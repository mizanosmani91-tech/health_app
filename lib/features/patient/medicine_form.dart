import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../services/app_state.dart';
import '../../services/drug_search.dart';

class MedicineForm extends StatefulWidget {
  final Member member;
  final Medicine? medicine;
  final int? visitId;
  final DateTime? startDate;
  const MedicineForm({super.key, required this.member, this.medicine, this.visitId, this.startDate});
  @override
  State<MedicineForm> createState() => _MedicineFormState();
}

class _MedicineFormState extends State<MedicineForm> {
  final _key = GlobalKey<FormState>();
  late final Medicine? m = widget.medicine;
  late final _name = TextEditingController(text: m?.name);
  late final _presc = TextEditingController(text: m == null || m!.prescribedDays == 0 ? '' : bn(m!.prescribedDays));
  late final _bought = TextEditingController(text: m == null || m!.boughtDays == 0 ? '' : bn(m!.boughtDays));
  late final _notes = TextEditingController(text: m?.notes);
  late bool _morning = m?.morning ?? false, _noon = m?.noon ?? false, _night = m?.night ?? false;
  late String _meal = m?.meal ?? 'after';
  late String _usage = m?.usage ?? 'eat';
  late DateTime _start = m?.startDate ?? widget.startDate ?? dateOnly(DateTime.now());
  List<String> _names = [];

  @override
  void initState() {
    super.initState();
    LocalDb.instance.medicineNames().then((n) => mounted ? setState(() => _names = n) : null);
  }

  int _n(TextEditingController c) => int.tryParse(en(c.text.trim())) ?? 0;

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final med = Medicine(
      id: m?.id, visitId: m?.visitId ?? widget.visitId, memberId: widget.member.id!, name: _name.text.trim(),
      prescribedDays: _n(_presc), boughtDays: _n(_bought), startDate: _start,
      morning: _morning, noon: _noon, night: _night, meal: _meal, usage: _usage, notes: _notes.text.trim(),
    );
    await LocalDb.instance.saveMedicine(med);
    if (!mounted) return;
    context.read<AppState>().touch();
    Navigator.pop(context);
  }

  Widget _seg(String label, bool on, VoidCallback t) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: t,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: on ? context.pal.primaryDark : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: on ? context.pal.primaryDark : context.pal.border, width: 1.5)),
              child: Text(label, style: TextStyle(color: on ? Colors.white : context.pal.muted, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Form(
        key: _key,
        child: FormPage(
          title: m == null ? 'ওষুধ যোগ' : 'ওষুধ সম্পাদনা',
          action: PrimaryButton('সংরক্ষণ করুন', onTap: _save),
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _name.text),
              optionsBuilder: (v) async {
                if (v.text.isEmpty) return const <String>[];
                final mine = _names.where((n) => n.contains(v.text)).toList();
                await Future.delayed(const Duration(milliseconds: 300)); // let typing settle before asking the server
                final hits = await searchDrugs(v.text);
                return {...mine, ...hits.map((h) => h.label)};
              },
              onSelected: (v) => _name.text = v,
              fieldViewBuilder: (c, ctrl, focus, _) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: ctrl, focusNode: focus,
                  onChanged: (v) => _name.text = v,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'ওষুধের নাম লিখুন' : null,
                  decoration: const InputDecoration(labelText: 'ওষুধের নাম', prefixIcon: Icon(Icons.medication)),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('ব্যবহারের নিয়ম', style: TextStyle(fontWeight: FontWeight.w500))),
            Row(children: [
              _seg('খাবে', _usage == 'eat', () => setState(() => _usage = 'eat')),
              _seg('লাগাবে', _usage == 'apply', () => setState(() => _usage = 'apply')),
              _seg('ড্রপ', _usage == 'drop', () => setState(() => _usage = 'drop')),
            ]),
            const SizedBox(height: 16),
            const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('দিনে কতবার', style: TextStyle(fontWeight: FontWeight.w500))),
            Row(children: [
              _seg('সকাল', _morning, () => setState(() => _morning = !_morning)),
              _seg('দুপুর', _noon, () => setState(() => _noon = !_noon)),
              _seg('রাত', _night, () => setState(() => _night = !_night)),
            ]),
            const SizedBox(height: 16),
            if (_usage == 'eat') ...[
              const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('খাবারের সাথে', style: TextStyle(fontWeight: FontWeight.w500))),
              Row(children: [
                _seg('আগে', _meal == 'before', () => setState(() => _meal = 'before')),
                _seg('পরে', _meal == 'after', () => setState(() => _meal = 'after')),
                _seg('যেকোনো', _meal == 'any', () => setState(() => _meal = 'any')),
              ]),
              const SizedBox(height: 16),
            ],
            Row(children: [
              Expanded(child: Field('কত দিনের দিয়েছে', controller: _presc, keyboard: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(child: Field('কত দিনের কিনেছি', controller: _bought, keyboard: TextInputType.number)),
            ]),
            Field('শুরুর তারিখ: ${bnDate(_start)}', icon: Icons.event, readOnly: true, onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _start,
                  firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null) setState(() => _start = d);
            }),
            Field('নোট (ঐচ্ছিক)', controller: _notes, icon: Icons.notes),
            Card2(
              color: context.pal.soft,
              child: Row(children: [
                Icon(Icons.info, color: context.pal.primaryDark),
                const SizedBox(width: 10),
                const Expanded(child: Text('"কিনেছি" যত দিনের, ততদিন পর্যন্ত রিমাইন্ডার বাজবে। শেষ হওয়ার ৩ দিন আগে জানানো হবে।', style: TextStyle(fontSize: 13, height: 1.5))),
              ]),
            ),
          ],
        ),
      );
}
