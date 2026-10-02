import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog.dart';
import '../../services/api.dart';
import 'scan_page.dart';
import 'owner_ctx.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String _f = 'all';
  String _q = '';

  bool _expiring(Map<String, dynamic> r) {
    final e = DateTime.tryParse('${r['expiry']}');
    return e != null && e.difference(DateTime.now()).inDays <= 90;
  }

  /// Scan a pack: known barcode -> open that item, unknown -> new item with the barcode filled in.
  Future<void> _scan(BuildContext context, OwnerCtx o) async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code == null || !context.mounted) return;
    try {
      final item = await o.api.get('/stock/barcode/$code') as Map<String, dynamic>;
      if (context.mounted) {
        context.toast('চেনা ওষুধ: ${item['name']}');
        await context.push(StockFormPage(item: item));
      }
    } on ApiException catch (e) {
      if (e.status != 404) {
        if (context.mounted) context.toast('$e');
        return;
      }
      if (context.mounted) {
        context.toast('নতুন ওষুধ। নাম লিখে সংরক্ষণ করুন, পরের বার স্ক্যান করলেই সব ভরবে।');
        await context.push(StockFormPage(barcode: code));
      }
    }
  }

  Future<void> _setStatus(OwnerCtx o, String id, String s) async {
    await o.setStockStatus(id, s);
    o.touch();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('স্টক তালিকা', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'বারকোড স্ক্যান',
            onPressed: () => _scan(context, o),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          backgroundColor: context.pal.primaryDark, foregroundColor: Colors.white,
          onPressed: () => context.push(const StockFormPage()), child: const Icon(Icons.add)),
      ),
      body: Q<List<Map<String, dynamic>>>(
        load: () => o.api.list('/stock'),
        builder: (c, all) {
          final rows = all.where((r) {
            if (_q.isNotEmpty && !('${r['name']} ${r['genericName'] ?? ''}').toLowerCase().contains(_q.toLowerCase())) return false;
            return switch (_f) { 'in' => r['status'] == 'in', 'low' => r['status'] == 'low', 'out' => r['status'] == 'out', 'exp' => _expiring(r), _ => true };
          }).toList();
          final buy = all.where((r) => r['status'] != 'in' || _expiring(r)).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 140), children: [
            Muted('${bn(all.length)}টি ওষুধ'),
            const SizedBox(height: 8),
            TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ওষুধের নাম খুঁজুন')),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (k, l) in [('all', 'সব'), ('in', 'আছে'), ('low', 'কম'), ('out', 'নেই'), ('exp', 'মেয়াদ কাছে')])
                  Padding(padding: const EdgeInsets.only(right: 8), child: Chip2(l, selected: _f == k, onTap: () => setState(() => _f = k))),
              ]),
            ),
            if (buy.isNotEmpty) ...[
              const SizedBox(height: 10),
              OutlineButton2('কিনতে হবে এমন ${bn(buy.length)}টির তালিকা পাঠান', icon: Icons.send, onTap: () {
                final text = 'কিনতে হবে:\n${buy.map((r) => '• ${r['name']}${r['status'] == 'out' ? ' (নেই)' : r['status'] == 'low' ? ' (কম)' : ' (মেয়াদ কাছে)'}').join('\n')}';
                launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
              }),
            ],
            const SizedBox(height: 12),
            if (rows.isEmpty) const Empty(Icons.inventory_2, 'কোনো ওষুধ নেই। + চেপে যোগ করুন।'),
            Card2(padding: EdgeInsets.zero, child: Column(children: [
              for (final r in rows)
                InkWell(
                  onTap: () => context.push(StockFormPage(item: r)),
                  onLongPress: () async {
                    if (await confirm(context, '"${r['name']}" স্টক থেকে মুছবেন?')) {
                      await o.deleteStock(r['id']);
                      o.touch();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                        Muted([if (r['genericName'] != null) r['genericName'], if (_expiring(r)) 'মেয়াদ ${r['expiry']}'].join(' · ')),
                      ])),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: const Color(0xFFEFEEF8), borderRadius: BorderRadius.circular(11)),
                        child: Row(children: [
                          for (final (k, l, col) in [('in', 'আছে', waGreen), ('low', 'কম', const Color(0xFFE8A21A)), ('out', 'নেই', const Color(0xFFE0532A))])
                            GestureDetector(
                              onTap: () => _setStatus(o, r['id'], k),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: r['status'] == k ? col : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                                child: Text(l, style: TextStyle(fontSize: 12, color: r['status'] == k ? Colors.white : context.pal.muted)),
                              ),
                            ),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ])),
            if (rows.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Muted('সম্পাদনা করতে চাপুন, মুছতে চেপে ধরুন। শুধু আছে/কম/নেই রোগী দেখে, দাম দেখে না।', size: 12, align: TextAlign.center)),
          ]);
        },
      ),
    );
  }
}

/// Add (from catalog search or by typing a name) or edit a stock item.
class StockFormPage extends StatefulWidget {
  final Map<String, dynamic>? item;
  final String? barcode;
  const StockFormPage({super.key, this.item, this.barcode});
  @override
  State<StockFormPage> createState() => _StockFormPageState();
}

