import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config.dart';
import '../../core/widgets.dart';
import '../../services/app_state.dart';
import '../../services/auth_service.dart';
import '../../services/prefs.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _google({bool owner = false}) async {
    setState(() => _busy = true);
    Prefs.ownerIntent = owner;
    try {
      await AuthService.instance.signInWithGoogle();
      if (mounted) await context.read<AppState>().signedIn();
    } catch (e) {
      Prefs.ownerIntent = false;
      if (mounted) context.toast('লগইন হয়নি: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: Column(children: [
        HeroHeader(
          child: SizedBox(
            height: 270,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 84, height: 84,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                child: Icon(Icons.favorite, size: 46, color: p.primaryDark),
              ),
              const SizedBox(height: 16),
              const Text('স্বাস্থ্য ডায়েরি', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('আপনার পরিবারের ডিজিটাল স্বাস্থ্য খাতা', style: TextStyle(color: Color(0xFFBFEDE3))),
            ]),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 28, 24, 24), children: [
            const Text('স্বাগতম', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Muted('Google দিয়ে এক ট্যাপে ঢুকুন। ওটিপি লাগবে না।', size: 15),
            const SizedBox(height: 22),
            OutlineButton2Big(busy: _busy, onTap: Config.hasBackend ? _google : null),
            if (!Config.hasBackend) ...[
              const SizedBox(height: 14),
              Card2(
                color: const Color(0xFFFFF0D1),
                child: const Text('সার্ভার কনফিগার করা নেই (API_BASE_URL)। '
                    'চাইলে নিচের বোতামে অফলাইন মোডে শুধু ব্যক্তিগত/পরিবারের অংশ চালিয়ে দেখতে পারেন।',
                    style: TextStyle(color: Color(0xFF6B4305), height: 1.5)),
              ),
              const SizedBox(height: 12),
              OutlineButton2('অফলাইন মোডে চালান', icon: Icons.cloud_off,
                  onTap: () => context.read<AppState>().continueOffline()),
            ],
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: _busy || !Config.hasBackend ? null : () => _google(owner: true),
                child: Text('ফার্মেসির মালিক? এখান থেকে ঢুকুন', style: TextStyle(color: context.pal.muted, fontSize: 14)),
              ),
            ),
            const SizedBox(height: 8),
            Card2(
              color: const Color(0xFFF0EDFF),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.verified_user, color: Color(0xFF5B4BD5), size: 26),
                SizedBox(width: 12),
                Expanded(
                  child: Text('আপনার স্বাস্থ্য তথ্য ফোনে আর আপনার নিজের Drive-এ থাকে। আমরা কিছু দেখি না।',
                      style: TextStyle(fontSize: 14, height: 1.55, color: Color(0xFF3B2F99))),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            const Muted('এগিয়ে গেলে আপনি শর্তাবলী ও প্রাইভেসি পলিসিতে সম্মত হচ্ছেন।', size: 12, align: TextAlign.center),
          ]),
        ),
      ]),
    );
  }
}

class OutlineButton2Big extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;
  const OutlineButton2Big({super.key, required this.busy, this.onTap});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: busy ? null : onTap,
            child: Container(
              height: 54,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(17), border: Border.all(color: context.pal.border, width: 1.5)),
              child: Center(
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('G', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Color(0xFF2A6FD6))),
                        SizedBox(width: 8),
                        Text('Google দিয়ে চালিয়ে যান', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ]),
              ),
            ),
          ),
        ),
      );
}
