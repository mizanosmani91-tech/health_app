import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/bn.dart';
import '../../core/widgets.dart';
import '../../services/notification_service.dart';

/// Reminders matter for health, so this screen lets the person verify (and fix) everything Android needs
/// for a dose alarm to ring on time even when the app is closed and the phone is idle.
class ReminderCheckPage extends StatefulWidget {
  const ReminderCheckPage({super.key});
  @override
  State<ReminderCheckPage> createState() => _ReminderCheckPageState();
}

class _ReminderCheckPageState extends State<ReminderCheckPage> with WidgetsBindingObserver {
  ReminderHealth? _h;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load(); // came back from system settings
  }

  Future<void> _load() async {
    final h = await NotificationService.instance.health();
    if (mounted) setState(() => _h = h);
  }

  Widget _item(bool ok, String title, String why, Future<void> Function() fix) => Card2(
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.error, color: ok ? Colors.green : Colors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Muted(why, size: 13),
          ])),
          if (!ok) TextButton(onPressed: () async { await fix(); _load(); }, child: const Text('চালু করুন')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final h = _h;
    return FormPage(
      title: 'রিমাইন্ডার ঠিক আছে কিনা',
      children: h == null
          ? const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))]
          : [
              Card2(
                color: h.allGood ? const Color(0xFFE3F8EC) : const Color(0xFFFFF1D6),
                margin: const EdgeInsets.only(bottom: 14),
                child: Text(h.allGood ? 'সব ঠিক আছে। অ্যাপ বন্ধ থাকলেও ওষুধের সময় রিমাইন্ডার আসবে।' : 'নিচের কিছু অনুমতি বাকি। ওগুলো না দিলে রিমাইন্ডার দেরিতে আসতে পারে বা আসবে না।',
                    style: const TextStyle(height: 1.5)),
              ),
              _item(h.notifications, 'নোটিফিকেশনের অনুমতি', 'এটা ছাড়া কোনো রিমাইন্ডারই দেখা যাবে না।', NotificationService.instance.askNotifications),
              _item(h.exactAlarms, 'ঠিক সময়ে অ্যালার্ম', 'ফোন ঘুমিয়ে থাকলেও ঠিক মিনিটে বাজার জন্য।', NotificationService.instance.askExactAlarms),
              _item(h.batteryUnrestricted, 'ব্যাটারি সীমা নেই', 'ব্যাটারি সেভার অ্যাপ বন্ধ করে দিলে রিমাইন্ডার মিস হয়।', NotificationService.instance.askBattery),
              const SizedBox(height: 6),
              Card2(child: Text(
                'Xiaomi / Redmi / Realme / Oppo / Vivo / Samsung ফোনে এটাও করুন: অ্যাপের সেটিংসে গিয়ে "অটোস্টার্ট" চালু করুন এবং ব্যাটারি "কোনো সীমা নয় (No restrictions)" দিন। Recent apps-এ অ্যাপটি লক করে রাখাও ভালো।',
                style: TextStyle(color: context.pal.muted, height: 1.5, fontSize: 13.5))),
              const SizedBox(height: 10),
              OutlineButton2('অ্যাপের সেটিংস খুলুন', icon: Icons.settings, onTap: openAppSettings),
              const SizedBox(height: 10),
              PrimaryButton('পরীক্ষা: ১ মিনিট পরে একটা রিমাইন্ডার পাঠান', icon: Icons.notifications_active, onTap: () async {
                await NotificationService.instance.sendTest();
                if (context.mounted) context.toast('এখন অ্যাপ বন্ধ করে ১ মিনিট অপেক্ষা করুন, নোটিফিকেশন আসা উচিত');
              }),
              const SizedBox(height: 12),
              Center(child: Muted('এখন ${bn(h.pending)}টি রিমাইন্ডার ঠিক করা আছে', size: 13)),
            ],
    );
  }
}