class _StockFormPageState extends State<StockFormPage> {
  final _key = GlobalKey<FormState>();
  late final i = widget.item;
  late final _name = TextEditingController(text: i?['name']);
  late final _generic = TextEditingController(text: i?['genericName']);
  late final _qty = TextEditingController(text: i?['qty'] == null ? '' : bn(i!['qty']));
  late final _unit = TextEditingController(text: i?['unit'] ?? 'পাতা');
  late final _buy = TextEditingController(text: i?['buyPrice'] == null ? '' : bn(i!['buyPrice']));
  late final _sell = TextEditingController(text: i?['sellPrice'] == null ? '' : bn(i!['sellPrice']));
  late final _batch = TextEditingController(text: i?['batchNo']);
  late final _barcode = TextEditingController(text: i?['barcode'] ?? widget.barcode);
  late String _form = i?['form'] ?? 'ট্যাবলেট';
  late String _status = i?['status'] ?? 'in';
  late final _expiry = TextEditingController(text: i?['expiry'] == null ? '' : bn((i!['expiry'] as String).substring(0, 7).split('-').reversed.join('/')));
  List<CatalogItem> _hits = [];

  double? _num(TextEditingController c) => double.tryParse(en(c.text.trim()));

  /// "08/2027" -> 2027-08-31 (last day, so it never expires early).
  String? _parseExpiry() {
    final m = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(en(_expiry.text.trim()));
    if (m == null) return null;
    final mo = int.parse(m[1]!), y = int.parse(m[2]!);
    if (mo < 1 || mo > 12) return null;
    return isoDate(DateTime(y, mo + 1, 0));
  }

  void _search(String q) {
    final t = q.trim();
    setState(() => _hits = t.length < 2 ? [] : medicineCatalog.where((m) => m.name.contains(t) || m.generic.contains(t)).take(6).toList());
  }

  Future<void> _save(OwnerCtx o) async {
    if (!_key.currentState!.validate()) return;
    final data = {
      'name': _name.text.trim(),
      'genericName': _generic.text.trim().isEmpty ? null : _generic.text.trim(),
      'form': _form, 'qty': _num(_qty), 'unit': _unit.text.trim(), 'buyPrice': _num(_buy), 'sellPrice': _num(_sell),
      'expiry': _parseExpiry(), 'batchNo': _batch.text.trim().isEmpty ? null : _batch.text.trim(),
      'barcode': _barcode.text.trim().isEmpty ? null : en(_barcode.text.trim()), 'status': _status,
    };
    try {
      await o.saveStock(i?['id'], data);
      if (!mounted) return;
      o.touch();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) context.toast('সংরক্ষণ হয়নি: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    return Form(
      key: _key,
      child: FormPage(
        title: i == null ? 'ওষুধ যোগ' : 'ওষুধ সম্পাদনা',
        action: PrimaryButton('সংরক্ষণ করুন', onTap: () => _save(o)),
        children: [
          Field('ওষুধের নাম', controller: _name, icon: Icons.search, onChanged: _search, validator: (v) => (v ?? '').trim().isEmpty ? 'নাম লিখুন' : null),
          for (final h in _hits)
            Card2(
              margin: const EdgeInsets.only(bottom: 6),
              onTap: () => setState(() {
                _name.text = h.name; _generic.text = h.generic; _form = h.form; _hits = [];
              }),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Muted('${h.maker} · ${h.form}'),
                ])),
                Pill('+ নিন', context.pal.soft, context.pal.primaryDark),
              ]),
            ),
          Row(children: [
            Expanded(child: Field('বারকোড (ঐচ্ছিক)', controller: _barcode, icon: Icons.qr_code, keyboard: TextInputType.number)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IconButton.filledTonal(
                tooltip: 'স্ক্যান',
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () async {
                  final c = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
                  if (c != null) setState(() => _barcode.text = c);
                },
              ),
            ),
          ]),
          Field('জেনেরিক নাম (ঐচ্ছিক)', controller: _generic, icon: Icons.science),
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('ধরন', style: TextStyle(fontWeight: FontWeight.w500))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in ['ট্যাবলেট', 'সিরাপ', 'ক্যাপসুল', 'ইনজেকশন', 'অন্যান্য']) Chip2(f, selected: _form == f, onTap: () => setState(() => _form = f)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Field('পরিমাণ', controller: _qty, keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: Field('একক', controller: _unit)),
          ]),
          Row(children: [
            Expanded(child: Field('কেনা দাম (৳)', controller: _buy, keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: Field('বিক্রয় দাম (৳)', controller: _sell, keyboard: TextInputType.number)),
          ]),
          Row(children: [
            Expanded(child: Field('মেয়াদ (মাস/সাল) যেমন ০৮/২০২৭', controller: _expiry, keyboard: TextInputType.datetime,
                validator: (v) => (v ?? '').trim().isEmpty || _parseExpiry() != null ? null : 'ঠিক ফরম্যাট: ০৮/২০২৭')),
            const SizedBox(width: 10),
            Expanded(child: Field('ব্যাচ নম্বর', controller: _batch)),
          ]),
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('রোগীরা যা দেখবে', style: TextStyle(fontWeight: FontWeight.w500))),
          Row(children: [
            for (final (k, l) in [('in', 'আছে'), ('low', 'কম'), ('out', 'নেই')])
              Padding(padding: const EdgeInsets.only(right: 8), child: Chip2(l, selected: _status == k, onTap: () => setState(() => _status = k))),
          ]),
          const SizedBox(height: 14),
          Card2(color: context.pal.soft, child: Row(children: [
            Icon(Icons.notifications_active, color: context.pal.primaryDark), const SizedBox(width: 10),
            const Expanded(child: Text('মেয়াদ শেষের ৯০ দিনের মধ্যে ওষুধটি "মেয়াদ কাছে" তালিকায় দেখাবে। দাম শুধু আপনি দেখবেন।', style: TextStyle(fontSize: 13, height: 1.5))),
          ])),
        ],
      ),
    );
  }
}
