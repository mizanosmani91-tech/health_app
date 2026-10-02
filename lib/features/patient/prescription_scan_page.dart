import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../data/prescription_draft.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../services/images.dart';

/// Photo of a prescription -> AI draft -> person checks every medicine -> saved on the phone.
/// The AI only suggests; nothing is saved (and no dose is trusted) until the person confirms it.
class PrescriptionScanPage extends StatefulWidget {
  final Member member;
  const PrescriptionScanPage({super.key, required this.member});
  @override
  State<PrescriptionScanPage> createState() => _PrescriptionScanPageState();
}

class _PrescriptionScanPageState extends State<PrescriptionScanPage> {
  bool _agree = false, _busy = false;
  String? _image;
  PrescriptionDraft? _draft;
  String? _error;
  final _doctor = TextEditingController(), _problem = TextEditingController();

  @override
  void dispose() { _doctor.dispose(); _problem.dispose(); super.dispose(); }

  Future<void> _scan(bool camera) async {
    final path = await pickImage(camera: camera, maxWidth: 1600, quality: 78);
    if (path == null) return;
    setState(() { _image = path; _busy = true; _error = null; _draft = null; });
    try {
      final bytes = await File(path).readAsBytes();
      final r = await Api.instance.post('/prescriptions/parse', {
        'consent': true, 'mediaType': 'image/jpeg', 'image': base64Encode(bytes),
      });
      final d = PrescriptionDraft.fromJson((r as Map)['draft'] as Map<String, dynamic>);
      if (!mounted) return;
      _doctor.text = d.doctor; _problem.text = d.problem;
      setState(() { _draft = d; _error = d.readable ? null : 'এটা পড়া গেল না। আরও পরিষ্কার আলোয় পুরো কাগজের ছবি তুলে আবার চেষ্টা করুন।'; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.status) {
            503 => 'এই সুবিধা এখনো চালু হয়নি।',
            429 => 'আজকের সীমা শেষ। কাল আবার চেষ্টা করুন, বা হাতে লিখে যোগ করুন।',
            502 => 'পড়া গেল না। আরও পরিষ্কার ছবি দিয়ে আবার চেষ্টা করুন।',
            _ => e.toString(),
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final d = _draft!;
    final db = LocalDb.instance;
    final date = d.visitDate ?? dateOnly(DateTime.now());
    final vid = await db.saveVisit(Visit(
      memberId: widget.member.id!, date: date, doctor: d.doctor.trim(), problem: d.problem.trim(),
      nextVisit: d.nextVisit, prescriptions: [?_image]));
    for (final m in d.medicines) {
      await db.saveMedicine(m.toMedicine(widget.member.id!, vid, dateOnly(DateTime.now())));
    }
    for (final t in d.tests.where((t) => t.include && t.name.trim().isNotEmpty)) {
      await db.saveTest(TestRecord(memberId: widget.member.id!, name: t.name.trim(), dueDate: dateOnly(DateTime.now())));
    }
    if (!mounted) return;
    context.read<AppState>().touch();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('সংরক্ষণ হয়েছে। ওষুধ কেনা হলে ওষুধের পাতায় কেনা-দিন যোগ করুন।')));
  }

  Future<DateTime?> _pickDate(DateTime? init, {bool future = false}) => showDatePicker(
        context: context, initialDate: init ?? DateTime.now(), firstDate: DateTime(2000),
        lastDate: DateTime.now().add(Duration(days: future ? 365 * 3 : 0)));

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return FormPage(
      title: 'ছবি থেকে প্রেসক্রিপশন',
      action: d == null || !d.readable ? null : PrimaryButton('সংরক্ষণ করুন', onTap: d.canSave ? _save : null),
      children: [
        if (d == null || !d.readable) ..._intro(context),
        if (d != null && d.readable) ..._review(context, d),
      ],
    );
  }

