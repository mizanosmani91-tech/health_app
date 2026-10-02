import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import 'prefs.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  bool get unauthorized => status == 401;
  @override
  String toString() => switch (status) {
        0 => 'ইন্টারনেট/সার্ভারে সংযোগ হয়নি',
        401 => 'আবার লগইন করুন',
        403 => 'এই কাজের অনুমতি নেই',
        404 => 'পাওয়া যায়নি',
        409 => 'এটা আগেই আছে (একই বারকোড বা তথ্য)',
        429 => 'একটু পরে চেষ্টা করুন',
        _ => message,
      };
}

/// Thin JSON client for the Health Diary API (see /server).
class Api {
  Api._();
  static final instance = Api._();

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('${Config.apiBase}$path').replace(queryParameters: q);

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final req = http.Request(method, _u(path, query))..headers['content-type'] = 'application/json';
    final t = Prefs.apiToken;
    if (t != null) req.headers['authorization'] = 'Bearer $t';
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw ApiException(0, 'network');
    }
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    dynamic data;
    try { data = jsonDecode(utf8.decode(res.bodyBytes)); } catch (_) { data = null; }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, data is Map ? '${data['error'] ?? 'error'}' : 'error ${res.statusCode}');
    }
    return data;
  }

  Future<dynamic> get(String p, {Map<String, String>? query}) => _send('GET', p, query: query);
  Future<dynamic> post(String p, [Object? body]) => _send('POST', p, body: body ?? {});
  Future<dynamic> put(String p, Object body) => _send('PUT', p, body: body);
  Future<dynamic> patch(String p, Object body) => _send('PATCH', p, body: body);
  Future<dynamic> delete(String p) => _send('DELETE', p);

  Future<List<Map<String, dynamic>>> list(String p, {Map<String, String>? query}) async =>
      ((await get(p, query: query)) as List).cast<Map<String, dynamic>>();
}
