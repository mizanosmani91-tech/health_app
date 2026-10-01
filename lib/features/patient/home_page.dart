import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../services/app_state.dart';
import '../../services/prefs.dart';
import 'medicine_form.dart';
import 'member_form.dart';
import 'test_form.dart';
import 'visit_form.dart';

class _Home {
  final List<Medicine> meds;
  final Set<String> taken;
  final List<Visit> visits;
  final List<TestRecord> tests;
  _Home(this.meds, this.taken, this.visits, this.tests);
}

class HomePage extends StatelessWidget {
  final void Function(int) go;
  const HomePage({super.key, required this.go});

  static const _slots = [('morning', 'সকাল'), ('noon', 'দুপুর'), ('night', 'রাত')];

  Future<_Home> _load(Member m) async {
    final db = LocalDb.instance;
    return _Home(await db.medicines(memberId: m.id), await db.takenToday(m.id!), await db.visits(m.id!), await db.tests(m.id!));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.current;
    if (me == null) return const SizedBox();
    return Q<_Home>(
      load: () => _load(me),
      builder: (context, d) {
        final today = dateOnly(DateTime.now());
        final active = d.meds.where((m) => m.active && !dateOnly(m.startDate).isAfter(today)).toList();
        // today's doses: (medicine, slot key, slot label)
        final doses = <(Medicine, String, String)>[];
        for (final m in active) {
          final on = [m.morning, m.noon, m.night];
          for (var i = 0; i < 3; i++) {
            if (on[i]) doses.add((m, _slots[i].$1, _slots[i].$2));
          }
        }
        doses.sort((a, b) => Prefs.slotMinutes(a.$2).compareTo(Prefs.slotMinutes(b.$2)));
        bool isTaken((Medicine, String, String) x) => d.taken.contains('${x.$1.id}:${x.$2}');
        final done = doses.where(isTaken).length;
        final pending = doses.where((x) => !isTaken(x)).toList();
        final low = active.where((m) => m.needsRebuy).toList();
        final nextVisit = d.visits.where((v) => v.nextVisit != null && !v.nextVisit!.isBefore(today)).toList()
          ..sort((a, b) => a.nextVisit!.compareTo(b.nextVisit!));
        final dueTests = d.tests.where((t) => t.dueDate != null && t.doneDate == null).toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

        return ListView(padding: EdgeInsets.zero, children: [
          HeroHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greeting(), style: const TextStyle(fontSize: 13, color: Color(0xFFBFEDE3))),
              const Text('আজকের স্বাস্থ্য', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              SizedBox(
                height: 66,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final m in s.members) _Avatar(m, selected: m.id == me.id, onTap: () => s.selectMember(m)),
                  GestureDetector(
                    onTap: () => context.push(const MemberForm()),
                    child: Container(
                      width: 48, height: 48,
                      margin: const EdgeInsets.only(right: 12, top: 0),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 2)),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              Card2(
                child: Row(children: [
                  SizedBox(
                    width: 62, height: 62,
                    child: Stack(alignment: Alignment.center, children: [
                      CircularProgressIndicator(
                        value: doses.isEmpty ? 0 : done / doses.length, strokeWidth: 7,
                        backgroundColor: context.pal.soft, color: context.pal.primary),
                      Text(doses.isEmpty ? '–' : '${bn(done)}/${bn(doses.length)}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: context.pal.text)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(doses.isEmpty ? '${me.name}-এর আজ কোনো ওষুধ নেই' : 'আজ ${bn(done)}টি ডোজ নেওয়া হয়েছে',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: context.pal.text)),
                      Muted(doses.isEmpty ? 'ওষুধ যোগ করুন' : pending.isEmpty ? 'সব ডোজ শেষ 🎉' : 'আর ${bn(pending.length)}টি বাকি'),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            child: Column(children: [
              for (final x in pending.take(3))
                Card2(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    const IconTile(Icons.medication, Tint.purple),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.$1.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Muted('${bnTime(Prefs.slotMinutes(x.$2) ~/ 60, Prefs.slotMinutes(x.$2) % 60)}'
                            '${x.$1.mealLabel.isEmpty ? '' : ' · ${x.$1.mealLabel}'}'),
                      ]),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: context.pal.primaryDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () async {
                        await LocalDb.instance.setDose(x.$1.id!, x.$2, true);
                        if (context.mounted) context.read<AppState>().touch();
                      },
                      child: const Text('নিয়েছি'),
                    ),
                  ]),
                ),
              Row(children: [
                _Quick(Icons.medication, 'ওষুধ', Tint.purple, () => context.push(MedicineForm(member: me))),
                _Quick(Icons.medical_services, 'ভিজিট', Tint.orange, () => context.push(VisitForm(member: me))),
                _Quick(Icons.science, 'টেস্ট', Tint.blue, () => context.push(TestForm(member: me))),
                _Quick(Icons.person, 'প্রোফাইল', Tint.amber, () => context.push(MemberForm(member: me))),
              ]),
              const SizedBox(height: 14),
              for (final m in low.take(3))
                Card2(
                  color: const Color(0xFFFFF0D1),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    const Icon(Icons.error, color: Color(0xFFA86A08), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${m.name} ${m.daysLeft <= 3 ? 'প্রায় শেষ' : 'কিনতে হবে'}',
                            style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B4305))),
                        Text('হাতে ${bn(m.daysLeft)} দিন${m.toBuyDays > 0 ? ', ${bn(m.toBuyDays)} দিনের কেনা বাকি' : ''}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF8A5A0B))),
                      ]),
                    ),
                  ]),
                ),
              if (nextVisit.isNotEmpty)
                Card2(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    const IconTile(Icons.medical_services, Tint.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(nextVisit.first.doctor.isEmpty ? 'পরবর্তী ভিজিট' : nextVisit.first.doctor, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Muted('${bnDateShort(nextVisit.first.nextVisit!)} · ${relativeDays(nextVisit.first.nextVisit!)}'),
                      ]),
                    ),
                    InkWell(onTap: () => go(2), child: Icon(Icons.chevron_right, color: context.pal.muted)),
                  ]),
                ),
              if (dueTests.isNotEmpty)
                Card2(
                  child: Row(children: [
                    const IconTile(Icons.science, Tint.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(dueTests.first.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Muted('টেস্ট · ${bnDateShort(dueTests.first.dueDate!)} · ${relativeDays(dueTests.first.dueDate!)}'),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  final Member m;
  final bool selected;
  final VoidCallback onTap;
  const _Avatar(this.m, {required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.white : Colors.white24,
                  image: m.photoPath == null ? null : DecorationImage(image: FileImage(File(m.photoPath!)), fit: BoxFit.cover),
                  border: selected ? Border.all(color: Colors.white, width: 2) : null),
              alignment: Alignment.center,
              child: m.photoPath != null ? null : Text(m.isSelf ? 'আমি' : m.initials,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? context.pal.primaryDark : Colors.white)),
            ),
          ]),
        ),
      );
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final Tint tint;
  final VoidCallback onTap;
  const _Quick(this.icon, this.label, this.tint, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: tint.bg, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Icon(icon, color: tint.fg, size: 26),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 12, color: tint.fg)),
              ]),
            ),
          ),
        ),
      );
}
