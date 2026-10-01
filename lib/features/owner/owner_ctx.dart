import 'package:flutter/foundation.dart';
import '../../services/api.dart';

/// Holds the signed-in owner's pharmacy and a version counter that owner
/// screens watch to re-query after a write.
class OwnerCtx extends ChangeNotifier {
  final api = Api.instance;
  Map<String, dynamic>? pharmacy;
  String? error;
  int version = 0;

  bool get verified => pharmacy?['status'] == 'verified';

  Future<void> load() async {
    try {
      pharmacy = await api.get('/pharmacy') as Map<String, dynamic>;
      error = null;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> updatePharmacy(Map<String, Object?> data) async {
    pharmacy = await api.patch('/pharmacy', data) as Map<String, dynamic>;
    notifyListeners();
  }

  Future<void> saveStock(String? id, Map<String, Object?> data) =>
      id == null ? api.post('/stock', data) : api.patch('/stock/$id', data);
  Future<void> setStockStatus(String id, String status) => api.patch('/stock/$id', {'status': status});
  Future<void> deleteStock(String id) => api.delete('/stock/$id');

  void touch() {
    version++;
    notifyListeners();
  }
}

DateTime? ts(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
