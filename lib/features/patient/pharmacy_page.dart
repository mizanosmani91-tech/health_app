import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/bn.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../services/app_state.dart';
import '../../services/auth_service.dart';

String _waNumber(String phone) {
  final d = en(phone).replaceAll(RegExp(r'\D'), '');
  return d.startsWith('0') ? '88$d' : d;
}

Future<void> callPhone(String phone) => launchUrl(Uri.parse('tel:${en(phone).replaceAll(' ', '')}'));
Future<void> whatsapp(String phone, String text) =>
    launchUrl(Uri.parse('https://wa.me/${_waNumber(phone)}?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);

class PharmacyPage extends StatefulWidget {
  const PharmacyPage({super.key});
  @override
  State<PharmacyPage> createState() => _PharmacyPageState();
}

class _PharmacyPageState extends State<PharmacyPage> {
  int _tab = 0;
  final Set<String> _selected = {};
  final _extra = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final online = !context.watch<AppState>().offline;
    return Scaffold(
      appBar: AppBar(title: const Text('ফার্মেসি', style: TextStyle(fontWeight: FontWeight.w600))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 140), children: [
        Row(children: [
          Chip2('আমার ফার্মেসি', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
          const SizedBox(width: 8),
          if (online) Chip2('কোথায় কী আছে', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
          if (online) const SizedBox(width: 8),
          if (online) Chip2('আমার অনুরোধ', selected: _tab == 2, onTap: () => setState(() => _tab = 2)),
        ]),
        const SizedBox(height: 12),
        if (_tab == 0) _mine(context) else if (_tab == 1) _search(context) else _requests(context),
      ]),
    );
  }

  // ---- my pharmacies (local) ---------------------------------------------
  Widget _mine(BuildContext context) {
    final me = context.watch<AppState>().current!;
    return Q<(List<FavPharmacy>, List<Medicine>)>(
      load: () async => (await LocalDb.instance.pharmacies(), await LocalDb.instance.medicines(memberId: me.id)),
      builder: (c, d) {
        final (ph, meds) = d;
        final need = meds.where((m) => m.active && m.needsRebuy).toList();
        final text = 'আসসালামু আলাইকুম। আমার এই ওষুধগুলো লাগবে:\n${need.map((m) => '• ${m.name} (${bn(m.toBuyDays > 0 ? m.toBuyDays : 7)} দিনের)').join('\n')}\nআছে কি?';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Muted('পছন্দের ফার্মেসির নম্বর রাখুন। ওষুধ শেষ হলে এক ট্যাপে কল করুন বা তালিকা পাঠান।', size: 14)),
            IconButton.filledTonal(onPressed: () => _edit(context), icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 10),
          for (final f in ph)
            Card2(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(children: [
                Row(children: [
                  const IconTile(Icons.local_pharmacy, Tint.green),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Muted([if (f.area.isNotEmpty) f.area, f.phone].join(' · ')),
                  ])),
                  if (f.favorite) const Pill('প্রিয়', Color(0xFFFFF0D1), Color(0xFF8A5A0B)),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') _edit(context, f);
                      if (v == 'del') { await LocalDb.instance.deletePharmacy(f.id!); if (context.mounted) context.read<AppState>().touch(); }
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('সম্পাদনা')), PopupMenuItem(value: 'del', child: Text('মুছুন'))],
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlineButton2('কল', icon: Icons.call, onTap: () => callPhone(f.phone))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: OutlineButton2('তালিকা পাঠান', icon: Icons.chat, fg: Colors.white, bg: waGreen,
                      onTap: need.isEmpty ? () => context.toast('কিনতে হবে এমন কোনো ওষুধ নেই') : () => whatsapp(f.phone, text))),
                ]),
              ]),
            ),
          if (ph.isEmpty) const Empty(Icons.local_pharmacy, 'কোনো ফার্মেসি যোগ করা নেই।'),
          if (need.isNotEmpty) ...[
            const SectionTitle('পাঠানোর তালিকা'),
            Card2(padding: EdgeInsets.zero, child: Column(children: [
              for (final m in need)
                ListTile(
                  leading: Icon(Icons.check_box, color: context.pal.primary),
                  title: Text(m.name),
                  trailing: Muted(m.toBuyDays > 0 ? '${bn(m.toBuyDays)} দিনের বাকি' : '${bn(m.daysLeft)} দিন হাতে'),
                ),
            ])),
          ],
          const SizedBox(height: 10),
          const Muted('এখান থেকে ওষুধ কেনা বা ডেলিভারি হয় না।', size: 12, align: TextAlign.center),
        ]);
      },
    );
  }

  Future<void> _edit(BuildContext context, [FavPharmacy? f]) async {
    final name = TextEditingController(text: f?.name), area = TextEditingController(text: f?.area), phone = TextEditingController(text: f?.phone);
    var fav = f?.favorite ?? false;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(f == null ? 'ফার্মেসি যোগ' : 'ফার্মেসি সম্পাদনা'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'নাম')),
            const SizedBox(height: 8),
            TextField(controller: area, decoration: const InputDecoration(labelText: 'এলাকা')),
            const SizedBox(height: 8),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'মোবাইল নম্বর')),
            CheckboxListTile(value: fav, onChanged: (v) => set(() => fav = v ?? false), title: const Text('প্রিয়'), contentPadding: EdgeInsets.zero),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('বাতিল')),
            TextButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
                await LocalDb.instance.savePharmacy(FavPharmacy(id: f?.id, name: name.text.trim(), area: area.text.trim(), phone: phone.text.trim(), favorite: fav));
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('সংরক্ষণ'),
            ),
          ],
        ),
      ),
    );
    if (context.mounted) context.read<AppState>().touch();
  }

  // ---- stock search (Supabase) -------------------------------------------
  Future<List<Map<String, dynamic>>>? _results;

  Widget _search(BuildContext context) {
    final me = context.watch<AppState>().current!;
    return Q<List<Medicine>>(
      load: () => LocalDb.instance.medicines(memberId: me.id),
      builder: (c, meds) {
        final cand = meds.where((m) => m.active && m.needsRebuy).map((m) => m.name).toSet();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Muted('কোন ওষুধ খুঁজবেন বেছে নিন। দাম বা পরিমাণ দেখানো হয় না, শুধু আছে/কম/নেই।', size: 14),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in {...cand, ..._selected}) Chip2(n, selected: _selected.contains(n), onTap: () => setState(() => _selected.contains(n) ? _selected.remove(n) : _selected.add(n))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _extra, decoration: const InputDecoration(hintText: 'অন্য ওষুধের নাম', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)))),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: () {
              if (_extra.text.trim().isEmpty) return;
              setState(() { _selected.add(_extra.text.trim()); _extra.clear(); });
            }, icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 12),
          PrimaryButton('কোথায় আছে খুঁজুন', icon: Icons.search, onTap: _selected.isEmpty ? null : () => setState(() {
            _results = _doSearch(_selected.toList());
          })),
          const SizedBox(height: 16),
          if (_results != null)
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _results,
              builder: (c, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.hasError) return Muted('খোঁজা যায়নি: ${s.error}');
                return _resultList(context, s.data!, me);
              },
            ),
        ]);
      },
    );
  }

  /// Verified pharmacies, each with one public stock doc (name + in/low/out only).
  Future<List<Map<String, dynamic>>> _doSearch(List<String> names) async {
    if (!Config.hasBackend) return [];
    final db = AuthService.instance.db;
    final phs = (await db.collection('pharmacies').where('status', isEqualTo: 'verified').limit(50).get()).docs;
    final stocks = await Future.wait(phs.map((p) => db.collection('stockPublic').doc(p.id).get()));
    const rank = {'in': 3, 'low': 2, 'out': 1};
    final out = <Map<String, dynamic>>[];
    for (final (i, p) in phs.indexed) {
      final d = p.data();
      final sd = stocks[i].data();
      final items = ((sd?['items'] as Map?)?.values ?? const []).cast<Map>();
      for (final n in names) {
        final q = n.toLowerCase();
        var best = 'unknown';
        for (final it in items) {
          if (!('${it['n']} ${it['g'] ?? ''}'.toLowerCase().contains(q))) continue;
          final st = '${it['s']}';
          if ((rank[st] ?? 0) > (rank[best] ?? 0)) best = st;
        }
        out.add({
          'pharmacy_id': p.id, 'pharmacy_name': d['name'], 'address': d['address'], 'phone': d['phone'],
          'is_open': d['isOpen'], 'medicine_name': n, 'status': best,
          'updated_at': ts2(sd?['updatedAt'])?.toIso8601String(),
        });
      }
    }
    return out;
  }

  DateTime? ts2(dynamic v) => v is Timestamp ? v.toDate() : null;

  Widget _resultList(BuildContext context, List<Map<String, dynamic>> rows, Member me) {
    final byPh = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) { (byPh[r['pharmacy_id']] ??= []).add(r); }
    if (byPh.isEmpty) return const Empty(Icons.storefront, 'কাছাকাছি কোনো যাচাইকৃত ফার্মেসি পাওয়া যায়নি।');
    final entries = byPh.values.toList()..sort((a, b) => b.where((x) => x['status'] != 'out' && x['status'] != 'unknown').length.compareTo(a.where((x) => x['status'] != 'out' && x['status'] != 'unknown').length));
    return Column(children: [
      for (final list in entries)
        Builder(builder: (context) {
          final head = list.first;
          final have = list.where((x) => x['status'] == 'in' || x['status'] == 'low').length;
          return Card2(
            margin: const EdgeInsets.only(bottom: 12),
            padding: EdgeInsets.zero,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const IconTile(Icons.local_pharmacy, Tint.green),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(head['pharmacy_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                    Muted('${head['address'] ?? ''}${head['is_open'] == false ? ' · বন্ধ' : ''}'),
                  ])),
                  have == list.length ? Pill.ok('${bn(list.length)}টির ${bn(have)}টি আছে') : have == 0 ? const Pill.no('কোনোটাই নেই') : Pill.low('${bn(list.length)}টির ${bn(have)}টি আছে'),
                ]),
              ),
              for (final r in list)
                ListTile(
                  dense: true,
                  title: Text(r['medicine_name']),
                  trailing: switch (r['status']) {
                    'in' => const Pill.ok('আছে'),
                    'low' => const Pill.low('কম আছে'),
                    'out' => const Pill.no('নেই'),
                    _ => const Pill('জানা নেই', Color(0xFFEDF3F1), Color(0xFF5E736E)),
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                child: Column(children: [
                  Align(alignment: Alignment.centerLeft, child: Muted('স্টক আপডেট: ${r2(head['updated_at'])}', size: 12)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlineButton2('কল', icon: Icons.call, onTap: head['phone'] == null ? null : () => callPhone(head['phone']))),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: PrimaryButtonSmall('অনুরোধ পাঠান', () => _sendRequest(context, head, list, me))),
                  ]),
                ]),
              ),
            ]),
          );
        }),
      const Muted('স্টক দোকানের দেওয়া তথ্য। যাওয়ার আগে কল করে নিশ্চিত হয়ে নিন।', size: 12, align: TextAlign.center),
    ]);
  }

  String r2(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    return d == null ? '—' : '${relativeDays(d)} ${bnTime(d.hour, d.minute)}';
  }

  Future<void> _sendRequest(BuildContext context, Map<String, dynamic> head, List<Map<String, dynamic>> list, Member me) async {
    try {
      final a = AuthService.instance;
      await a.db.collection('requests').add({
        'pharmacyId': head['pharmacy_id'], 'pharmacyName': head['pharmacy_name'], 'pharmacyPhone': head['phone'],
        'patientId': a.user!.uid, 'patientName': me.name, 'status': 'new', 'replyMessage': null,
        'items': [for (final r in list) {'name': r['medicine_name'], 'days': 0, 'availability': 'pending'}],
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) context.toast('অনুরোধ পাঠানো হয়েছে');
      setState(() => _tab = 2);
    } catch (e) {
      if (context.mounted) context.toast('পাঠানো যায়নি: $e');
    }
  }

  // ---- my requests --------------------------------------------------------
  Widget _requests(BuildContext context) {
    final uid = AuthService.instance.user?.uid;
    return Q<List<Map<String, dynamic>>>(
      load: () async => (await AuthService.instance.db.collection('requests').where('patientId', isEqualTo: uid).get())
          .docs.map((d) => {...d.data(), 'id': d.id}).toList()
        ..sort((a, b) => (ts2(b['createdAt']) ?? DateTime.now()).compareTo(ts2(a['createdAt']) ?? DateTime.now())),
      builder: (c, rows) {
        if (rows.isEmpty) return const Empty(Icons.inbox, 'এখনো কোনো অনুরোধ পাঠাননি।');
        return Column(children: [
          for (final r in rows)
            Card2(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(r['pharmacyName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                  r['status'] == 'replied' ? const Pill.ok('উত্তর এসেছে') : const Pill.low('অপেক্ষায়'),
                ]),
                const SizedBox(height: 8),
                for (final i in (r['items'] as List))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(i['name'])),
                      switch (i['availability']) { 'yes' => const Pill.ok('আছে'), 'no' => const Pill.no('নেই'), _ => const Muted('—') },
                    ]),
                  ),
                if ((r['replyMessage'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card2(color: context.pal.soft, child: Row(children: [
                    Icon(Icons.chat, size: 18, color: context.pal.primaryDark), const SizedBox(width: 8),
                    Expanded(child: Text(r['replyMessage'])),
                  ])),
                ],
              ]),
            ),
        ]);
      },
    );
  }
}

class PrimaryButtonSmall extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const PrimaryButtonSmall(this.label, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => Material(
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(gradient: context.pal.gradient, borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(height: 44, child: Center(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))),
          ),
        ),
      );
}
