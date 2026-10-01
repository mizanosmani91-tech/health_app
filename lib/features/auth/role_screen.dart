import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/app_state.dart';
import '../../services/auth_service.dart';

/// Shown once after the first Google login: patient/family or pharmacy owner.
class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key});
  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  UserRole _sel = UserRole.patient;
  bool _busy = false;

  Widget _opt(UserRole r, IconData icon, Tint t, String title, String sub) {
    final on = _sel == r;
    final accent = r == UserRole.owner ? Palette.owner.primaryDark : Palette.patient.primaryDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: on ? accent : Colors.transparent, width: 2)),
        child: Card2(
          padding: const EdgeInsets.all(18),
          onTap: () => setState(() => _sel = r),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: on ? accent : t.bg, borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, size: 30, color: on ? Colors.white : t.fg),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
              const SizedBox(height: 3),
              Muted(sub),
            ])),
            if (on) Icon(Icons.check_circle, color: accent, size: 26),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('আপনি কে?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Muted('আপনার ধরন বেছে নিন।', size: 15),
              const SizedBox(height: 28),
              _opt(UserRole.patient, Icons.family_restroom, Tint.green, 'রোগী বা পরিবার', 'ভিজিট, ওষুধ ও টেস্টের হিসাব রাখব'),
              _opt(UserRole.owner, Icons.storefront, Tint.purple, 'ফার্মেসি মালিক', 'আমার দোকান যুক্ত করব'),
              const Spacer(),
              PrimaryButton('চালিয়ে যান', busy: _busy, onTap: () async {
                setState(() => _busy = true);
                try {
                  await context.read<AppState>().chooseRole(_sel);
                } catch (e) {
                  if (context.mounted) context.toast('সেভ হয়নি: $e');
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              }),
            ]),
          ),
        ),
      );
}
