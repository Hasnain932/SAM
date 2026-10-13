part of '../main.dart';

// What teachers are allowed to do.

// ---- Teacher permissions (settings/permissions) ----
// kPermMaster ON: teachers can do everything. OFF: each permission below applies
// on its own. A missing field means "not allowed".
const String kPermMaster = 'teachers_unrestricted';
const String kPermAnytime = 'perm_anytime'; // mark outside the 20-minute window
const String kPermChangeTime = 'perm_change_time'; // pick the class time
const String kPermChangeDate = 'perm_change_date'; // pick other / past dates
const String kPermEdit = 'perm_edit'; // edit existing records
const String kPermDelete = 'perm_delete'; // delete records
const String kPermChangeType = 'perm_change_type'; // convert Class <-> Lab
const List<String> kDetailedPerms = [
  kPermAnytime,
  kPermChangeTime,
  kPermChangeDate,
  kPermEdit,
  kPermDelete,
  kPermChangeType,
];

class TeacherPerms {
  final bool master;
  final bool anytime;
  final bool changeTime;
  final bool changeDate;
  final bool edit;
  final bool delete;
  final bool changeType; // may convert a session between Class and Lab
  const TeacherPerms({
    this.master = false,
    this.anytime = false,
    this.changeTime = false,
    this.changeDate = false,
    this.edit = false,
    this.delete = false,
    this.changeType = false,
  });

  static const TeacherPerms none = TeacherPerms();

  factory TeacherPerms.from(Map<String, dynamic>? d) {
    if (d == null) return none;
    return TeacherPerms(
      master: d[kPermMaster] == true,
      anytime: d[kPermAnytime] == true,
      changeTime: d[kPermChangeTime] == true,
      changeDate: d[kPermChangeDate] == true,
      edit: d[kPermEdit] == true,
      delete: d[kPermDelete] == true,
      changeType: d[kPermChangeType] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TeacherPerms &&
      other.master == master &&
      other.anytime == anytime &&
      other.changeTime == changeTime &&
      other.changeDate == changeDate &&
      other.edit == edit &&
      other.delete == delete &&
      other.changeType == changeType;

  @override
  int get hashCode =>
      Object.hash(
          master, anytime, changeTime, changeDate, edit, delete, changeType);
}
