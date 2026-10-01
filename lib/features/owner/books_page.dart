import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'owner_ctx.dart';

class BooksPage extends StatefulWidget {
  const BooksPage({super.key});
  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  int _tab = 0; // 0 আয়-ব্যয়, 1 বাকির খাতা
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('হিসাব', style: TextStyle(fontWeight: FontWeight.w600)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(children: [
                Chip2('আয়-ব্যয়', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
                const SizedBox(width: 6),
                Chip2('বাকি', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
              ]),
            ),
          ],
        ),
        body: _tab == 0 ? const _Ledger() : const _Khata(),
      );
}

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

Future<Map<String, String>?> _entryDialog(BuildContext context, String title, {bool phone = false, String titleLabel = 'বিবরণ'}) async {
  final a = TextEditingController(), b = TextEditingController(), p = TextEditingController();
  return showDialog<Map<String, String>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: a, decoration: InputDecoration(labelText: titleLabel)),
        const SizedBox(height: 8),
        TextField(controller: b, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'টাকা (৳)')),
        if (phone) ...[const SizedBox(height: 8), TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'মোবাইল (ঐচ্ছিক)'))],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('বাতিল')),
        TextButton(
          onPressed: () {
            if (a.text.trim().isEmpty || (double.tryParse(en(b.text.trim())) ?? 0) <= 0) return;
            Navigator.pop(c, {'a': a.text.trim(), 'b': en(b.text.trim()), 'p': en(p.text.trim())});
          },
          child: const Text('সংরক্ষণ'),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ আয়-ব্যয়
class _Ledger extends StatefulWidget {
  const _Ledger();
  @override
  State<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends State<_Ledger> {
  int _range = 0; // 0 আজ, 1 সপ্তাহ, 2 মাস

  DateTime get _from {
    final t = dateOnly(DateTime.now());
    return _range == 0 ? t : _range == 1 ? t.subtract(const Duration(days: 6)) : DateTime(t.year, t.month, 1);
  }

  Future<void> _add(OwnerCtx o, String kind) async {
    final r = await _entryDialog(context, kind == 'income' ? 'আয় যোগ' : 'ব্যয় যোগ');
    if (r == null) return;
    await o.ref.collection('ledger').add({
      'kind': kind, 'title': r['a'], 'amount': double.parse(r['b']!),
      'entryDate': isoDate(DateTime.now()), 'createdAt': FieldValue.serverTimestamp(),
    });
    o.touch();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    final week = dateOnly(DateTime.now()).subtract(const Duration(days: 6));
    return Q<List<Map<String, dynamic>>>(
      load: () async => (await o.ref.collection('ledger')
              .where('entryDate', isGreaterThanOrEqualTo: isoDate(_from.isBefore(week) ? _from : week)).get())
          .docs.map(withId).toList()
        ..sort((a, b) => '${b['entryDate']}${ts(b['createdAt'])?.millisecondsSinceEpoch ?? 0}'
            .compareTo('${a['entryDate']}${ts(a['createdAt'])?.millisecondsSinceEpoch ?? 0}')),
      builder: (c, all) {
        final rows = all.where((r) => !DateTime.parse(r['entryDate']).isBefore(_from)).toList();
        final inc = rows.where((r) => r['kind'] == 'income').fold<num>(0, (a, r) => a + _n(r['amount']));
        final exp = rows.where((r) => r['kind'] == 'expense').fold<num>(0, (a, r) => a + _n(r['amount']));
        final days = [for (var i = 6; i >= 0; i--) dateOnly(DateTime.now()).subtract(Duration(days: i))];
        final perDay = [for (final d in days) all.where((r) => r['kind'] == 'income' && r['entryDate'] == isoDate(d)).fold<num>(0, (a, r) => a + _n(r['amount']))];
        final maxV = perDay.fold<num>(1, (a, b) => b > a ? b : a);
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 140), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: context.pal.gradient, borderRadius: BorderRadius.circular(26)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (final (i, l) in ['আজ', 'সপ্তাহ', 'মাস'].indexed)
                  Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(
                    onTap: () => setState(() => _range = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(color: _range == i ? Colors.white : Colors.white24, borderRadius: BorderRadius.circular(99)),
                      child: Text(l, style: TextStyle(fontSize: 13, color: _range == i ? context.pal.primaryDark : Colors.white)),
                    ),
                  )),
              ]),
              const SizedBox(height: 12),
              Text(_range == 0 ? 'আজকের লাভ' : _range == 1 ? 'গত ৭ দিনের লাভ' : 'এই মাসের লাভ', style: const TextStyle(fontSize: 13, color: Color(0xFFD6D1FF))),
              Text(bnMoney(inc - exp), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _mini('আয়', bnMoney(inc), const Color(0xFFBFF5D6))),
                const SizedBox(width: 10),
                Expanded(child: _mini('ব্যয়', bnMoney(exp), const Color(0xFFFFD3C4))),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          Card2(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('গত ৭ দিনের আয়', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            SizedBox(
              height: 74,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (final (i, v) in perDay.indexed)
                  Container(width: 26, height: 6 + 64 * (v / maxV).toDouble(),
                      decoration: BoxDecoration(color: i == 6 ? context.pal.primaryDark : const Color(0xFFCFCBF5), borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(4)))),
              ]),
            ),
          ])),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _addBtn('আয়', Icons.add, const [Color(0xFF25B866), Color(0xFF157A3D)], () => _add(o, 'income'))),
            const SizedBox(width: 10),
            Expanded(child: _addBtn('ব্যয়', Icons.remove, const [Color(0xFFEC6A3E), Color(0xFFC4421A)], () => _add(o, 'expense'))),
          ]),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Empty(Icons.account_balance_wallet, 'এই সময়ে কোনো হিসাব নেই।'),
          Card2(padding: EdgeInsets.zero, child: Column(children: [
            for (final r in rows)
              Dismissible(
                key: ValueKey(r['id']),
                direction: DismissDirection.endToStart,
                background: Container(color: noBg, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: noFg)),
                confirmDismiss: (_) => confirm(context, 'এই হিসাবটি মুছবেন?'),
                onDismissed: (_) async { await o.ref.collection('ledger').doc(r['id']).delete(); o.touch(); },
                child: ListTile(
                  leading: IconTile(r['kind'] == 'income' ? Icons.payments : Icons.local_shipping, r['kind'] == 'income' ? Tint.green : Tint.orange, size: 38),
                  title: Text(r['title']),
                  subtitle: Muted(bnDateShort(DateTime.parse(r['entryDate']))),
                  trailing: Text('${r['kind'] == 'income' ? '+' : '−'}${bn(_n(r['amount']).toStringAsFixed(0))}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: r['kind'] == 'income' ? okFg : noFg)),
                ),
              ),
          ])),
        ]);
      },
    );
  }

  Widget _mini(String l, String v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: TextStyle(fontSize: 12, color: c)),
          Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _addBtn(String l, IconData i, List<Color> g, VoidCallback t) => Material(
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          decoration: BoxDecoration(gradient: LinearGradient(colors: g), borderRadius: BorderRadius.circular(15)),
          child: InkWell(
            borderRadius: BorderRadius.circular(15), onTap: t,
            child: SizedBox(height: 46, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(i, color: Colors.white), const SizedBox(width: 6),
              Text(l, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            ])),
          ),
        ),
      );
}

