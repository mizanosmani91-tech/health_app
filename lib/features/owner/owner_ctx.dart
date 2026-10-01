import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';

/// Holds the signed-in owner's pharmacy row and a version counter that owner
/// screens watch to re-query after a write.
class OwnerCtx extends ChangeNotifier {
  SupabaseClient get db => AuthService.instance.client;
  Map<String, dynamic>? pharmacy;
  int version = 0;

  String get pid => pharmacy!['id'] as String;
  bool get verified => pharmacy?['status'] == 'verified';

  Future<void> load() async {
    pharmacy = await db.from('pharmacies').select().eq('owner_id', AuthService.instance.user!.id).maybeSingle();
    notifyListeners();
  }

  void touch() {
    version++;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> rows(PostgrestTransformBuilder<PostgrestList> q) async =>
      (await q).cast<Map<String, dynamic>>();
}
