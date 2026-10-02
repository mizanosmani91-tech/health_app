import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../services/app_state.dart';
import 'medicine_form.dart';

class MedicinesPage extends StatelessWidget {
  const MedicinesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.current!;
    return Scaffold(
      appBar: AppBar(title: Text('${me.name}-এর ওষুধ', style: const TextStyle(fontWeight: FontWeight.w600))),
      body: FabSlot(
        onPressed: () => context.push(MedicineForm(member: me)),
        child: Q<List<Medicine>>(
        load: () => LocalDb.instance.medicines(memberId: me.id),
        builder: (c, meds) {
          final active = meds.where((m) => m.active || m.prescribedDays > m.boughtDays && m.boughtDays == 0).toList();
          final past = meds.where((m) => !active.contains(m)).toList();
          if (meds.isEmpty) return const Center(child: Empty(Icons.medication, 'এখনো কোনো ওষুধ নেই।\n+ চেপে যোগ করুন।'));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 140), children: [
            if (active.isNotEmpty) const SectionTitle('চলছে'),
            for (final m in active) _MedTile(m, me),
            if (past.isNotEmpty) const SectionTitle('শেষ হয়েছে'),
            for (final m in past) _MedTile(m, me),
          ]);
        },
      ),
      ),
    );
  }
}

class _MedTile extends StatelessWidget {
  final Medicine m;
  final Member member;
  const _MedTile(this.m, this.member);
  @override
  Widget build(BuildContext context) {
    final warn = m.active && m.needsRebuy;
    return Card2(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(MedicineForm(member: member, medicine: m)),
      child: Row(children: [
        IconTile(m.usage == 'drop' ? Icons.water_drop : m.usage == 'apply' ? Icons.healing : Icons.medication, Tint.purple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Muted([m.usageLabel, if (m.slotsLabel.isNotEmpty) m.slotsLabel, if (m.mealLabel.isNotEmpty && m.usage == 'eat') m.mealLabel].join(' · ')),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (m.active) warn ? Pill.low('${bn(m.daysLeft)} দিন বাকি') : Pill.ok('${bn(m.daysLeft)} দিন বাকি') else const Pill('শেষ', Color(0xFFEDF3F1), Color(0xFF5E736E)),
          if (m.toBuyDays > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Muted('${bn(m.toBuyDays)} দিনের কেনা বাকি', size: 11)),
        ]),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'del' && await confirm(context, '"${m.name}" রিসাইকেল বিনে পাঠাবেন?')) {
              await LocalDb.instance.softDelete('medicines', m.id!);
              if (context.mounted) context.read<AppState>().touch();
            }
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('মুছুন'))],
        ),
      ]),
    );
  }
}
