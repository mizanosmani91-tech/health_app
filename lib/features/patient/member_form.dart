import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../core/config.dart';
import '../../services/app_state.dart';
import '../../services/auth_service.dart';
import '../../services/images.dart';

const bloodGroups = ['A+', 'A−', 'B+', 'B−', 'O+', 'O−', 'AB+', 'AB−'];
const relations = ['নিজে', 'মা', 'বাবা', 'স্বামী', 'স্ত্রী', 'ছেলে', 'মেয়ে', 'ভাই', 'বোন', 'দাদা/দাদি', 'নানা/নানি', 'অন্যান্য'];

/// Create or edit a family profile. [isSelf] is used on first-run setup.
class MemberForm extends StatefulWidget {
  final Member? member;
  final bool isSelf;
  final bool setup;
  const MemberForm({super.key, this.member, this.isSelf = false, this.setup = false});
  @override
  State<MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends State<MemberForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.member?.name);
  late final _year = TextEditingController(text: widget.member?.birthYear == null ? '' : bn(widget.member!.birthYear!));
  late final _allergy = TextEditingController(text: widget.member?.allergy);
  late String _blood = widget.member?.bloodGroup ?? '';
  late String _relation = widget.member?.relation ?? (widget.isSelf ? 'নিজে' : '');
  late final _phone = TextEditingController();
  String? _photo;
  bool _saving = false;
  bool get _isSelf => widget.member?.isSelf ?? widget.isSelf;

  @override
  void initState() {
    super.initState();
    _photo = widget.member?.photoPath;
    if (_isSelf && Config.hasBackend) _loadAccount();
  }

  /// The server keeps name, mobile, birth year and blood group, so a reinstall can prefill them.
  Future<void> _loadAccount() async {
    final u = await AuthService.instance.loadProfile();
    if (u == null || !mounted) return;
    setState(() {
      _phone.text = (u['phone'] as String?) ?? '';
      if (widget.member == null) {
        if (_name.text.isEmpty) _name.text = (u['name'] as String?) ?? '';
        if (_year.text.isEmpty && u['birthYear'] != null) _year.text = bn(u['birthYear'] as int);
        if (_blood.isEmpty) _blood = ((u['bloodGroup'] as String?) ?? '').replaceAll('-', '−');
      }
    });
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    final yr = int.tryParse(en(_year.text.trim()));
    final m = Member(
      id: widget.member?.id,
      name: _name.text.trim(),
      relation: _relation,
      birthYear: yr,
      bloodGroup: _blood,
      allergy: _allergy.text.trim(),
      photoPath: _photo,
      isSelf: widget.member?.isSelf ?? widget.isSelf,
    );
    final id = await LocalDb.instance.saveMember(m);
    if (_isSelf && Config.hasBackend) {
      try {
        await AuthService.instance.saveProfile(name: m.name, phone: en(_phone.text.trim()), birthYear: yr, bloodGroup: _blood.replaceAll('−', '-'));
      } catch (_) {
        // offline: the local profile is saved; the account copy is refreshed on the next edit
      }
    }
    if (!mounted) return;
    final state = context.read<AppState>();
    await state.refresh();
    if (!mounted) return;
    if (widget.setup) {
      state.setupDone();
    } else {
      if (widget.member == null) state.selectMember(state.members.firstWhere((x) => x.id == id));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Form(
      key: _key,
      child: FormPage(
        title: widget.setup ? 'প্রথমে আপনার প্রোফাইল' : (widget.member == null ? 'নতুন সদস্য' : 'প্রোফাইল সম্পাদনা'),
        action: PrimaryButton(widget.setup ? 'শুরু করুন' : 'সংরক্ষণ করুন', busy: _saving, onTap: _save),
        children: [
          if (widget.setup) const Padding(padding: EdgeInsets.only(bottom: 16), child: Muted('পরে পরিবারের অন্যদেরও যোগ করতে পারবেন।', size: 14)),
          Center(
            child: GestureDetector(
              onTap: () async {
                final f = await pickImage(camera: false);
                if (f != null) setState(() => _photo = f);
              },
              child: Container(
                width: 84, height: 84,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: p.soft,
                    image: _photo == null ? null : DecorationImage(image: FileImage(File(_photo!)), fit: BoxFit.cover)),
                child: _photo == null ? Icon(Icons.add_a_photo, size: 34, color: p.primaryDark) : null,
              ),
            ),
          ),
          Field('পুরো নাম', controller: _name, icon: Icons.person, validator: (v) => (v ?? '').trim().isEmpty ? 'নাম লিখুন' : null),
          if (_isSelf && Config.hasBackend)
            Field('মোবাইল নম্বর', controller: _phone, icon: Icons.phone, keyboard: TextInputType.phone,
                validator: (v) => RegExp(r'^\+?[0-9]{10,15}$').hasMatch(en((v ?? '').trim())) ? null : 'সঠিক মোবাইল নম্বর লিখুন'),
          if (!widget.isSelf && !(widget.member?.isSelf ?? false)) ...[
            const Padding(padding: EdgeInsets.only(bottom: 8, left: 4), child: Text('সম্পর্ক', style: TextStyle(fontWeight: FontWeight.w500))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in relations.skip(1)) Chip2(r, selected: _relation == r, onTap: () => setState(() => _relation = r)),
            ]),
            const SizedBox(height: 14),
          ],
          Field('জন্ম সাল (যেমন: ১৯৯০)', controller: _year, icon: Icons.cake, keyboard: TextInputType.number),
          const Padding(padding: EdgeInsets.only(bottom: 8, left: 4), child: Text('রক্তের গ্রুপ', style: TextStyle(fontWeight: FontWeight.w500))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in bloodGroups) Chip2(g, selected: _blood == g, onTap: () => setState(() => _blood = _blood == g ? '' : g)),
          ]),
          const SizedBox(height: 16),
          if (_isSelf && Config.hasBackend)
            const Padding(padding: EdgeInsets.only(bottom: 12), child: Muted('নাম, মোবাইল, জন্ম সাল ও রক্তের গ্রুপ আপনার অ্যাকাউন্টে থাকবে (রিইনস্টলে আবার লিখতে হবে না)। ওষুধ, ভিজিট, টেস্ট ও প্রেসক্রিপশন শুধু আপনার ফোনে ও আপনার Drive-এ থাকে।', size: 13)),
          Field('অ্যালার্জি (ঐচ্ছিক) — যেমন: পেনিসিলিন', controller: _allergy, icon: Icons.warning_amber),
        ],
      ),
    );
  }
}
