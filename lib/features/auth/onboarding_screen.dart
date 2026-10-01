import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/app_state.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _i = 0;

  static const _pages = [
    (Icons.health_and_safety, 'পরিবারের সব স্বাস্থ্য তথ্য, এক জায়গায়',
        'ভিজিট, ওষুধ, টেস্ট আর প্রেসক্রিপশন। ওষুধ খেতে ও ডাক্তারের কাছে যেতে সময়মতো মনে করিয়ে দেবে।'),
    (Icons.alarm, 'ওষুধ শেষ হওয়ার আগেই জানবেন',
        'কোন ওষুধ কত দিনের বাকি, কোনটা আবার কিনতে হবে — অ্যাপই মনে করিয়ে দেবে। ইন্টারনেট ছাড়াও চলে।'),
    (Icons.storefront, 'কোন ফার্মেসিতে ওষুধ আছে, দেখুন',
        'কাছের ফার্মেসিতে আপনার ওষুধ আছে কি না আগেই জেনে নিন। ফার্মেসি মালিকরাও এই অ্যাপেই যোগ দিতে পারেন।'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final last = _i == _pages.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFE4F5F1),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _ctrl,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) {
                final (icon, title, body) = _pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: 290, height: 290,
                      child: Stack(alignment: Alignment.center, children: [
                        Container(width: 210, height: 210, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFCDEBE4))),
                        Container(
                          width: 140, height: 140,
                          decoration: BoxDecoration(shape: BoxShape.circle, gradient: p.gradient),
                          child: Icon(icon, size: 70, color: Colors.white),
                        ),
                        const Positioned(left: 14, top: 30, child: IconTile(Icons.medication, Tint.purple, size: 64)),
                        const Positioned(right: 14, top: 46, child: IconTile(Icons.calendar_month, Tint.orange, size: 64)),
                        const Positioned(left: 26, bottom: 26, child: IconTile(Icons.description, Tint.blue, size: 64)),
                        const Positioned(right: 30, bottom: 14, child: IconTile(Icons.science, Tint.amber, size: 64)),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Text(title, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Color(0xFF0B4F45), height: 1.3)),
                    const SizedBox(height: 12),
                    Muted(body, size: 15, align: TextAlign.center),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _i ? 26 : 8, height: 8,
                decoration: BoxDecoration(color: i == _i ? p.primaryDark : const Color(0xFFBFE6DE), borderRadius: BorderRadius.circular(5)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(children: [
              PrimaryButton(last ? 'শুরু করুন' : 'পরের', onTap: () => last
                  ? context.read<AppState>().finishOnboarding()
                  : _ctrl.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)),
              TextButton(
                  onPressed: () => context.read<AppState>().finishOnboarding(),
                  child: Muted(last ? '' : 'এড়িয়ে যান', size: 15)),
            ]),
          ),
        ]),
      ),
    );
  }
}
