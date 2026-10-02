import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/bn.dart';
import '../../core/widgets.dart';
import '../../services/notification_service.dart';
import '../../services/prefs.dart';

/// Step-by-step guide: one thing at a time, a big button that opens the exact system screen, and when the
/// person comes back we re-check and move on to whatever is still missing. Ends with a real test reminder.
class ReminderCheckPage extends StatefulWidget {
  const ReminderCheckPage({super.key});
  @override
  State<ReminderCheckPage> createState() => _ReminderCheckPageState();
}

enum _Step { notifications, exact, battery, autostart, test }

const _picky = ['xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'oneplus', 'vivo', 'iqoo', 'huawei', 'honor', 'samsung', 'tecno', 'infinix', 'itel', 'symphony', 'walton'];

class _ReminderCheckPageState extends State<ReminderCheckPage> with WidgetsBindingObserver {
  List<_Step> _steps = const [];
  Map<_Step, bool> _done = {};
  String _maker = '';
  bool _loading = true, _testSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && !_loading) _refresh(); // back from a system screen
  }

  Future<void> _init() async {
    if (Platform.isAndroid) _maker = (await DeviceInfoPlugin().androidInfo).manufacturer.toLowerCase();
    final needsAutostart = _picky.any(_maker.contains);
    _steps = [_Step.notifications, _Step.exact, _Step.battery, if (needsAutostart) _Step.autostart, _Step.test];
    await _refresh();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    final h = await NotificationService.instance.health();
    // Granting a permission changes what can be scheduled, so re-plan the reminders now.
    NotificationService.instance.rescheduleAll();
    if (!mounted) return;
    setState(() => _done = {
          _Step.notifications: h.notifications,
          _Step.exact: h.exactAlarms,
          _Step.battery: h.batteryUnrestricted,
          _Step.autostart: Prefs.autostartDone,
          _Step.test: _testSent && Prefs.reminderTestOk,
        });
  }

  Future<void> _openAutostart() async {
    Prefs.reminderWizardSeen = true;
    try {
      if (_maker.contains('xiaomi') || _maker.contains('redmi') || _maker.contains('poco')) {
        await const AndroidIntent(componentName: 'com.miui.permcenter.autostart.AutoStartManagementActivity', package: 'com.miui.securitycenter').launch();
        return;
      }
      if (_maker.contains('oppo') || _maker.contains('realme') || _maker.contains('oneplus')) {
        await const AndroidIntent(componentName: 'com.coloros.safecenter.permission.startup.StartupAppListActivity', package: 'com.coloros.safecenter').launch();
        return;
      }
    } catch (_) {/* fall through to the app's own settings */}
    await openAppSettings();
  }

  _Info _info(_Step s) => switch (s) {
        _Step.notifications => _Info(Icons.notifications_active, 'নোটিফিকেশন চালু করুন',
            'এটা না দিলে ওষুধের সময় কিছুই দেখা যাবে না। পরের পর্দায় "অনুমতি দিন / Allow" চাপুন।', 'চালু করুন', Permission.notification.request),
        _Step.exact => _Info(Icons.alarm_on, 'ঠিক সময়ে অ্যালার্ম',
            'এটা চালু থাকলে ফোন ঘুমিয়ে থাকলেও ঠিক মিনিটে রিমাইন্ডার বাজবে। যে পর্দা খুলবে সেখানে অ্যাপের পাশের সুইচটা চালু করুন, তারপর ব্যাক চাপুন।', 'সেটিংস খুলুন', () async {
              Prefs.reminderWizardSeen = true;
              await Permission.scheduleExactAlarm.request();
            }),
        _Step.battery => _Info(Icons.battery_saver, 'ব্যাটারি সীমা তুলে দিন',
            'ব্যাটারি বাঁচাতে ফোন অ্যাপ বন্ধ করে দেয়, তখন রিমাইন্ডার মিস হয়। পরের পর্দায় "অনুমতি দিন / Allow" চাপুন।', 'চালু করুন', Permission.ignoreBatteryOptimizations.request),
        _Step.autostart => _Info(Icons.rocket_launch, 'অটোস্টার্ট চালু করুন',
            'আপনার ফোনে (${_maker.isEmpty ? 'এই' : _maker}) এটা না দিলে অ্যাপ বন্ধ থাকলে রিমাইন্ডার আসে না। যে পর্দা খুলবে সেখানে "স্বাস্থ্য ডায়েরি"-র পাশের সুইচ চালু করুন, তারপর ব্যাক চেপে এখানে ফিরে "করেছি" চাপুন।',
            'সেটিংস খুলুন', _openAutostart,
            confirm: 'আমি চালু করেছি', onConfirm: () async { Prefs.autostartDone = true; }),
        _Step.test => _Info(Icons.fact_check, 'শেষ ধাপ: পরীক্ষা',
            _testSent
                ? 'এইমাত্র একটা নোটিফিকেশন এসেছে? না এলে নোটিফিকেশনের অনুমতি/ফোনের সেটিংস সমস্যা। এবার অ্যাপটা বন্ধ করুন (Recent apps থেকেও সরিয়ে দিন) এবং ১ মিনিট অপেক্ষা করুন। দ্বিতীয় নোটিফিকেশন এলে নিচের "পেয়েছি" চাপুন।'
                : '"পরীক্ষা পাঠান" চাপলে এখনই একটা নোটিফিকেশন আসবে, আর ১ মিনিট পরে আরেকটা। দ্বিতীয়টা অ্যাপ বন্ধ অবস্থায় এলেই সব ঠিক।',
            _testSent ? 'আবার পাঠান' : 'পরীক্ষা পাঠান', () async {
              Prefs.reminderWizardSeen = true;
              await NotificationService.instance.showNow();
              await NotificationService.instance.sendTest();
              _testSent = true;
            },
            confirm: _testSent ? 'পেয়েছি, সব ঠিক' : null, onConfirm: () async { Prefs.reminderTestOk = true; }),
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const FormPage(title: 'রিমাইন্ডার সেটআপ', children: [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))]);
    // The first step that is not done yet. The test step only counts once the person confirmed it.
    final cur = _steps.where((s) => _done[s] != true).firstOrNull;
    final idx = cur == null ? _steps.length : _steps.indexOf(cur) + 1;
    return FormPage(
      title: 'রিমাইন্ডার সেটআপ',
      children: [
        LinearProgressIndicator(value: (idx - 1) / _steps.length, minHeight: 8, borderRadius: BorderRadius.circular(8)),
        const SizedBox(height: 8),
        Muted(cur == null ? 'সব ধাপ শেষ' : 'ধাপ ${bn(idx)} / ${bn(_steps.length)}', size: 13),
        const SizedBox(height: 16),
        if (cur == null) ...[
          const Icon(Icons.check_circle, size: 96, color: Colors.green),
          const SizedBox(height: 12),
          const Center(child: Text('সব ঠিক আছে!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          const Text('অ্যাপ বন্ধ থাকলেও ওষুধের সময় রিমাইন্ডার আসবে। ফোন বদলালে বা অ্যাপ আবার ইনস্টল করলে এই সেটআপ আবার করতে হবে।', textAlign: TextAlign.center, style: TextStyle(height: 1.5)),
          const SizedBox(height: 20),
          PrimaryButton('শেষ করুন', icon: Icons.done, onTap: () { Prefs.reminderWizardSeen = true; Navigator.pop(context); }),
        ] else ...[
          Builder(builder: (c) {
            final i = _info(cur);
            return Column(children: [
              Icon(i.icon, size: 84, color: c.pal.primaryDark),
              const SizedBox(height: 14),
              Text(i.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(i.body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15.5, height: 1.6)),
              const SizedBox(height: 24),
              PrimaryButton(i.button, onTap: () async {
                try {
                  await i.action();
                } catch (e) {
                  if (c.mounted) c.toast('ব্যর্থ: $e'); // show the real reason instead of failing silently
                }
                await _refresh();
              }),
              if (i.confirm != null) ...[
                const SizedBox(height: 10),
                OutlineButton2(i.confirm!, onTap: () async { await i.onConfirm!(); await _refresh(); }),
              ],
              if (cur != _Step.notifications) ...[
                const SizedBox(height: 6),
                TextButton(onPressed: () async { await _skip(cur); }, child: const Text('এটা এড়িয়ে যান (প্রস্তাবিত নয়)')),
              ],
            ]);
          }),
        ],
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final s in _steps)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(_done[s] == true ? Icons.check_circle : Icons.circle_outlined, size: 16, color: _done[s] == true ? Colors.green : Colors.black26)),
        ]),
      ],
    );
  }

  Future<void> _skip(_Step s) async {
    if (s == _Step.autostart) Prefs.autostartDone = true;
    if (s == _Step.test) Prefs.reminderTestOk = true;
    if (s == _Step.exact || s == _Step.battery) {
      // Not grantable: leave it undone but move past it in this session.
      _steps = _steps.where((x) => x != s).toList();
    }
    await _refresh();
  }
}

class _Info {
  final IconData icon;
  final String title, body, button;
  final Future<void> Function() action;
  final String? confirm;
  final Future<void> Function()? onConfirm;
  _Info(this.icon, this.title, this.body, this.button, this.action, {this.confirm, this.onConfirm});
}
