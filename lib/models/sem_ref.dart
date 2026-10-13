part of '../main.dart';

// Points to one semester + Firestore path helpers.

// Firestore path helpers
// departments/{dept}/sections/{A-D}/semesters/{1-8}/
//     students/{key}      key = roll; duplicate rolls become roll__2, roll__3 ...
//     subjects/{name}                    (claimed_by, claimed_by_name)
//     subjects/{name}/overrides/{roll}   (subject-level add / soft-remove)
//     attendance/{subject}/dates/{date_Session_n}
class SemRef {
  final String deptId;
  final String section;
  final String semester;
  const SemRef(this.deptId, this.section, this.semester);

  DocumentReference<Map<String, dynamic>> get doc => FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .collection('sections')
      .doc(section)
      .collection('semesters')
      .doc(semester);

  CollectionReference<Map<String, dynamic>> get students =>
      doc.collection('students');
  CollectionReference<Map<String, dynamic>> get subjects =>
      doc.collection('subjects');
  DocumentReference<Map<String, dynamic>> subjectDoc(String subject) =>
      subjects.doc(subject);
  CollectionReference<Map<String, dynamic>> overrides(String subject) =>
      subjectDoc(subject).collection('overrides');
  CollectionReference<Map<String, dynamic>> dates(String subject) =>
      doc.collection('attendance').doc(subject).collection('dates');

  String claimKey(String subject) => '$deptId|$section|$semester|$subject';
}

String defaultSemesterLabel(String semesterId) => 'Semester $semesterId';

CollectionReference<Map<String, dynamic>> teacherClaimsRef(String teacherId) =>
    FirebaseFirestore.instance
        .collection('teachers')
        .doc(teacherId)
        .collection('claims');

DocumentReference<Map<String, dynamic>> permissionsRef() =>
    FirebaseFirestore.instance.collection('settings').doc('permissions');
