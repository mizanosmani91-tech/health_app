import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'owner_ctx.dart';

String relativeTime(String iso) {
  final d = DateTime.parse(iso).toLocal();
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'এইমাত্র';
  if (m < 60) return '${bn(m)} মিনিট আগে';
  if (m < 60 * 24) return '${bn(m ~/ 60)} ঘণ্টা আগে';
  return '${bn(m ~/ (60 * 24))} দিন আগে';
}

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});
  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  String _f = 'new';

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    return Scaffold(
      appBar: AppBar(title: const Text('অনুরোধ', style: TextStyle(fontWeight: FontWeight.w600))),
      body: Q<List<Map<String, dynamic>>>(
        load: () => o.rows(o.db.from('med_requests').select('id,patient_name,status,created_at,med_request_items(id)')
            .eq('pharmacy_id', o.pid).eq('status', _f).order('created_at', ascending: false).limit(100)),
        builder: (c, rows) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 140), children: [
          Row(children: [
            Chip2('নতুন', selected: _f == 'new', onTap: () => setState(() => _f = 'new')),
            const SizedBox(width: 8),
            Chip2('উত্তর দেওয়া', selected: _f == 'replied', onTap: () => setState(() => _f = 'replied')),
          ]),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Empty(Icons.inbox, 'কোনো অনুরোধ নেই।'),
          for (final r in rows)
            Card2(
              margin: const EdgeInsets.only(bottom: 10),
              onTap: () => context.push(RequestDetailPage(id: r['id'])),
              child: Row(children: [
                IconTile(Icons.person, Tint.all[(r['patient_name'] as String).hashCode.abs() % 6], round: true),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['patient_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  Muted('${bn((r['med_request_items'] as List).length)}টি ওষুধ · ${relativeTime(r['created_at'])}'),
                ])),
                Icon(Icons.chevron_right, color: context.pal.muted),
              ]),
            ),
        ]),
      ),
    );
  }
}

class RequestDetailPage extends StatefulWidget {
  final String id;
  const RequestDetailPage({super.key, required this.id});
  @override
  State<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends State<RequestDetailPage> {
  final _msg = TextEditingController();
  final Map<String, String> _avail = {};
  bool _busy = false, _init = false;

  Future<void> _send(OwnerCtx o, List items) async {
    setState(() => _busy = true);
    try {
      for (final i in items) {
        final a = _avail[i['id']] ?? 'pending';
        if (a != i['availability']) await o.db.from('med_request_items').update({'availability': a}).eq('id', i['id']);
      }
      await o.db.from('med_requests').update({
        'status': 'replied', 'reply_message': _msg.text.trim(), 'replied_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.id);
      if (!mounted) return;
      o.touch();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) context.toast('পাঠানো যায়নি: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _seg(String label, bool on, Color color, VoidCallback t) => GestureDetector(
        onTap: t,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: on ? color : Colors.transparent, borderRadius: BorderRadius.circular(9)),
          child: Text(label, style: TextStyle(color: on ? Colors.white : context.pal.muted, fontSize: 13)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    return Scaffold(
      appBar: AppBar(title: const Text('অনুরোধ', style: TextStyle(fontWeight: FontWeight.w600))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: o.db.from('med_requests').select('id,patient_name,status,reply_message,created_at,med_request_items(id,medicine_name,days,availability)').eq('id', widget.id).single(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final r = s.data!;
          final items = (r['med_request_items'] as List).cast<Map<String, dynamic>>();
          if (!_init) {
            _init = true;
            for (final i in items) { _avail[i['id']] = i['availability']; }
            _msg.text = r['reply_message'] ?? '';
          }
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 20), children: [
                Card2(child: Row(children: [
                  IconTile(Icons.person, Tint.orange, size: 48, round: true), const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['patient_name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    Muted('${relativeTime(r['created_at'])} পাঠিয়েছেন'),
                  ]),
                ])),
                const SectionTitle('ওষুধের তালিকা'),
                Card2(padding: EdgeInsets.zero, child: Column(children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i['medicine_name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                          if ((i['days'] ?? 0) > 0) Muted('${bn(i['days'])} দিনের'),
                        ])),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: const Color(0xFFEFEEF8), borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            _seg('আছে', _avail[i['id']] == 'yes', waGreen, () => setState(() => _avail[i['id']] = 'yes')),
                            _seg('নেই', _avail[i['id']] == 'no', const Color(0xFFE0532A), () => setState(() => _avail[i['id']] = 'no')),
                          ]),
                        ),
                      ]),
                    ),
                ])),
                const SectionTitle('রোগীকে বার্তা (ঐচ্ছিক)'),
                TextField(controller: _msg, maxLines: 3, decoration: const InputDecoration(hintText: 'বিকেল ৫টার পর দোকান থেকে নিতে পারবেন।')),
                const SizedBox(height: 8),
                const Muted('দাম, পেমেন্ট ও ডেলিভারি অ্যাপে নেই। লেনদেন দোকানেই হবে।', size: 12, align: TextAlign.center),
              ]),
            ),
            SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                child: PrimaryButton('রোগীকে জানান', icon: Icons.send, busy: _busy, onTap: () => _send(o, items)))),
          ]);
        },
      ),
    );
  }
}
