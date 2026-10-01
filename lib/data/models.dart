import 'dart:convert';
import '../core/bn.dart';

class Member {
  final int? id;
  final String name, relation;
  final int? birthYear;
  final String bloodGroup, allergy;
  final String? photoPath;
  final bool isSelf;
  const Member({this.id, required this.name, this.relation = '', this.birthYear,
      this.bloodGroup = '', this.allergy = '', this.photoPath, this.isSelf = false});

  String get initials {
    final t = name.trim();
    return t.isEmpty ? '?' : String.fromCharCode(t.runes.first);
  }

  int? get age => birthYear == null ? null : DateTime.now().year - birthYear!;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id, 'name': name, 'relation': relation,
        'birth_year': birthYear, 'blood_group': bloodGroup, 'allergy': allergy,
        'photo_path': photoPath, 'is_self': isSelf ? 1 : 0,
      };
  factory Member.fromMap(Map<String, Object?> m) => Member(
        id: m['id'] as int?, name: m['name'] as String,
        relation: (m['relation'] as String?) ?? '', birthYear: m['birth_year'] as int?,
        bloodGroup: (m['blood_group'] as String?) ?? '', allergy: (m['allergy'] as String?) ?? '',
        photoPath: m['photo_path'] as String?, isSelf: (m['is_self'] as int? ?? 0) == 1,
      );
}

List<String> decodePaths(Object? s) =>
    s == null || (s as String).isEmpty ? [] : (jsonDecode(s) as List).cast<String>();

class Visit {
  final int? id;
  final int memberId;
  final DateTime date;
  final String doctor, place, problem;
  final double fee;
  final DateTime? nextVisit;
  final List<String> prescriptions;
  const Visit({this.id, required this.memberId, required this.date, this.doctor = '',
      this.place = '', this.problem = '', this.fee = 0, this.nextVisit,
      this.prescriptions = const []});

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id, 'member_id': memberId, 'date': isoDate(date),
        'doctor': doctor, 'place': place, 'problem': problem, 'fee': fee,
        'next_visit': nextVisit == null ? null : isoDate(nextVisit!),
        'prescriptions': jsonEncode(prescriptions),
      };
  factory Visit.fromMap(Map<String, Object?> m) => Visit(
        id: m['id'] as int?, memberId: m['member_id'] as int,
        date: DateTime.parse(m['date'] as String),
        doctor: (m['doctor'] as String?) ?? '', place: (m['place'] as String?) ?? '',
        problem: (m['problem'] as String?) ?? '', fee: ((m['fee'] as num?) ?? 0).toDouble(),
        nextVisit: parseIso(m['next_visit'] as String?),
        prescriptions: decodePaths(m['prescriptions']),
      );
}

class Medicine {
  final int? id;
  final int? visitId;
  final int memberId;
  final String name;
  final int prescribedDays, boughtDays;
  final DateTime startDate;
  final bool morning, noon, night;
  final String meal; // before | after | any
  final String usage; // eat | apply | drop
  final String notes;
  const Medicine({this.id, this.visitId, required this.memberId, required this.name,
      this.prescribedDays = 0, this.boughtDays = 0, required this.startDate,
      this.morning = false, this.noon = false, this.night = false,
      this.meal = 'any', this.usage = 'eat', this.notes = ''});

  int get timesPerDay => (morning ? 1 : 0) + (noon ? 1 : 0) + (night ? 1 : 0);

  /// Days of medicine we have already bought that are still unused.
  int get daysLeft {
    final used = dateOnly(DateTime.now()).difference(dateOnly(startDate)).inDays;
    final left = boughtDays - used;
    return left < 0 ? 0 : left;
  }

  DateTime get lastDay => dateOnly(startDate).add(Duration(days: boughtDays - 1));
  bool get active => boughtDays > 0 && daysLeft > 0;
  bool get needsRebuy => prescribedDays > boughtDays || daysLeft <= 3;
  int get toBuyDays => prescribedDays - boughtDays > 0 ? prescribedDays - boughtDays : 0;

  String get mealLabel => meal == 'before' ? 'খাবারের আগে' : meal == 'after' ? 'খাবারের পরে' : '';
  String get usageLabel => usage == 'apply' ? 'লাগাবে' : usage == 'drop' ? 'ড্রপ' : 'খাবে';
  String get slotsLabel => [
        if (morning) 'সকাল', if (noon) 'দুপুর', if (night) 'রাত',
      ].join('-');

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id, 'visit_id': visitId, 'member_id': memberId, 'name': name,
        'prescribed_days': prescribedDays, 'bought_days': boughtDays,
        'start_date': isoDate(startDate), 'morning': morning ? 1 : 0, 'noon': noon ? 1 : 0,
        'night': night ? 1 : 0, 'meal': meal, 'usage': usage, 'notes': notes,
      };
  factory Medicine.fromMap(Map<String, Object?> m) => Medicine(
        id: m['id'] as int?, visitId: m['visit_id'] as int?, memberId: m['member_id'] as int,
        name: m['name'] as String, prescribedDays: (m['prescribed_days'] as int?) ?? 0,
        boughtDays: (m['bought_days'] as int?) ?? 0,
        startDate: DateTime.parse(m['start_date'] as String),
        morning: m['morning'] == 1, noon: m['noon'] == 1, night: m['night'] == 1,
        meal: (m['meal'] as String?) ?? 'any', usage: (m['usage'] as String?) ?? 'eat',
        notes: (m['notes'] as String?) ?? '',
      );
}

class TestRecord {
  final int? id;
  final int memberId;
  final String name, place, result;
  final DateTime? doneDate, dueDate;
  final List<String> files;
  const TestRecord({this.id, required this.memberId, required this.name, this.place = '',
      this.result = '', this.doneDate, this.dueDate, this.files = const []});

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id, 'member_id': memberId, 'name': name, 'place': place,
        'result': result, 'done_date': doneDate == null ? null : isoDate(doneDate!),
        'due_date': dueDate == null ? null : isoDate(dueDate!), 'files': jsonEncode(files),
      };
  factory TestRecord.fromMap(Map<String, Object?> m) => TestRecord(
        id: m['id'] as int?, memberId: m['member_id'] as int, name: m['name'] as String,
        place: (m['place'] as String?) ?? '', result: (m['result'] as String?) ?? '',
        doneDate: parseIso(m['done_date'] as String?), dueDate: parseIso(m['due_date'] as String?),
        files: decodePaths(m['files']),
      );
}

class FavPharmacy {
  final int? id;
  final String name, area, phone;
  final bool favorite;
  const FavPharmacy({this.id, required this.name, this.area = '', required this.phone, this.favorite = false});
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id, 'name': name, 'area': area, 'phone': phone, 'favorite': favorite ? 1 : 0,
      };
  factory FavPharmacy.fromMap(Map<String, Object?> m) => FavPharmacy(
        id: m['id'] as int?, name: m['name'] as String, area: (m['area'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '', favorite: m['favorite'] == 1,
      );
}
