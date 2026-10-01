import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../services/app_state.dart';
import '../../services/images.dart';
import 'medicine_form.dart';

class VisitForm extends StatefulWidget {
  final Member member;
  final Visit? visit;
  const VisitForm({super.key, required this.member, this.visit});
  @override
  State<VisitForm> createState() => _VisitFormState();
}

class _VisitFormState extends State<VisitForm> {
  late final Visit? v = widget.visit;
  late final _doctor = TextEditingController(text: v?.doctor);
  late final _place = TextEditingController(text: v?.place);
  late final _problem = TextEditingController(text: v?.problem);
  late final _fee = TextEditingController(text: v == null || v!.fee == 0 ? '' : bn(v!.fee.toStringAsFixed(0)));
  late DateTime _date = v?.date ?? dateOnly(DateTime.now());
  late DateTime? _next = v?.nextVisit;
  late final List<String> _photos = [...?v?.prescriptions];
  int? _savedId;

  Visit _build() => Visit(
        id: _savedId ?? v?.id, memberId: widget.member.id!, date: _date, doctor: _doctor.text.trim(),
        place: _place.text.trim(), problem: _problem.text.trim(),
        fee: double.tryParse(en(_fee.text.trim())) ?? 0, nextVisit: _next, prescriptions: _photos,
      );

  Future<int> _persist() async => _savedId = await LocalDb.instance.saveVisit(_build());

  Future<void> _save() async {
    await _persist();
    if (!mounted) return;
    context.read<AppState>().touch();
    Navigator.pop(context);
  }

  Future<void> _pickDate(bool next) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (next ? _next : _date) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d != null) setState(() => next ? _next = d : _date = d);
  }

  Future<void> _addPhoto() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('ক্যামেরা'), onTap: () => Navigator.pop(c, true)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('গ্যালারি'), onTap: () => Navigator.pop(c, false)),
        ]),
      ),
    );
    if (camera == null) return;
    final f = camera ? [await pickImage(camera: true)] : await pickMany();
    setState(() => _photos.addAll(f.whereType<String>()));
  }

  @override
  Widget build(BuildContext context) => FormPage(
        title: v == null ? 'নতুন ভিজিট' : 'ভিজিট সম্পাদনা',
        action: PrimaryButton('সংরক্ষণ করুন', onTap: _save),
        children: [
          Field('তারিখ: ${bnDate(_date)}', icon: Icons.event, readOnly: true, onTap: () => _pickDate(false)),
          Field('ডাক্তারের নাম', controller: _doctor, icon: Icons.medical_services),
          Field('হাসপাতাল / চেম্বার', controller: _place, icon: Icons.local_hospital),
          Field('সমস্যা', controller: _problem, icon: Icons.sick),
          Field('ফি (৳)', controller: _fee, icon: Icons.payments, keyboard: TextInputType.number),
          Field(_next == null ? 'পরবর্তী ভিজিটের তারিখ (ঐচ্ছিক)' : 'পরবর্তী ভিজিট: ${bnDate(_next!)}', icon: Icons.event_repeat, readOnly: true, onTap: () => _pickDate(true)),
          const SectionTitle('প্রেসক্রিপশনের ছবি'),
          SizedBox(
            height: 96,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              GestureDetector(
                onTap: _addPhoto,
                child: Container(
                  width: 96, margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: context.pal.soft, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.pal.border, width: 1.5)),
                  child: Icon(Icons.add_a_photo, color: context.pal.primaryDark, size: 30),
                ),
              ),
              for (final f in _photos)
                Stack(children: [
                  Container(
                    width: 96, margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), image: DecorationImage(image: FileImage(File(f)), fit: BoxFit.cover)),
                  ),
                  Positioned(top: 4, right: 14, child: GestureDetector(
                    onTap: () => setState(() => _photos.remove(f)),
                    child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                  )),
                ]),
            ]),
          ),
          const SectionTitle('এই ভিজিটের ওষুধ'),
          if (v?.id == null && _savedId == null)
            Card2(
              color: context.pal.soft,
              onTap: () async {
                await _persist();
                if (!mounted) return;
                setState(() {});
              },
              child: Row(children: [
                Icon(Icons.info, color: context.pal.primaryDark),
                const SizedBox(width: 10),
                const Expanded(child: Text('ওষুধ যোগ করতে এখানে চাপুন (ভিজিট আগে সেভ হবে)', style: TextStyle(fontSize: 13))),
              ]),
            )
          else
            Q<List<Medicine>>(
              load: () => LocalDb.instance.medicines(visitId: _savedId ?? v!.id),
              builder: (c, meds) => Column(children: [
                for (final m in meds)
                  Card2(
                    margin: const EdgeInsets.only(bottom: 8),
                    onTap: () => context.push(MedicineForm(member: widget.member, medicine: m, visitId: m.visitId)).then((_) => setState(() {})),
                    child: Row(children: [
                      Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Muted('${bn(m.boughtDays)}/${bn(m.prescribedDays)} দিন'),
                    ]),
                  ),
                OutlineButton2('ওষুধ যোগ করুন', icon: Icons.add,
                    onTap: () => context.push(MedicineForm(member: widget.member, visitId: _savedId ?? v!.id, startDate: _date)).then((_) => setState(() {}))),
              ]),
            ),
        ],
      );
}
