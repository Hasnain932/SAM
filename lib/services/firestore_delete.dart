part of '../main.dart';

// Delete helpers for Firestore.

// Firestore delete helpers
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getDocsForDelete(
    Query<Map<String, dynamic>> query) async {
  try {
    if (await _isOnline()) {
      final snap = await query.get().timeout(const Duration(seconds: 10));
      return snap.docs;
    }
  } catch (_) {}
  try {
    final snap = await query.get(const GetOptions(source: Source.cache));
    return snap.docs;
  } catch (_) {
    return [];
  }
}

void _deleteDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  for (int i = 0; i < docs.length; i += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs.skip(i).take(400)) {
      batch.delete(d.reference);
    }
    unawaited(batch.commit().catchError((_) {}));
  }
}

// When a subject is deleted, also remove the teacher's claim on it.
Future<void> _cleanupClaimOfSubject(
    SemRef sem, String subject, Map<String, dynamic>? subjectData) async {
  final cb = (subjectData?['claimed_by'] ?? '').toString();
  if (cb.isEmpty) return;
  unawaited(teacherClaimsRef(cb)
      .doc(sem.claimKey(subject))
      .delete()
      .catchError((_) {}));
  await LocalDb.deleteClaim(cb, sem, subject);
}

Future<void> deleteSubjectEverywhere(SemRef sem, String subject) async {
  final subSnap = await safeGetDocOrNull(sem.subjectDoc(subject));
  await _cleanupClaimOfSubject(sem, subject, subSnap?.data());
  _deleteDocs(await _getDocsForDelete(sem.dates(subject)));
  _deleteDocs(await _getDocsForDelete(sem.overrides(subject)));
  unawaited(sem.subjectDoc(subject).delete().catchError((_) {}));
  await LocalDb.deleteSubject(sem, subject);
}
