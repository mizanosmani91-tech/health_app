import '../core/config.dart';
import 'api.dart';

class DrugHit {
  final String name, generic, strength, form, manufacturer;
  const DrugHit(this.name, this.generic, this.strength, this.form, this.manufacturer);
  String get label => strength.isEmpty ? name : '$name $strength';
}

/// Medicine-name suggestions from the server's list. Empty when offline or on any error (typing always works).
Future<List<DrugHit>> searchDrugs(String q) async {
  final t = q.trim();
  if (!Config.hasBackend || t.length < 2) return const [];
  try {
    final rows = await Api.instance.list('/drugs/search', query: {'q': t});
    return [for (final r in rows) DrugHit('${r['name']}', '${r['generic'] ?? ''}', '${r['strength'] ?? ''}', '${r['form'] ?? ''}', '${r['manufacturer'] ?? ''}')];
  } catch (_) {
    return const [];
  }
}