  List<Widget> _intro(BuildContext context) => [
        Card2(child: Text(
          'প্রেসক্রিপশনের ছবি তুললে এআই পড়ে একটা খসড়া বানাবে। ডাক্তারের হাতের লেখা সবসময় ঠিক পড়া যায় না, তাই আপনি প্রতিটা ওষুধ নিজে মিলিয়ে নিশ্চিত না করা পর্যন্ত কিছুই সেভ হবে না।',
          style: TextStyle(color: context.pal.muted, height: 1.5))),
        CheckboxListTile(
          value: _agree, onChanged: (v) => setState(() => _agree = v ?? false), contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('ছবিটা পড়ার জন্য একটি এআই সেবায় পাঠানো হবে, তা মেনে নিলাম। সার্ভারে ছবি বা ফলাফল জমা রাখা হয় না।', style: TextStyle(fontSize: 13.5))),
        const SizedBox(height: 8),
        if (_busy)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('পড়া হচ্ছে… একটু সময় লাগতে পারে')])))
        else ...[
          PrimaryButton('ক্যামেরায় ছবি তুলুন', icon: Icons.photo_camera, onTap: _agree ? () => _scan(true) : null),
          const SizedBox(height: 10),
          OutlineButton2('গ্যালারি থেকে নিন', icon: Icons.photo_library, onTap: _agree ? () => _scan(false) : null),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, height: 1.4))),
      ];

  List<Widget> _review(BuildContext context, PrescriptionDraft d) {
    final unsure = d.medicines.where((m) => !m.ready).length;
    return [
      if (_image != null)
        GestureDetector(
          onTap: () => showDialog(context: context, builder: (c) => Dialog(child: InteractiveViewer(child: Image.file(File(_image!))))),
          child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(_image!), height: 150, width: double.infinity, fit: BoxFit.cover)),
        ),
      const Padding(padding: EdgeInsets.only(top: 6), child: Muted('ছবিতে চাপ দিয়ে বড় করে দেখুন, আর নিচের তথ্য কাগজের সাথে মেলান।')),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: unsure == 0 ? const Pill.ok('সব ওষুধ নিশ্চিত') : Pill.low('$unsureটি ওষুধ মিলিয়ে নিশ্চিত করা বাকি'),
      ),
      Field('ডাক্তার', controller: _doctor, icon: Icons.person, onChanged: (v) => d.doctor = v),
      Field('সমস্যা', controller: _problem, icon: Icons.healing, onChanged: (v) => d.problem = v),
      Field(d.visitDate == null ? 'ভিজিটের তারিখ (না পেলে আজ)' : 'ভিজিট: ${bnDate(d.visitDate!)}', icon: Icons.event, readOnly: true,
          onTap: () async { final x = await _pickDate(d.visitDate); if (x != null) setState(() => d.visitDate = x); }),
      Field(d.nextVisit == null ? 'পরবর্তী ভিজিট (ঐচ্ছিক)' : 'পরবর্তী ভিজিট: ${bnDate(d.nextVisit!)}', icon: Icons.event_repeat, readOnly: true,
          onTap: () async { final x = await _pickDate(d.nextVisit, future: true); if (x != null) setState(() => d.nextVisit = x); }),
      if (d.advice.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Muted('পরামর্শ: ${d.advice}')),
      const SectionTitle('ওষুধ'),
      if (d.medicines.isEmpty) const Muted('কোনো ওষুধ পাওয়া যায়নি।'),
      for (final m in d.medicines) _medCard(context, d, m),
      OutlineButton2('ওষুধ যোগ করুন', icon: Icons.add, onTap: () => setState(() => d.medicines.add(DraftMedicine(name: '')..confirmed = true))),
      const SectionTitle('টেস্ট'),
      if (d.tests.isEmpty) const Muted('কোনো টেস্ট পাওয়া যায়নি।'),
      for (final t in d.tests)
        CheckboxListTile(value: t.include, onChanged: (v) => setState(() => t.include = v ?? true), contentPadding: EdgeInsets.zero, title: Text(t.name)),
    ];
  }

  Widget _medCard(BuildContext context, PrescriptionDraft d, DraftMedicine m) {
    final warn = m.uncertain && !m.confirmed || (m.confirmed && !m.ready);
    Widget slot(String label, double? v, ValueChanged<double?> set) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: SizedBox(width: double.infinity, child: Text(label, textAlign: TextAlign.center)),
              selected: (v ?? 0) > 0,
              onSelected: (s) => setState(() { set(s ? 1 : 0); }),
            ),
          ),
        );
    return Card2(
      key: ObjectKey(m),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextFormField(initialValue: m.name, decoration: const InputDecoration(labelText: 'ওষুধের নাম'), onChanged: (v) { m.name = v; setState(() {}); })),
          IconButton(icon: const Icon(Icons.close), tooltip: 'বাদ দিন', onPressed: () => setState(() => d.medicines.remove(m))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          slot('সকাল', m.morning, (v) => m.morning = v),
          slot('দুপুর', m.noon, (v) => m.noon = v),
          slot('রাত', m.night, (v) => m.night = v),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 110, child: TextFormField(
            initialValue: m.days?.toString() ?? '', keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'কত দিন'),
            onChanged: (v) { m.days = int.tryParse(en(v.trim())); setState(() {}); })),
          const SizedBox(width: 10),
          Expanded(child: Wrap(spacing: 6, children: [
            for (final (k, l) in [('before', 'খাবারের আগে'), ('after', 'খাবারের পরে'), ('any', 'যেকোনো')])
              ChoiceChip(label: Text(l), selected: m.meal == k, onSelected: (_) => setState(() => m.meal = k)),
          ])),
        ]),
        if (m.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Muted('নোট: ${m.note}')),
        if (m.uncertain)
          CheckboxListTile(
            value: m.confirmed, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => m.confirmed = v ?? false),
            title: Text('এআই নিশ্চিত ছিল না — আমি কাগজের সাথে মিলিয়ে দেখেছি', style: TextStyle(fontSize: 13, color: warn ? Colors.orange.shade800 : null)),
          ),
        if (m.confirmed && !m.ready) const Muted('নাম, অন্তত একটা সময় আর দিনের সংখ্যা দিন।'),
      ]),
    );
  }
}
