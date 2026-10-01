import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../core/bn.dart';
import 'models.dart';

/// On-device store for the patient side. Health data never leaves the phone
/// except through the user's own Google Drive backup.
class LocalDb {
  LocalDb._();
  static final instance = LocalDb._();
  late final Database db;

  static const tables = ['members', 'visits', 'medicines', 'dose_log', 'tests', 'pharmacies'];

  Future<void> init() async {
    db = await openDatabase(
      p.join(await getDatabasesPath(), 'health_diary.db'),
      version: 1,
      onCreate: (d, _) async {
        await d.execute('''CREATE TABLE members(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, relation TEXT, birth_year INTEGER,
          blood_group TEXT, allergy TEXT, photo_path TEXT, is_self INTEGER DEFAULT 0, deleted_at TEXT)''');
        await d.execute('''CREATE TABLE visits(
          id INTEGER PRIMARY KEY AUTOINCREMENT, member_id INTEGER NOT NULL, date TEXT NOT NULL,
          doctor TEXT, place TEXT, problem TEXT, fee REAL DEFAULT 0, next_visit TEXT,
          prescriptions TEXT, deleted_at TEXT)''');
        await d.execute('''CREATE TABLE medicines(
          id INTEGER PRIMARY KEY AUTOINCREMENT, visit_id INTEGER, member_id INTEGER NOT NULL,
          name TEXT NOT NULL, prescribed_days INTEGER, bought_days INTEGER, start_date TEXT NOT NULL,
          morning INTEGER, noon INTEGER, night INTEGER, meal TEXT, usage TEXT, notes TEXT, deleted_at TEXT)''');
        await d.execute('''CREATE TABLE dose_log(
          medicine_id INTEGER NOT NULL, date TEXT NOT NULL, slot TEXT NOT NULL,
          PRIMARY KEY(medicine_id, date, slot))''');
        await d.execute('''CREATE TABLE tests(
          id INTEGER PRIMARY KEY AUTOINCREMENT, member_id INTEGER NOT NULL, name TEXT NOT NULL,
          place TEXT, result TEXT, done_date TEXT, due_date TEXT, files TEXT, deleted_at TEXT)''');
        await d.execute('''CREATE TABLE pharmacies(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, area TEXT, phone TEXT, favorite INTEGER DEFAULT 0)''');
      },
    );
  }

  // ---- members
  Future<List<Member>> members() async => (await db.query('members',
          where: 'deleted_at IS NULL', orderBy: 'is_self DESC, id'))
      .map(Member.fromMap).toList();
  Future<int> saveMember(Member m) async => m.id == null
      ? db.insert('members', m.toMap())
      : (await db.update('members', m.toMap(), where: 'id=?', whereArgs: [m.id]), m.id!).$2;

  // ---- visits
  Future<List<Visit>> visits(int memberId) async => (await db.query('visits',
          where: 'member_id=? AND deleted_at IS NULL', whereArgs: [memberId], orderBy: 'date DESC, id DESC'))
      .map(Visit.fromMap).toList();
  Future<List<Visit>> allVisits() async => (await db.query('visits', where: 'deleted_at IS NULL')).map(Visit.fromMap).toList();
  Future<int> saveVisit(Visit v) async => v.id == null
      ? db.insert('visits', v.toMap())
      : (await db.update('visits', v.toMap(), where: 'id=?', whereArgs: [v.id]), v.id!).$2;

  // ---- medicines
  Future<List<Medicine>> medicines({int? memberId, int? visitId}) async {
    final where = ['deleted_at IS NULL'];
    final args = <Object>[];
    if (memberId != null) { where.add('member_id=?'); args.add(memberId); }
    if (visitId != null) { where.add('visit_id=?'); args.add(visitId); }
    return (await db.query('medicines', where: where.join(' AND '), whereArgs: args, orderBy: 'id DESC'))
        .map(Medicine.fromMap).toList();
  }
  Future<int> saveMedicine(Medicine m) async => m.id == null
      ? db.insert('medicines', m.toMap())
      : (await db.update('medicines', m.toMap(), where: 'id=?', whereArgs: [m.id]), m.id!).$2;
  Future<List<String>> medicineNames() async => (await db.rawQuery(
          'SELECT DISTINCT name FROM medicines WHERE deleted_at IS NULL ORDER BY name'))
      .map((r) => r['name'] as String).toList();

  // ---- dose log
  Future<Set<String>> takenToday(int memberId) async {
    final rows = await db.rawQuery(
        'SELECT l.medicine_id AS m, l.slot AS s FROM dose_log l JOIN medicines x ON x.id=l.medicine_id '
        'WHERE l.date=? AND x.member_id=?', [isoDate(DateTime.now()), memberId]);
    return rows.map((r) => '${r['m']}:${r['s']}').toSet();
  }
  Future<void> setDose(int medicineId, String slot, bool taken) async {
    final d = isoDate(DateTime.now());
    if (taken) {
      await db.insert('dose_log', {'medicine_id': medicineId, 'date': d, 'slot': slot},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('dose_log', where: 'medicine_id=? AND date=? AND slot=?', whereArgs: [medicineId, d, slot]);
    }
  }

  // ---- tests
  Future<List<TestRecord>> tests(int memberId) async => (await db.query('tests',
          where: 'member_id=? AND deleted_at IS NULL', whereArgs: [memberId], orderBy: 'COALESCE(done_date, due_date) DESC'))
      .map(TestRecord.fromMap).toList();
  Future<List<TestRecord>> allTests() async => (await db.query('tests', where: 'deleted_at IS NULL')).map(TestRecord.fromMap).toList();
  Future<int> saveTest(TestRecord t) async => t.id == null
      ? db.insert('tests', t.toMap())
      : (await db.update('tests', t.toMap(), where: 'id=?', whereArgs: [t.id]), t.id!).$2;

  // ---- pharmacies
  Future<List<FavPharmacy>> pharmacies() async =>
      (await db.query('pharmacies', orderBy: 'favorite DESC, id')).map(FavPharmacy.fromMap).toList();
  Future<void> savePharmacy(FavPharmacy f) async => f.id == null
      ? db.insert('pharmacies', f.toMap())
      : db.update('pharmacies', f.toMap(), where: 'id=?', whereArgs: [f.id]);
  Future<void> deletePharmacy(int id) => db.delete('pharmacies', where: 'id=?', whereArgs: [id]);

  // ---- recycle bin (soft delete)
  Future<void> softDelete(String table, int id) =>
      db.update(table, {'deleted_at': DateTime.now().toIso8601String()}, where: 'id=?', whereArgs: [id]);
  Future<void> restore(String table, int id) =>
      db.update(table, {'deleted_at': null}, where: 'id=?', whereArgs: [id]);
  Future<void> purge(String table, int id) => db.delete(table, where: 'id=?', whereArgs: [id]);
  Future<List<Map<String, Object?>>> trashed(String table) =>
      db.query(table, where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC');

  // ---- backup / restore
  Future<Map<String, List<Map<String, Object?>>>> dump() async =>
      {for (final t in tables) t: await db.query(t)};

  Future<void> replaceAll(Map<String, dynamic> data) async {
    await db.transaction((tx) async {
      for (final t in tables) {
        await tx.delete(t);
        for (final row in (data[t] as List? ?? const [])) {
          await tx.insert(t, Map<String, Object?>.from(row as Map));
        }
      }
    });
  }
}
