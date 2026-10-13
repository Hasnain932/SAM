part of '../main.dart';

// Old Firestore paths, used only for migration and delete.

// ---- Old paths (from before sections existed), used only for migration and
// delete ----
CollectionReference<Map<String, dynamic>> legacyStudentsRef(String deptId) =>
    FirebaseFirestore.instance
        .collection('departments')
        .doc(deptId)
        .collection('students');

CollectionReference<Map<String, dynamic>> legacySubjectsRef(String deptId) =>
    FirebaseFirestore.instance
        .collection('departments')
        .doc(deptId)
        .collection('subjects');

CollectionReference<Map<String, dynamic>> legacyDatesRef(
    String deptId, String subjectName) {
  if (deptId == kSoftwareEngineeringDeptId) {
    return FirebaseFirestore.instance
        .collection('attendance')
        .doc(subjectName)
        .collection('dates');
  }
  return FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .collection('attendance')
      .doc(subjectName)
      .collection('dates');
}
