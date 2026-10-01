import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../services/auth_service.dart';

/// Holds the signed-in owner's pharmacy doc (id == owner uid) and a version
/// counter that owner screens watch to re-query after a write.
class OwnerCtx extends ChangeNotifier {
  final db = AuthService.instance.db;
  Map<String, dynamic>? pharmacy;
  int version = 0;

  String get pid => AuthService.instance.user!.uid;
  DocumentReference<Map<String, dynamic>> get ref => db.collection('pharmacies').doc(pid);
  bool get verified => pharmacy?['status'] == 'verified';

  Future<void> load() async {
    pharmacy = (await ref.get()).data();
    notifyListeners();
  }

  Future<void> updatePharmacy(Map<String, Object?> data) async {
    await ref.update(data);
    await load();
  }

  /// Private stock doc (prices, qty, batch) + the public mirror patients can read
  /// (name + in/low/out only), written together so they never drift apart.
  Future<void> saveStock(String? id, Map<String, Object?> data) async {
    final doc = ref.collection('stock').doc(id);
    final b = db.batch();
    b.set(doc, {...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    b.set(db.collection('stockPublic').doc(pid), {
      'items': {doc.id: {'n': data['name'], 'g': data['genericName'], 's': data['status']}},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await b.commit();
  }

  Future<void> setStockStatus(String id, String status) async {
    final b = db.batch();
    b.update(ref.collection('stock').doc(id), {'status': status, 'updatedAt': FieldValue.serverTimestamp()});
    b.set(db.collection('stockPublic').doc(pid), {
      'items': {id: {'s': status}},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await b.commit();
  }

  Future<void> deleteStock(String id) async {
    final b = db.batch();
    b.delete(ref.collection('stock').doc(id));
    b.set(db.collection('stockPublic').doc(pid), {'items': {id: FieldValue.delete()}}, SetOptions(merge: true));
    await b.commit();
  }

  void touch() {
    version++;
    notifyListeners();
  }
}

/// Doc data + its id, since Firestore keeps the id outside the map.
Map<String, dynamic> withId(DocumentSnapshot<Map<String, dynamic>> d) => {...?d.data(), 'id': d.id};

DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
