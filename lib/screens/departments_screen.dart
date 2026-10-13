part of '../main.dart';

// Departments screen (first screen after login).

// Departments screen (first screen after login, for admin and teacher)
class DepartmentsScreen extends StatefulWidget {
  // claimMode: the teacher's "Claim Subject" flow (Department -> Section ->
  // Semester -> Subject; tap to claim).
  final bool claimMode;
  const DepartmentsScreen({super.key, this.claimMode = false});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  bool _seeded = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasOffline = false;
  Timer? _seedGuard;

  bool get _isAdmin => AppSession.isAdmin;

  @override
  void initState() {
    super.initState();
    if (widget.claimMode) {
      // The teacher home already did the prefetch and sync.
      _seeded = true;
      return;
    }
    if (_isAdmin) {
      unawaited(_adminBootstrap());
      // Never keep the admin on a spinner because of a slow network.
      _seedGuard = Timer(const Duration(seconds: 3), () {
        if (mounted && !_seeded) setState(() => _seeded = true);
      });
    } else {
      _seeded = true;
      unawaited(syncLocalDbIfStale());
    }
    unawaited(prefetchAllData());
    unawaited(_isOnline().then((on) => _wasOffline = !on));

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      resetNetCache();
      final isOffline = results.every((r) => r == ConnectivityResult.none);
      if (_wasOffline && !isOffline) {
        unawaited(prefetchAllData());
        unawaited(syncLocalDbIfStale());
      }
      _wasOffline = isOffline;
    });
  }

  @override
  void dispose() {
    _seedGuard?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // On admin login, run in order: seed -> second admin -> copy old Software
  // Engineering data to Section A / Semester 3 -> local sync.
  Future<void> _adminBootstrap() async {
    await _ensureSeedData();
    await ensureHiddenAdminDepartment();
    final moved = await migrateSoftwareEngineeringLegacy();
    if (moved && mounted) {
      showSnack(context,
          'Old Software Engineering data has been moved into Section A / Semester 3.');
    }
    await syncLocalDbIfStale();
  }

  Future<void> _ensureSeedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('seed_done_v1') == true) {
      unawaited(FirebaseFirestore.instance
          .collection('meta')
          .doc('seed')
          .set({'done': true}, SetOptions(merge: true)).catchError((_) {}));
      if (mounted) setState(() => _seeded = true);
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final deptsCollection = firestore.collection('departments');

      if (!await _isOnline()) {
        if (mounted) setState(() => _seeded = true);
        return;
      }

      final metaSnap = await firestore
          .collection('meta')
          .doc('seed')
          .get()
          .timeout(_kNetworkTimeout);
      if (metaSnap.exists && metaSnap.data()?['done'] == true) {
        await prefs.setBool('seed_done_v1', true);
        if (mounted) setState(() => _seeded = true);
        return;
      }

      for (var name in fixedDepartments) {
        final docRef = deptsCollection.doc(name);
        final snap = await docRef.get().timeout(_kNetworkTimeout);
        if (!snap.exists) {
          await docRef.set({'name': name});
        }
      }

      // Old Software Engineering data is now seeded directly into Section A / Semester 3.
      final target = SemRef(kSoftwareEngineeringDeptId, 'A', '3');
      final studentsSnap = await target.students.limit(1).get().timeout(_kNetworkTimeout);
      if (studentsSnap.docs.isEmpty) {
        var batch = firestore.batch();
        for (var s in initialStudents) {
          batch.set(target.students.doc(s['roll']),
              {'roll': s['roll'], 'name': s['name']});
        }
        await batch.commit();
      }

      final subjectsSnap = await target.subjects.limit(1).get().timeout(_kNetworkTimeout);
      if (subjectsSnap.docs.isEmpty) {
        var batch2 = firestore.batch();
        for (var sub in initialSubjects) {
          batch2.set(target.subjects.doc(sub), {'name': sub});
        }
        await batch2.commit();
      }

      await firestore
          .collection('meta')
          .doc('seed')
          .set({'done': true}).timeout(_kNetworkTimeout);
      await prefs.setBool('seed_done_v1', true);
    } catch (_) {}

    if (mounted) setState(() => _seeded = true);
  }

  // Departments have no passwords now, so the user types the name to confirm delete.
  void _confirmDeleteDepartment(String deptId, String deptName) {
    final controller = TextEditingController();
    String? errorText;
    bool busy = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Delete Department?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "All sections, semesters, students, subjects and attendance under '$deptName' will be permanently deleted. This cannot be undone.",
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Type the department name to confirm',
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (controller.text.trim() != deptName) {
                        setDialogState(() => errorText = 'Name does not match');
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                      });
                      try {
                        await deleteDepartmentEverywhere(deptId);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          showSnack(context, "Deleted department '$deptName'");
                        }
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          errorText = 'Could not delete. Please try again.';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Delete', style: TextStyle(color: kAbsent)),
            ),
          ],
        ),
      ),
    );
  }

  // Only the department name is needed now (no username or password).
  void _showAddDepartmentDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Department'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Department Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty || name.contains('/')) return;

              final docRef =
                  FirebaseFirestore.instance.collection('departments').doc(name);
              final existing = await safeGetDocOrNull(docRef);
              if (existing != null && existing.exists) {
                if (context.mounted) {
                  showSnack(context, 'This department name already exists');
                }
                return;
              }

              unawaited(docRef.set({'name': name}).catchError((_) {}));
              unawaited(LocalDb.upsertDepartment(name, name));

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Admin only: only the display name changes; the department's ID stays the same.
  Future<void> _showRenameDepartmentDialog(String deptId, String deptName) async {
    final done = await showRenameDialog(
      context,
      title: 'Rename Department',
      label: 'Department Name',
      initial: deptName,
      onSave: (v) => renameDepartment(deptId, v),
    );
    if (done && mounted) showSnack(context, 'Department renamed');
  }

  // Admin only: delete the overall attendance of every subject.
  void _confirmDeleteOverallAttendance() {
    bool busy = false;
    String? errorText;
    String? backupNote;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Delete overall attendance?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes the attendance records of EVERY subject in every department: from the server (Firebase), the local SQLite database and this device.\n\nDepartments, subjects and students are not touched. This cannot be undone.',
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Note: take a backup first, so you can restore it if this was a mistake.',
                  style: TextStyle(
                      color: kAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (backupNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(backupNote!,
                      style: const TextStyle(color: kPresent, fontSize: 13)),
                ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(errorText!,
                      style: const TextStyle(color: kAbsent, fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                        backupNote = null;
                      });
                      try {
                        if ((await _netState()) != _Net.reachable) {
                          throw Exception('offline');
                        }
                        final n = await createBackupFile();
                        setDialogState(() {
                          busy = false;
                          backupNote = 'Backup ready ($n records).';
                        });
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          errorText =
                              'Backup failed. Check your internet and try again.';
                        });
                      }
                    },
              child: const Text('Backup now'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                      });
                      if ((await _netState()) != _Net.reachable) {
                        setDialogState(() {
                          busy = false;
                          errorText =
                              'Internet is required so the records are also removed from the server. Please connect and try again.';
                        });
                        return;
                      }
                      try {
                        await deleteAllAttendanceEverywhere();
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          showSnack(context, 'All attendance records deleted');
                        }
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          errorText =
                              'Could not delete. Please check your connection and try again.';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Delete everything',
                      style: TextStyle(color: kAbsent)),
            ),
          ],
        ),
      ),
    );
  }

  // Master switch: one button that applies to all teachers at once.
  void _showMasterSwitch() {
    final items = <({String key, String label, IconData icon})>[
      (key: kPermAnytime, label: 'TIME', icon: Icons.schedule),
      (key: kPermChangeTime, label: 'SET TIME', icon: Icons.access_time),
      (key: kPermChangeDate, label: 'DATE', icon: Icons.calendar_today),
      (key: kPermEdit, label: 'EDIT', icon: Icons.edit_outlined),
      (key: kPermDelete, label: 'DELETE', icon: Icons.delete_outline),
      (key: kPermChangeType, label: 'CLASS/LAB', icon: Icons.swap_horiz),
    ];

    void setPerms(Map<String, dynamic> m) {
      unawaited(permissionsRef()
          .set(m, SetOptions(merge: true))
          .catchError((_) {}));
    }

    showDialog(
      context: context,
      builder: (dialogContext) =>
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: permissionsRef().snapshots(),
        builder: (ctx, snap) {
          final d = snap.data?.data() ?? <String, dynamic>{};
          final on = d[kPermMaster] == true;
          return AlertDialog(
            title: const Text('Teacher permissions'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: on,
                      title: Text(on ? 'Master switch: ON' : 'Master switch: OFF'),
                      subtitle: const Text('ALL',
                          style: TextStyle(
                              color: kAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      onChanged: (v) => setPerms({kPermMaster: v}),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      on
                          ? 'Teachers can mark attendance at any time, add attendance for past dates, edit or delete records, convert Class/Lab sessions, and change the time or session.'
                          : 'Master switch OFF: turn on the options below one by one to give a teacher only that ability.',
                      style: const TextStyle(color: kMuted, fontSize: 13),
                    ),
                    const Divider(height: 20, color: kOutline),
                    // Grouped box: visually separates the five individual
                    // permissions from the master switch above.
                    Container(
                      decoration: BoxDecoration(
                        color: kSurfaceHi,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kOutline),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final it in items)
                            SwitchListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              secondary: Icon(it.icon, color: kAccent),
                              value: on || d[it.key] == true,
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: kAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      it.label,
                                      style: const TextStyle(
                                          color: kAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                _permSubtitle(it.key),
                                style:
                                    const TextStyle(color: kMuted, fontSize: 12),
                              ),
                              onChanged: on ? null : (v) => setPerms({it.key: v}),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Short English explanation shown under each permission's code label.
  String _permSubtitle(String key) {
    switch (key) {
      case kPermAnytime:
        return 'TIME: let the teacher mark attendance any time, not just the first $kMarkWindowMinutes minutes of the hour.';
      case kPermChangeTime:
        return 'SET TIME: let the teacher pick the class time manually.';
      case kPermChangeDate:
        return 'DATE: let the teacher choose any date, not just today.';
      case kPermEdit:
        return 'EDIT: let the teacher change attendance that is already taken.';
      case kPermDelete:
        return 'DELETE: let the teacher delete attendance records.';
      case kPermChangeType:
        return 'CLASS/LAB: let the teacher convert a session between Class and Lab Class.';
      default:
        return '';
    }
  }

  void _showBackupRestore() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Backup & Restore'),
        content: const Text(
          'Backup saves all departments, subjects, students, teachers and attendance into one file that you can keep safely (phone, Google Drive, email).\n\n'
          'Restore reads that file and puts the data back if something was deleted by mistake.\n\n'
          'The file contains teacher passwords, so keep it private.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (mounted) restoreFromBackupUi(context);
            },
            child: const Text('Restore'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (mounted) runBackupWithUi(context);
            },
            child: const Text('Backup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.claimMode;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        toolbarHeight: 84,
        title: HeaderCard(
          title: claim ? 'Claim Subject' : 'Departments',
          actions: [
            if (_isAdmin && !claim)
              HeaderTile(
                icon: Icons.tune,
                tooltip: 'Teacher permissions (master switch)',
                onTap: _showMasterSwitch,
              ),
            if (_isAdmin && !claim) const TeacherRequestsButton(),
            if (_isAdmin && !claim)
              HeaderTile(
                icon: Icons.cloud_upload_outlined,
                tooltip: 'Backup & Restore',
                onTap: _showBackupRestore,
              ),
            if (_isAdmin && !claim)
              HeaderTile(
                icon: Icons.delete_sweep_outlined,
                color: kAbsent,
                tooltip: 'Delete overall attendance',
                onTap: _confirmDeleteOverallAttendance,
              ),
            if (!claim)
              HeaderTile(
                icon: Icons.logout,
                color: Colors.white,
                tile: false,
                tooltip: 'Logout',
                onTap: () => confirmAndLogout(context),
              ),
          ],
        ),
      ),
      floatingActionButton: (_isAdmin && !claim)
          ? FloatingActionButton(
              onPressed: _showAddDepartmentDialog,
              backgroundColor: kButton,
              foregroundColor: kOnAccent,
              child: const Icon(Icons.add),
            )
          : null,
      body: !_seeded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (claim)
                  const InfoBanner(
                    text:
                        'Pick a department, then a section and semester. Tap a subject to claim it.',
                    icon: Icons.bookmark_add_outlined,
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: liveQuery(FirebaseFirestore.instance
                        .collection('departments')
                        .orderBy('name')),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      // Do not show the hidden admin in the department list.
                      final docs = (snapshot.data?.docs ?? [])
                          .where((d) => d.id != kHiddenAdminDeptName)
                          .toList();
                      if (!snapshot.hasData || docs.isEmpty) {
                        return const EmptyState(
                            icon: Icons.apartment, text: 'No department found.');
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 90),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final deptId = docs[index].id;
                          final deptName = (data['name'] ?? deptId).toString();

                          return AppCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SectionsScreen(
                                    deptId: deptId, deptName: deptName),
                              ),
                            ),
                            child: Row(
                              children: [
                                const IconBadge(icon: Icons.apartment),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(deptName,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                ),
                                if (_isAdmin && !claim) ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        color: kAccent),
                                    tooltip: 'Rename department',
                                    onPressed: () => _showRenameDepartmentDialog(
                                        deptId, deptName),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: kAbsent),
                                    tooltip: 'Delete department',
                                    onPressed: () => _confirmDeleteDepartment(
                                        deptId, deptName),
                                  ),
                                ] else if (_isAdmin)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: kAbsent),
                                    tooltip: 'Delete department',
                                    onPressed: () => _confirmDeleteDepartment(
                                        deptId, deptName),
                                  )
                                else
                                  const Icon(Icons.chevron_right, color: kMuted),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
