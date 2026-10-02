import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../services/app_state.dart';
import '../../core/config.dart';
import 'prescription_scan_page.dart';
import 'test_form.dart';
import 'visit_form.dart';

class _Item {
  final DateTime date;
  final Visit? visit;
  final TestRecord? test;
  _Item(this.date, {this.visit, this.test});
}

class VisitsPage extends StatefulWidget {
  const VisitsPage({super.key});
  @override
  State<VisitsPage> createState() => _VisitsPageState();
}

class _VisitsPageState extends State<VisitsPage> {
  int _filter = 0; // 0 all, 1 visits, 2 tests

  Future<List<_Item>> _load(Member m) async {
    final db = LocalDb.instance;
    final items = <_Item>[
      for (final v in await db.visits(m.id!)) _Item(v.date, visit: v),
      for (final t in await db.tests(m.id!)) _Item(t.doneDate ?? t.dueDate ?? DateTime.now(), test: t),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().current!;
    return Scaffold(
      appBar: AppBar(title: Text('${me.name}-এর ভিজিট ও টেস্ট', style: const TextStyle(fontWeight: FontWeight.w600))),
      body: FabSlot(
        onPressed: () => showModalBottomSheet(
            context: context,
            builder: (c) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(leading: const Icon(Icons.medical_services), title: const Text('নতুন ভিজিট'),
                    onTap: () { Navigator.pop(c); context.push(VisitForm(member: me)); }),
                if (Config.hasBackend)
                  ListTile(leading: const Icon(Icons.document_scanner), title: const Text('প্রেসক্রিপশনের ছবি থেকে'),
                      onTap: () { Navigator.pop(c); context.push(PrescriptionScanPage(member: me)); }),
                ListTile(leading: const Icon(Icons.science), title: const Text('নতুন টেস্ট'),
                    onTap: () { Navigator.pop(c); context.push(TestForm(member: me)); }),
              ]),
            ),
          ),
        child: Q<List<_Item>>(
        load: () => _load(me),
        builder: (c, all) {
          final items = all.where((i) => _filter == 0 || (_filter == 1 ? i.visit != null : i.test != null)).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 140), children: [
            Row(children: [
              for (final (i, l) in ['সব', 'ভিজিট', 'টেস্ট'].indexed)
                Padding(padding: const EdgeInsets.only(right: 8), child: Chip2(l, selected: _filter == i, onTap: () => setState(() => _filter = i))),
            ]),
            const SizedBox(height: 12),
            if (items.isEmpty) const Empty(Icons.event_note, 'এখনো কিছু যোগ করা হয়নি।', centered: true),
            for (final i in items) i.visit != null ? _visitTile(context, me, i.visit!) : _testTile(context, me, i.test!),
          ]);
        },
      ),
      ),
    );
  }

  Widget _visitTile(BuildContext context, Member me, Visit v) {
    final upcoming = v.nextVisit != null && !v.nextVisit!.isBefore(dateOnly(DateTime.now()));
    return Card2(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(VisitForm(member: me, visit: v)),
      child: Row(children: [
        v.prescriptions.isEmpty
            ? const IconTile(Icons.medical_services, Tint.orange)
            : ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(v.prescriptions.first), width: 42, height: 42, fit: BoxFit.cover)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.doctor.isEmpty ? (v.place.isEmpty ? 'ভিজিট' : v.place) : v.doctor, style: const TextStyle(fontWeight: FontWeight.w600)),
            Muted([bnDate(v.date), if (v.problem.isNotEmpty) v.problem].join(' · ')),
            if (upcoming) Padding(padding: const EdgeInsets.only(top: 4), child: Pill.low('পরবর্তী ভিজিট ${bnDateShort(v.nextVisit!)} · ${relativeDays(v.nextVisit!)}')),
          ]),
        ),
        if (v.fee > 0) Text(bnMoney(v.fee), style: const TextStyle(fontWeight: FontWeight.w600)),
        _menu(context, 'visits', v.id!),
      ]),
    );
  }

  Widget _testTile(BuildContext context, Member me, TestRecord t) => Card2(
        margin: const EdgeInsets.only(bottom: 10),
        onTap: () => context.push(TestForm(member: me, test: t)),
        child: Row(children: [
          const IconTile(Icons.science, Tint.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Muted(t.doneDate != null
                  ? '${bnDate(t.doneDate!)}${t.place.isEmpty ? '' : ' · ${t.place}'}'
                  : t.dueDate != null ? 'করতে হবে ${bnDate(t.dueDate!)}' : ''),
            ]),
          ),
          if (t.doneDate == null && t.dueDate != null) Pill.low(relativeDays(t.dueDate!)) else if (t.doneDate != null) const Pill.ok('করা হয়েছে'),
          _menu(context, 'tests', t.id!),
        ]),
      );

  Widget _menu(BuildContext context, String table, int id) => PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'del' && await confirm(context, 'রিসাইকেল বিনে পাঠাবেন?')) {
            await LocalDb.instance.softDelete(table, id);
            if (context.mounted) context.read<AppState>().touch();
          }
        },
        itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('মুছুন'))],
      );
}
