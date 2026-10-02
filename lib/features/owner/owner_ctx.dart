import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../core/widgets.dart';
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

extension OwnerNav on BuildContext {
  /// Pushed routes live outside the shell's provider, so hand the owner context to them explicitly.
  Future<T?> pushOwner<T>(Widget page) => push<T>(ChangeNotifierProvider<OwnerCtx>.value(value: read<OwnerCtx>(), child: page));
}