// ------------------------------------------------------------------ বাকির খাতা
class _Khata extends StatefulWidget {
  const _Khata();
  @override
  State<_Khata> createState() => _KhataState();
}

class _KhataState extends State<_Khata> {
  String _dir = 'receivable';
  String _q = '';

  Future<void> _add(OwnerCtx o) async {
    final r = await _entryDialog(context, _dir == 'receivable' ? 'কার কাছে পাবো' : 'কাকে দেবো', phone: true, titleLabel: 'নাম');
    if (r == null) return;
    await o.ref.collection('khata').add({
      'direction': _dir, 'partyName': r['a'], 'amount': double.parse(r['b']!), 'paid': 0,
      'phone': r['p']!.isEmpty ? null : r['p'], 'createdAt': FieldValue.serverTimestamp(),
    });
    o.touch();
  }

  Future<void> _pay(OwnerCtx o, Map<String, dynamic> e) async {
    final left = _n(e['amount']) - _n(e['paid']);
    final ctrl = TextEditingController(text: bn(left.toStringAsFixed(0)));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${e['partyName']} — ${_dir == 'receivable' ? 'আদায়' : 'পরিশোধ'}'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'কত টাকা? (বাকি ${bnMoney(left)})')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('বাতিল')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('সংরক্ষণ'))],
      ),
    );
    if (ok != true) return;
    final amt = (double.tryParse(en(ctrl.text.trim())) ?? 0).clamp(0, left).toDouble();
    if (amt <= 0) return;
    // Money actually collected / paid out also lands in the books (one atomic write).
    final batch = o.db.batch();
    batch.update(o.ref.collection('khata').doc(e['id']), {'paid': FieldValue.increment(amt)});
    batch.set(o.ref.collection('ledger').doc(), {
      'kind': _dir == 'receivable' ? 'income' : 'expense',
      'title': _dir == 'receivable' ? 'বাকি আদায়: ${e['partyName']}' : 'পরিশোধ: ${e['partyName']}',
      'amount': amt, 'entryDate': isoDate(DateTime.now()), 'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    o.touch();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(backgroundColor: context.pal.primaryDark, foregroundColor: Colors.white, onPressed: () => _add(o), child: const Icon(Icons.add)),
      ),
      body: Q<List<Map<String, dynamic>>>(
        load: () async => (await o.ref.collection('khata').where('direction', isEqualTo: _dir).get()).docs.map(withId).toList()
          ..sort((a, b) => (ts(a['createdAt']) ?? DateTime.now()).compareTo(ts(b['createdAt']) ?? DateTime.now())),
        builder: (c, all) {
          final open = all.where((e) => _n(e['paid']) < _n(e['amount'])).toList();
          final rows = open.where((e) => _q.isEmpty || '${e['partyName']}'.contains(_q)).toList();
          final total = open.fold<num>(0, (a, e) => a + _n(e['amount']) - _n(e['paid']));
          final late = open.where((e) => DateTime.now().difference((ts(e['createdAt']) ?? DateTime.now())).inDays > 20).length;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 140), children: [
            Row(children: [
              Expanded(child: Chip2('আমি পাবো', selected: _dir == 'receivable', onTap: () => setState(() => _dir = 'receivable'))),
              const SizedBox(width: 8),
              Expanded(child: Chip2('আমি দেবো', selected: _dir == 'payable', onTap: () => setState(() => _dir = 'payable'))),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(gradient: context.pal.gradient, borderRadius: BorderRadius.circular(26)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_dir == 'receivable' ? 'মোট পাবো' : 'মোট দেবো', style: const TextStyle(fontSize: 13, color: Color(0xFFD6D1FF))),
                Text(bnMoney(total), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: Colors.white)),
                Text('${bn(open.length)} জন${late > 0 ? ' · ${bn(late)} জনের ২০ দিনের বেশি' : ''}', style: const TextStyle(fontSize: 13, color: Color(0xFFFFD3C4))),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'নাম খুঁজুন')),
            const SizedBox(height: 12),
            if (rows.isEmpty) const Empty(Icons.menu_book, 'কোনো বাকি নেই।'),
            Card2(padding: EdgeInsets.zero, child: Column(children: [
              for (final e in rows)
                Builder(builder: (context) {
                  final days = DateTime.now().difference((ts(e['createdAt']) ?? DateTime.now())).inDays;
                  final left = _n(e['amount']) - _n(e['paid']);
                  return ListTile(
                    onTap: () => _pay(o, e),
                    leading: IconTile(Icons.person, Tint.all[('${e['partyName']}').hashCode.abs() % 6], round: true),
                    title: Text(e['partyName'], style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(days == 0 ? 'আজ' : '${bn(days)} দিন আগে থেকে', style: TextStyle(fontSize: 13, color: days > 20 ? noFg : context.pal.muted)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(bnMoney(left), style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (days > 20) const Pill.no('দেরি'),
                      ]),
                      if (_dir == 'receivable' && e['phone'] != null)
                        IconButton(
                          icon: Icon(Icons.notifications, color: context.pal.primaryDark),
                          tooltip: 'মনে করান',
                          onPressed: () {
                            final n = en('${e['phone']}').replaceAll(RegExp(r'\D'), '');
                            final text = 'আসসালামু আলাইকুম ${e['partyName']}, ${o.pharmacy!['name']}-এ আপনার ${bnMoney(left)} বাকি আছে। সুবিধামতো পরিশোধ করবেন।';
                            launchUrl(Uri.parse('https://wa.me/${n.startsWith('0') ? '88$n' : n}?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
                          },
                        ),
                    ]),
                  );
                }),
            ])),
            const Padding(padding: EdgeInsets.only(top: 8), child: Muted('নামে চাপলে আদায়/পরিশোধ লিখতে পারবেন।', size: 12, align: TextAlign.center)),
          ]);
        },
      ),
    );
  }
}
