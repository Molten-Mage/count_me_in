import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/counter.dart';
import 'counter_storage.dart';

class FirestoreCounterStorage implements CounterStorage {
  FirestoreCounterStorage({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('users').doc(_uid);

  @override
  Future<List<Counter>> loadCounters() async {
    final snapshot = await _doc.get();
    final counters = snapshot.data()?['counters'] as List<dynamic>?;
    if (counters == null) return [];
    return counters
        .map((e) => Counter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveCounters(List<Counter> counters) async {
    await _doc.set(
      {'counters': counters.map((c) => c.toJson()).toList()},
      SetOptions(merge: true),
    );
  }
}
