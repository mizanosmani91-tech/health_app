import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../services/app_state.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/prefs.dart';
import 'member_form.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  Widget _row(IconData icon, Tint t, String title, {String? sub, Widget? trailing, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            IconTile(icon, t, size: 38),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title),
              if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: context.pal.primary)),
            ])),
            trailing ?? Icon(Icons.chevron_right, color: context.pal.muted),
          ]),
        ),
      );

  Future<void> _time(String slot, String label) async {
    final cur = Prefs.slotMinutes(slot);
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60), helpText: '$label ওষুধের সময়');
    if (t == null) return;
    Prefs.setSlotMinutes(slot, t.hour * 60 + t.minute);
    await NotificationService.instance.rescheduleAll();
    setState(() {});
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.backupNow();
      if (mounted) context.toast('Drive-এ ব্যাকআপ হয়েছে');
    } catch (e) {
      if (mounted) context.toast('ব্যাকআপ হয়নি: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (!await confirm(context, 'এই ফোনের বর্তমান সব তথ্য মুছে Drive-এর সর্বশেষ ব্যাকআপ বসানো হবে। চালিয়ে যাবেন?', yes: 'রিস্টোর')) return;
    setState(() => _busy = true);
    try {
      final ok = await BackupService.instance.restoreLatest();
      if (!mounted) return;
      if (ok) {
        await context.read<AppState>().refresh();
        if (mounted) context.toast('রিস্টোর হয়েছে');
      } else {
        context.toast('Drive-এ কোনো ব্যাকআপ পাওয়া যায়নি');
      }
    } catch (e) {
      if (mounted) context.toast('রিস্টোর হয়নি: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final user = AuthService.instance.user;
    final last = Prefs.lastBackupMs;
    String t(String slot) { final m = Prefs.slotMinutes(slot); return bnTime(m ~/ 60, m % 60); }
    return ListView(padding: EdgeInsets.zero, children: [
      HeroHeader(
        child: Row(children: [
          Container(
            width: 64, height: 64, alignment: Alignment.center,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Text(s.members.firstOrNull?.initials ?? '?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: context.pal.primaryDark)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.members.firstOrNull?.name ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            Text(user?.email ?? (s.offline ? 'অফলাইন মোড' : ''), style: const TextStyle(fontSize: 13, color: Color(0xFFBFEDE3))),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
              child: Text('${bn(s.members.length)} জন সদস্য', style: const TextStyle(fontSize: 12)),
            ),
          ])),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
        child: Column(children: [
          Card2(padding: EdgeInsets.zero, margin: const EdgeInsets.only(bottom: 12), child: Column(children: [
            _row(Icons.group, Tint.green, 'পরিবারের সদস্য', onTap: () => context.push(const _MembersPage())),
            _row(Icons.notifications, Tint.amber, 'রিমাইন্ডার', trailing: Switch(
              value: Prefs.remindersOn,
              onChanged: (v) async { Prefs.remindersOn = v; await NotificationService.instance.rescheduleAll(); setState(() {}); },
            )),
            _row(Icons.wb_sunny, Tint.amber, 'সকালের ওষুধের সময়', trailing: Muted(t('morning'), size: 14), onTap: () => _time('morning', 'সকালের')),
            _row(Icons.light_mode, Tint.amber, 'দুপুরের ওষুধের সময়', trailing: Muted(t('noon'), size: 14), onTap: () => _time('noon', 'দুপুরের')),
            _row(Icons.nightlight, Tint.purple, 'রাতের ওষুধের সময়', trailing: Muted(t('night'), size: 14), onTap: () => _time('night', 'রাতের')),
          ])),
          if (!s.offline)
            Card2(padding: EdgeInsets.zero, margin: const EdgeInsets.only(bottom: 12), child: Column(children: [
              _row(Icons.cloud_upload, Tint.blue, 'Drive-এ ব্যাকআপ করুন',
                  sub: last == null ? 'এখনো ব্যাকআপ হয়নি' : 'শেষ ব্যাকআপ: ${relativeDays(DateTime.fromMillisecondsSinceEpoch(last))}',
                  trailing: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  onTap: _busy ? null : _backup),
              _row(Icons.cloud_download, Tint.blue, 'Drive থেকে রিস্টোর', onTap: _busy ? null : _restore),
            ])),
          Card2(padding: EdgeInsets.zero, margin: const EdgeInsets.only(bottom: 12), child: Column(children: [
            _row(Icons.lock, Tint.purple, 'অ্যাপ লক', trailing: Switch(
              value: Prefs.appLock,
              onChanged: (v) async {
                if (v) {
                  try {
                    final la = LocalAuthentication();
                    if (!await la.isDeviceSupported()) { if (context.mounted) context.toast('ফোনে স্ক্রিন লক সেট করুন'); return; }
                    if (!await la.authenticate(localizedReason: 'অ্যাপ লক চালু করতে নিশ্চিত করুন')) return;
                  } catch (_) { return; }
                }
                Prefs.appLock = v;
                setState(() {});
              },
            )),
            _row(Icons.language, Tint.pink, 'ভাষা', trailing: const Muted('বাংলা', size: 14)),
            _row(Icons.delete, Tint.green, 'রিসাইকেল বিন', onTap: () => context.push(const _BinPage())),
          ])),
          Card2(
            color: const Color(0xFFFFE9E0),
            onTap: () async { if (await confirm(context, 'লগআউট করবেন?')) s.signOut(); },
            child: const Row(children: [
              Icon(Icons.logout, color: Color(0xFFD9532A)), SizedBox(width: 12),
              Text('লগআউট', style: TextStyle(color: Color(0xFFB23E19), fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _MembersPage extends StatelessWidget {
  const _MembersPage();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('পরিবারের সদস্য')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.pal.primaryDark, foregroundColor: Colors.white,
        onPressed: () => context.push(const MemberForm()), child: const Icon(Icons.add)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final m in s.members)
          Card2(
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => context.push(MemberForm(member: m)),
            child: Row(children: [
              CircleAvatar(backgroundColor: context.pal.soft, child: Text(m.initials, style: TextStyle(color: context.pal.primaryDark))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Muted([if (m.relation.isNotEmpty) m.relation, if (m.age != null) '${bn(m.age!)} বছর', if (m.bloodGroup.isNotEmpty) m.bloodGroup].join(' · ')),
              ])),
            ]),
          ),
      ]),
    );
  }
}

class _BinPage extends StatefulWidget {
  const _BinPage();
  @override
  State<_BinPage> createState() => _BinPageState();
}

class _BinPageState extends State<_BinPage> {
  static const _tables = {'medicines': 'ওষুধ', 'visits': 'ভিজিট', 'tests': 'টেস্ট'};

  Future<List<(String, Map<String, Object?>)>> _load() async => [
        for (final t in _tables.keys) for (final r in await LocalDb.instance.trashed(t)) (t, r),
      ];

  String _title(String t, Map<String, Object?> r) =>
      t == 'visits' ? '${(r['doctor'] ?? '') == '' ? (r['place'] ?? 'ভিজিট') : r['doctor']}' : '${r['name']}';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('রিসাইকেল বিন')),
        body: Q<List<(String, Map<String, Object?>)>>(
          load: _load,
          builder: (c, rows) => rows.isEmpty
              ? const Empty(Icons.delete_outline, 'বিন খালি।')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final (t, r) in rows)
                    Card2(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_title(t, r), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Muted(_tables[t]!),
                        ])),
                        TextButton(
                          onPressed: () async { await LocalDb.instance.restore(t, r['id'] as int); if (context.mounted) { context.read<AppState>().touch(); setState(() {}); } },
                          child: const Text('ফিরিয়ে আনুন'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever, color: noFg),
                          onPressed: () async {
                            if (await confirm(context, 'চিরতরে মুছবেন?')) { await LocalDb.instance.purge(t, r['id'] as int); if (mounted) setState(() {}); }
                          },
                        ),
                      ]),
                    ),
                ]),
        ),
      );
}
