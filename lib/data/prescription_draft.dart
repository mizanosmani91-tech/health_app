import 'models.dart';

/// A prescription as read by the server's AI. It is only a DRAFT: nothing is saved
/// until the person has checked every medicine and pressed save.
class DraftMedicine {
  String name;
  double? morning, noon, night;
  int? days;
  String meal; // before | after | any
  String note;
  final bool uncertain;
  bool confirmed;
  DraftMedicine({required this.name, this.morning, this.noon, this.night, this.days,
      this.meal = 'any', this.note = '', this.uncertain = false}) : confirmed = !uncertain;

  factory DraftMedicine.fromJson(Map<String, dynamic> j) {
    final parts = [j['strength'], j['form']].whereType<String>().where((s) => s.isNotEmpty);
    final name = [j['name'] as String? ?? '', ...parts].join(' ').trim();
    return DraftMedicine(
      name: name,
      morning: (j['morning'] as num?)?.toDouble(), noon: (j['noon'] as num?)?.toDouble(),
      night: (j['night'] as num?)?.toDouble(), days: (j['days'] as num?)?.toInt(),
      meal: (j['meal'] as String?) ?? 'any', note: (j['note'] as String?) ?? '',
      uncertain: (j['uncertain'] as bool?) ?? true,
    );
  }

  /// Saving needs a name, at least one dose time and a number of days, and a person's OK on unsure rows.
  bool get ready => name.trim().isNotEmpty && confirmed && (days ?? 0) > 0 && ((morning ?? 0) + (noon ?? 0) + (night ?? 0)) > 0;

  Medicine toMedicine(int memberId, int visitId, DateTime start) {
    String half(String s, double? d) => d != null && d > 0 && d != 1 ? '$s ${d == 0.5 ? '½' : d}' : '';
    final notes = [note, half('সকাল', morning), half('দুপুর', noon), half('রাত', night)].where((s) => s.isNotEmpty).join(' · ');
    return Medicine(
      visitId: visitId, memberId: memberId, name: name.trim(), prescribedDays: days ?? 0, boughtDays: 0,
      startDate: start, morning: (morning ?? 0) > 0, noon: (noon ?? 0) > 0, night: (night ?? 0) > 0,
      meal: meal, notes: notes,
    );
  }
}

class DraftTest {
  String name;
  bool include = true;
  DraftTest(this.name);
}

class PrescriptionDraft {
  final bool readable;
  String doctor, problem;
  DateTime? visitDate, nextVisit;
  String advice;
  final List<DraftMedicine> medicines;
  final List<DraftTest> tests;
  PrescriptionDraft({required this.readable, this.doctor = '', this.problem = '', this.visitDate, this.nextVisit,
      this.advice = '', required this.medicines, required this.tests});

  factory PrescriptionDraft.fromJson(Map<String, dynamic> j) => PrescriptionDraft(
        readable: j['readable'] == true,
        doctor: (j['doctorName'] as String?) ?? '', problem: (j['problem'] as String?) ?? '',
        visitDate: parseIso(j['visitDate'] as String?), nextVisit: parseIso(j['nextVisitDate'] as String?),
        advice: (j['advice'] as String?) ?? '',
        medicines: [for (final m in (j['medicines'] as List? ?? [])) DraftMedicine.fromJson(m as Map<String, dynamic>)],
        tests: [for (final t in (j['tests'] as List? ?? [])) DraftTest((t as Map)['name'] as String)],
      );

  bool get canSave => medicines.every((m) => m.ready) && (medicines.isNotEmpty || tests.any((t) => t.include) || doctor.isNotEmpty || problem.isNotEmpty);
}
