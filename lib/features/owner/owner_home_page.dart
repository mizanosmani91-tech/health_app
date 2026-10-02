import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'owner_ctx.dart';
import 'requests_page.dart';

class OwnerHomePage extends StatelessWidget {
  final void Function(int) go;
  const OwnerHomePage({super.key, required this.go});

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    final ph = o.pharmacy!;
    return Q<List<Map<String, dynamic>>>(
      load: () => o.api.list('/requests', query: {'as': 'owner'}),
      builder: (c, reqs) {
        final today = dateOnly(DateTime.now());
        final fresh = reqs.where((r) => r['status'] == 'new').toList();
        final todays = reqs.where((r) => !dateOnly((ts(r['createdAt']) ?? DateTime.now())).isBefore(today)).length;
        final replied = reqs.where((r) => r['status'] == 'replied').length;
        final regulars = reqs.map((r) => r['patientId']).toSet().length;
        Widget stat(String n, String l, Tint t) => Expanded(
              child: Container(
                margin: const EdgeInsets.all(6), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: t.fg)),
                  Text(l, style: TextStyle(fontSize: 13, color: t.fg)),
                ]),
              ),
            );
        return ListView(padding: EdgeInsets.zero, children: [
          HeroHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('স্বাগতম', style: TextStyle(fontSize: 13, color: Color(0xFFD6D1FF))),
              Text(ph['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(Icons.circle, size: 12, color: ph['isOpen'] == true ? const Color(0xFF7CF0A8) : Colors.white54),
                  const SizedBox(width: 10),
                  Expanded(child: Text(ph['isOpen'] == true ? 'এখন খোলা' : 'এখন বন্ধ', style: const TextStyle(fontWeight: FontWeight.w500))),
                  Switch(
                    value: ph['isOpen'] == true, activeThumbColor: Colors.white, activeTrackColor: waGreen,
                    onChanged: (v) async {
                      await o.updatePharmacy({'isOpen': v});
                    },
                  ),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 140),
            child: Column(children: [
              if (!o.verified)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Card2(
                    color: const Color(0xFFFFF0D1),
                    child: Row(children: [
                      const Icon(Icons.schedule, color: Color(0xFFA86A08)), const SizedBox(width: 10),
                      Expanded(child: Text(ph['status'] == 'rejected' ? 'আপনার আবেদন গৃহীত হয়নি। প্রোফাইলে তথ্য ঠিক করে আবার চেষ্টা করুন।' : 'যাচাই চলছে। যাচাই শেষ হলে গ্রাহকরা আপনার দোকান দেখতে পাবে।',
                          style: const TextStyle(color: Color(0xFF6B4305), height: 1.5))),
                    ]),
                  ),
                ),
              Row(children: [stat(bn(fresh.length), 'নতুন অনুরোধ', Tint.orange), stat(bn(replied), 'উত্তর দেওয়া', Tint.green)]),
              Row(children: [stat(bn(todays), 'আজকের মোট', Tint.blue), stat(bn(regulars), 'মোট গ্রাহক', Tint.purple)]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionTitle('নতুন অনুরোধ', trailing: TextButton(onPressed: () => go(1), child: const Text('সব দেখুন'))),
                  if (fresh.isEmpty) const Empty(Icons.inbox, 'নতুন কোনো অনুরোধ নেই।'),
                  for (final r in fresh.take(5))
                    Card2(
                      margin: const EdgeInsets.only(bottom: 10),
                      onTap: () => context.push(RequestDetailPage(id: r['id'])),
                      child: Row(children: [
                        IconTile(Icons.person, Tint.all[(r['patientName'] as String).hashCode.abs() % 6], round: true),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r['patientName'], style: const TextStyle(fontWeight: FontWeight.w600)),
                          Muted('${bn((r['items'] as List).length)}টি ওষুধ · ${relativeTime(ts(r['createdAt']))}'),
                        ])),
                        const Pill.no('নতুন'),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
