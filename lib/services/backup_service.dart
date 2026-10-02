import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/local_db.dart';
import 'prefs.dart';

/// Backs the patient's data up to the hidden app-data folder of *their own*
/// Google Drive. We can only see files this app created (drive.appdata scope).
class BackupService {
  BackupService._();
  static final instance = BackupService._();

  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _keep = 10; // "আগের ১০টা ব্যাকআপ থাকবে"
  static const _api = 'https://www.googleapis.com';

  Future<Map<String, String>> _headers({bool interactive = true}) async {
    final gs = GoogleSignIn.instance;
    final light = await gs.attemptLightweightAuthentication();
    if (light == null && !interactive) throw StateError('Google সাইন-ইন লাগবে');
    final account = light ?? await gs.authenticate();
    final client = account.authorizationClient;
    final auth = await client.authorizationForScopes([_scope]) ??
        (interactive ? await client.authorizeScopes([_scope]) : null);
    if (auth == null) throw StateError('Drive অনুমতি দেওয়া হয়নি');
    return {'Authorization': 'Bearer ${auth.accessToken}'};
  }

  Future<List<Map<String, dynamic>>> _list(Map<String, String> h, {String? q}) async {
    final uri = Uri.parse('$_api/drive/v3/files').replace(queryParameters: {
      'spaces': 'appDataFolder',
      'fields': 'files(id,name,createdTime)',
      'orderBy': 'createdTime desc',
      'pageSize': '200',
      'q': ?q,
    });
    final r = await http.get(uri, headers: h);
    if (r.statusCode != 200) throw StateError('Drive: ${r.statusCode}');
    return (jsonDecode(r.body)['files'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> _upload(Map<String, String> h, String name, List<int> bytes, String mime) async {
    final boundary = 'hd${DateTime.now().microsecondsSinceEpoch}';
    final meta = jsonEncode({'name': name, 'parents': ['appDataFolder']});
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'))
      ..add(utf8.encode('--$boundary\r\nContent-Type: $mime\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final r = await http.post(
      Uri.parse('$_api/upload/drive/v3/files?uploadType=multipart'),
      headers: {...h, 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: body.toBytes(),
    );
    if (r.statusCode != 200) throw StateError('Drive আপলোড ব্যর্থ: ${r.statusCode}');
  }

  Iterable<String> _imagePaths(Map<String, List<Map<String, Object?>>> d) sync* {
    for (final m in d['members']!) {
      if (m['photo_path'] != null) yield m['photo_path'] as String;
    }
    for (final t in ['visits', 'tests']) {
      final col = t == 'visits' ? 'prescriptions' : 'files';
      for (final r in d[t]!) {
        final s = r[col] as String?;
        if (s != null && s.isNotEmpty) yield* (jsonDecode(s) as List).cast<String>();
      }
    }
  }

  Future<void> backupNow({bool silent = false}) async {
    final h = await _headers(interactive: !silent);
    final data = await LocalDb.instance.dump();
    final existing = await _list(h);
    final have = existing.map((f) => f['name'] as String).toSet();

    // Images first (skip ones already uploaded); JSON last so a partial run isn't a "complete" backup.
    for (final path in _imagePaths(data).toSet()) {
      final name = 'img_${p.basename(path)}';
      final f = File(path);
      if (have.contains(name) || !await f.exists()) continue;
      await _upload(h, name, await f.readAsBytes(), 'image/jpeg');
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    await _upload(h, 'backup_$stamp.json', utf8.encode(jsonEncode(data)), 'application/json');

    final backups = (await _list(h)).where((f) => (f['name'] as String).startsWith('backup_')).toList();
    for (final old in backups.skip(_keep)) {
      await http.delete(Uri.parse('$_api/drive/v3/files/${old['id']}'), headers: h);
    }
    Prefs.driveLinked = true;
    Prefs.lastBackupMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// True if this Google account already has a backup in Drive (e.g. from a previous install).
  Future<bool> hasBackup() async {
    final h = await _headers();
    return (await _list(h)).any((f) => (f['name'] as String).startsWith('backup_'));
  }

  Timer? _timer;
  bool _running = false;

  /// Called after every data change: waits a little (so a burst of edits is one backup), then backs up in the
  /// background. Silent: never opens a sign-in or permission screen, and quietly retries on the next change/open.
  void scheduleAuto() {
    if (!Prefs.driveLinked) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 45), _auto);
  }

  /// On app start: if linked and the last backup is over a day old, back up now.
  Future<void> autoOnStart() async {
    if (!Prefs.driveLinked) return;
    final last = Prefs.lastBackupMs ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last > const Duration(hours: 20).inMilliseconds) await _auto();
  }

  Future<void> _auto() async {
    if (_running) return;
    _running = true;
    try {
      await backupNow(silent: true);
    } catch (_) {
      // offline / token expired: tried again at the next change or app start
    } finally {
      _running = false;
    }
  }

  /// Restores the newest backup. Returns false when none exists.
  Future<bool> restoreLatest() async {
    final h = await _headers();
    final backups = (await _list(h)).where((f) => (f['name'] as String).startsWith('backup_')).toList();
    if (backups.isEmpty) return false;
    final r = await http.get(Uri.parse('$_api/drive/v3/files/${backups.first['id']}?alt=media'), headers: h);
    if (r.statusCode != 200) throw StateError('Drive: ${r.statusCode}');
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

    // Re-download images into this device's documents dir and rewrite the stored paths.
    final dir = (await getApplicationDocumentsDirectory()).path;
    final files = {for (final f in await _list(h)) f['name'] as String: f['id'] as String};
    String fix(String old) {
      final target = p.join(dir, p.basename(old));
      return target;
    }
    Future<void> fetch(String old) async {
      final id = files['img_${p.basename(old)}'];
      if (id == null) return;
      final res = await http.get(Uri.parse('$_api/drive/v3/files/$id?alt=media'), headers: h);
      if (res.statusCode == 200) await File(fix(old)).writeAsBytes(res.bodyBytes);
    }
    for (final m in (data['members'] as List).cast<Map>()) {
      final ph = m['photo_path'] as String?;
      if (ph != null) { await fetch(ph); m['photo_path'] = fix(ph); }
    }
    for (final (table, col) in [('visits', 'prescriptions'), ('tests', 'files')]) {
      for (final row in (data[table] as List).cast<Map>()) {
        final s = row[col] as String?;
        if (s == null || s.isEmpty) continue;
        final list = (jsonDecode(s) as List).cast<String>();
        for (final old in list) { await fetch(old); }
        row[col] = jsonEncode(list.map(fix).toList());
      }
    }
    await LocalDb.instance.replaceAll(data);
    return true;
  }
}
