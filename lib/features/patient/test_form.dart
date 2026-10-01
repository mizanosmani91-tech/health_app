import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../services/app_state.dart';
import '../../services/images.dart';

class TestForm extends StatefulWidget {
  final Member member;
  final TestRecord? test;
  const TestForm({super.key, required this.member, this.test});
  @override
  State<TestForm> createState() => _TestFormState();
}

class _TestFormState extends State<TestForm> {
  final _key = GlobalKey<FormState>();
  late final TestRecord? t = widget.test;
  late final _name = TextEditingController(text: t?.name);
  late final _place = TextEditingController(text: t?.place);
  late final _result = TextEditingController(text: t?.result);
  late DateTime? _done = t?.doneDate, _due = t?.dueDate;
  late final List<String> _files = [...?t?.files];

  Future<DateTime?> _pick(DateTime? init, {bool future = false}) => showDatePicker(
        context: context,
        initialDate: init ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(Duration(days: future ? 365 * 3 : 0)),
      );

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    await LocalDb.instance.saveTest(TestRecord(
      id: t?.id, memberId: widget.member.id!, name: _name.text.trim(), place: _place.text.trim(),
      result: _result.text.trim(), doneDate: _done, dueDate: _due, files: _files));
    if (!mounted) return;
    context.read<AppState>().touch();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _key,
        child: FormPage(
          title: t == null ? 'নতুন টেস্ট' : 'টেস্ট সম্পাদনা',
          action: PrimaryButton('সংরক্ষণ করুন', onTap: _save),
          children: [
            Field('টেস্টের নাম', controller: _name, icon: Icons.science, validator: (v) => (v ?? '').trim().isEmpty ? 'নাম লিখুন' : null),
            Field('কোথায় করেছি / করাব', controller: _place, icon: Icons.local_hospital),
            Field(_done == null ? 'করেছি কবে (ঐচ্ছিক)' : 'করেছি: ${bnDate(_done!)}', icon: Icons.event_available, readOnly: true,
                onTap: () async { final d = await _pick(_done); if (d != null) setState(() => _done = d); }),
            Field(_due == null ? 'কবে করতে হবে (ঐচ্ছিক)' : 'করতে হবে: ${bnDate(_due!)}', icon: Icons.event, readOnly: true,
                onTap: () async { final d = await _pick(_due, future: true); if (d != null) setState(() => _due = d); }),
            Field('ফলাফল', controller: _result, icon: Icons.fact_check, maxLines: 3),
            const SectionTitle('রিপোর্টের ছবি'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              GestureDetector(
                onTap: () async {
                  final fs = await pickMany();
                  setState(() => _files.addAll(fs));
                },
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(color: context.pal.soft, borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.add_photo_alternate, color: context.pal.primaryDark, size: 30),
                ),
              ),
              for (final f in _files)
                GestureDetector(
                  onLongPress: () => setState(() => _files.remove(f)),
                  child: Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), image: DecorationImage(image: FileImage(File(f)), fit: BoxFit.cover)),
                  ),
                ),
            ]),
            if (_files.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Muted('মুছতে ছবিতে চেপে ধরে রাখুন', size: 12)),
          ],
        ),
      );
}
