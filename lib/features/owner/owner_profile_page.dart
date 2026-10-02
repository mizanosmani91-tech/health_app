import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/app_state.dart';
import '../../services/auth_service.dart';
import 'owner_ctx.dart';

class OwnerProfilePage extends StatelessWidget {
  const OwnerProfilePage({super.key});

  Future<void> _edit(BuildContext context, OwnerCtx o, String col, String label) async {
    final ctrl = TextEditingController(text: '${o.pharmacy![col] ?? ''}');
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(label),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('বাতিল')), TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('সংরক্ষণ'))],
      ),
    );
    if (v == null || v.isEmpty) return;
    await o.updatePharmacy({col: v});
  }

  Future<void> _time(BuildContext context, OwnerCtx o, String col, String label) async {
    final cur = '${o.pharmacy![col]}'.split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1])), helpText: label);
    if (t == null) return;
    await o.updatePharmacy({col: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'});
  }

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    final p = o.pharmacy!;
    String hm(String s) { final a = s.split(':'); return bnTimeStr(int.parse(a[0]), int.parse(a[1])); }
    Widget row(IconData i, Tint t, String text, {VoidCallback? onTap, Widget? trailing, String? sub}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              IconTile(i, t, size: 38), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: context.pal.muted)),
              ])),
              trailing ?? (onTap == null ? const SizedBox() : Icon(Icons.edit, size: 20, color: context.pal.muted)),
            ]),
          ),
        );
    final st = p['status'];
    return ListView(padding: EdgeInsets.zero, children: [
      HeroHeader(
        child: Row(children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.local_pharmacy, size: 34, color: context.pal.primaryDark)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: st == 'verified' ? const Color(0x40A0FFC0) : Colors.white24, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(st == 'verified' ? Icons.verified : Icons.schedule, size: 14),
                const SizedBox(width: 4),
                Text(st == 'verified' ? 'যাচাইকৃত' : st == 'rejected' ? 'গৃহীত হয়নি' : 'যাচাই চলছে', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ])),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
        child: Column(children: [
          Card2(padding: EdgeInsets.zero, margin: const EdgeInsets.only(bottom: 12), child: Column(children: [
            row(Icons.location_on, Tint.purple, p['address'], onTap: () => _edit(context, o, 'address', 'ঠিকানা')),
            row(Icons.call, Tint.green, p['phone'], onTap: () => _edit(context, o, 'phone', 'মোবাইল নম্বর')),
            row(Icons.schedule, Tint.blue, 'খোলা: ${hm(p['openFrom'])} — ${hm(p['openTo'])}', onTap: () async {
              await _time(context, o, 'openFrom', 'খোলার সময়');
              if (context.mounted) await _time(context, o, 'openTo', 'বন্ধের সময়');
            }),
            row(Icons.event_busy, Tint.amber, 'সাপ্তাহিক ছুটি', sub: p['weeklyOff'] ?? 'নেই', onTap: () => _edit(context, o, 'weeklyOff', 'সাপ্তাহিক ছুটি (যেমন: শুক্রবার দুপুর)')),
          ])),
          Card2(padding: EdgeInsets.zero, margin: const EdgeInsets.only(bottom: 12), child: Column(children: [
            row(Icons.notifications, Tint.purple, 'নতুন অনুরোধের নোটিফিকেশন', trailing: Switch(
              value: p['notifyNew'] == true,
              onChanged: (v) => o.updatePharmacy({'notifyNew': v}),
            )),
            row(Icons.badge, Tint.green, 'লাইসেন্স ${p['licenseNo']}', sub: st == 'verified' ? 'যাচাই সম্পন্ন' : 'যাচাই চলছে'),
          ])),
          Card2(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.only(bottom: 12),
            child: row(Icons.swap_horiz, Tint.green, 'আমার স্বাস্থ্য-অ্যাপে যান', sub: 'নিজের ও পরিবারের ওষুধ, ভিজিট, টেস্ট',
                onTap: () => context.read<AppState>().switchRole(UserRole.patient),
                trailing: Icon(Icons.chevron_right, color: context.pal.muted)),
          ),
          Card2(
            color: const Color(0xFFFFE9E0),
            onTap: () async { if (await confirm(context, 'লগআউট করবেন?') && context.mounted) context.read<AppState>().signOut(); },
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

String bnTimeStr(int h, int m) => bnTime(h, m);
