part of 'main.dart';

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
              {'roll': s['roll'], 'name': s['name'], 'father': ''});
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
    } catch (e) {
      debugPrint('browse_screens.dart:141: $e');
    }

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
                        final n = await createBackupFile(mounted ? context : null);
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
    // Class <-> Lab and Mid <-> Final conversion are always allowed, and Edit
    // also covers Delete, so none of those are listed here.
    final items = <({String key, String label, IconData icon})>[
      (key: kPermAnytime, label: 'TIME', icon: Icons.schedule),
      (key: kPermChangeTime, label: 'SET TIME', icon: Icons.access_time),
      (key: kPermChangeDate, label: 'DATE', icon: Icons.calendar_today),
      (key: kPermEdit, label: 'EDIT / DELETE', icon: Icons.edit_outlined),
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
          final announced = announcedPhaseFrom(d);
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: kGlassBorder),
              ),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const IconBadge(icon: Icons.tune, size: 44),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Teacher permissions',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEAF6FF),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Choose what teachers can do',
                              style: TextStyle(color: kLabelBlue, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Exam phase announcement: Mid / Final
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: kCardGrad,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kGlassBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const IconBadge(
                                        icon: Icons.campaign_outlined,
                                        size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  announced == null
                                                      ? 'Exam phase: not announced'
                                                      : 'Exam phase: ${phaseLabel(announced)}',
                                                  style: const TextStyle(
                                                    color: Color(0xFFEAF6FF),
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const _PermChip('MID / FINAL'),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            announced == kPhaseFinal
                                                ? 'Teachers whose subject is still in Mid see a reminder and cannot take attendance until they switch it to Final.'
                                                : announced == kPhaseMid
                                                    ? 'Teachers whose subject is still in Final see a reminder and cannot take attendance until they switch it to Mid.'
                                                    : 'Tap Mid or Final to remind every teacher to switch their subject to that phase.',
                                            style: const TextStyle(
                                                color: kMuted, fontSize: 12.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: GradPill(
                                        label: 'Mid',
                                        expand: true,
                                        height: 40,
                                        filled: announced == kPhaseMid,
                                        onTap: announced == kPhaseMid
                                            ? null
                                            : () => saveAnnouncedPhase(kPhaseMid),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: GradPill(
                                        label: 'Final',
                                        expand: true,
                                        height: 40,
                                        filled: announced == kPhaseFinal,
                                        onTap: announced == kPhaseFinal
                                            ? null
                                            : () => saveAnnouncedPhase(kPhaseFinal),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Master switch card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: kCardGrad,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kGlassBorder),
                            ),
                            child: Row(
                              children: [
                                const IconBadge(
                                    icon: Icons.verified_user_outlined,
                                    size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              on
                                                  ? 'Master switch: ON'
                                                  : 'Master switch: OFF',
                                              style: const TextStyle(
                                                color: Color(0xFFEAF6FF),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const _PermChip('ALL'),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        on
                                            ? 'Teachers can do everything: mark at any time, pick any date or time, and edit or delete records.'
                                            : 'Turn on the options below one by one to give teachers only that ability.',
                                        style: const TextStyle(
                                            color: kMuted, fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _permSwitch(on, (v) => setPerms({kPermMaster: v})),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final it in items)
                            Opacity(
                              opacity: on ? 0.7 : 1,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: kGlass,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: kGlassBorder),
                                ),
                                child: Row(
                                  children: [
                                    IconBadge(icon: it.icon, size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _PermChip(it.label),
                                          const SizedBox(height: 4),
                                          Text(
                                            _permSubtitle(it.key),
                                            style: const TextStyle(
                                                color: kMuted, fontSize: 12.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _permSwitch(
                                      on || d[it.key] == true,
                                      on ? null : (v) => setPerms({it.key: v}),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GradPill(
                      label: 'Close',
                      onTap: () => Navigator.pop(dialogContext),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Switch in the app's blue (no outline, white thumb).
  Widget _permSwitch(bool value, ValueChanged<bool>? onChanged) {
    return Switch(
      value: value,
      onChanged: onChanged,
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return states.contains(WidgetState.disabled)
              ? kAccent.withValues(alpha: 0.6)
              : kAccent;
        }
        return const Color(0x33FFFFFF);
      }),
    );
  }

  // Short English explanation shown under each permission's label.
  String _permSubtitle(String key) {
    switch (key) {
      case kPermAnytime:
        return 'Let the teacher mark attendance any time, not just the first $kMarkWindowMinutes minutes of the hour.';
      case kPermChangeTime:
        return 'Let the teacher pick the class time manually.';
      case kPermChangeDate:
        return 'Let the teacher choose any date, not just today.';
      case kPermEdit:
        return 'Let the teacher change or delete attendance that is already taken.';
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
                tooltip: 'Teacher permissions & exam phase',
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
          ? GradFab(onPressed: _showAddDepartmentDialog)
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
                                  child: Text(deptName, style: kNameStyle),
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

// Sections screen: Department -> Section A / B / C / D
class SectionsScreen extends StatelessWidget {
  final String deptId;
  final String deptName;
  const SectionsScreen({super.key, required this.deptId, required this.deptName});

  // Admin only: add a new section (A-D are built in).
  void _showAddSectionDialog(BuildContext context, List<String> existing) {
    final controller = TextEditingController();
    String? errorText;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Add New Section'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Section name (e.g. E)',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim().toUpperCase();
                if (name.isEmpty || name.contains('/') || name.contains('|')) {
                  setLocal(() => errorText = 'Enter a valid section name');
                  return;
                }
                if (existing.contains(name)) {
                  setLocal(() => errorText = 'This section already exists');
                  return;
                }
                unawaited(deptDocRef(deptId)
                    .set({
                      'extra_sections': FieldValue.arrayUnion([name])
                    }, SetOptions(merge: true))
                    .catchError((_) {}));
                Navigator.pop(dialogContext);
                if (context.mounted) showSnack(context, 'Section $name added');
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: deptDocRef(deptId).snapshots(),
      builder: (context, snapshot) {
        final sections = sectionsFrom(snapshot.data?.data());
        return Scaffold(
          appBar: headerAppBar(title: deptName),
          floatingActionButton: AppSession.isAdmin
              ? GradFab(
                  onPressed: () => _showAddSectionDialog(context, sections))
              : null,
          body: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 90),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Choose a section',
                    style: TextStyle(color: kMuted, fontSize: 14)),
              ),
              for (final sec in sections)
                AppCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SemestersScreen(
                          deptId: deptId, deptName: deptName, section: sec),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [kAccent, kAccent2],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(sec,
                            style: const TextStyle(
                                color: kOnAccent,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('Section $sec', style: kNameStyle),
                      ),
                      const Icon(Icons.chevron_right, color: kMuted),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Semesters screen: Section -> Semester (default 1 to 8, names can be edited)
class SemestersScreen extends StatelessWidget {
  final String deptId;
  final String deptName;
  final String section;
  const SemestersScreen(
      {super.key,
      required this.deptId,
      required this.deptName,
      required this.section});

  void _editLabelDialog(BuildContext context, SemRef sem, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename semester'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Semester name'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only the name changes — students, subjects and attendance remain under this semester.',
              style: TextStyle(color: kMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              unawaited(sem.doc
                  .set({'label': FieldValue.delete()}, SetOptions(merge: true))
                  .catchError((_) {}));
              unawaited(LocalDb.deleteSemesterLabel(sem));
              Navigator.pop(dialogContext);
            },
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () {
              final label = controller.text.trim();
              if (label.isEmpty) return;
              unawaited(sem.doc
                  .set({'label': label}, SetOptions(merge: true))
                  .catchError((_) {}));
              unawaited(LocalDb.upsertSemesterLabel(sem, label));
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Admin only: add a new semester (1-8 are built in). The next free number
  // is used as its ID, and the name can be changed right here.
  void _showAddSemesterDialog(BuildContext context, List<String> existing) {
    final nums = existing.map(int.tryParse).whereType<int>().toList();
    final nextNum = nums.isEmpty ? 1 : nums.reduce((a, b) => a > b ? a : b) + 1;
    final newId = nextNum.toString();
    final controller = TextEditingController(text: defaultSemesterLabel(newId));
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add New Semester'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Semester name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final label = controller.text.trim();
              if (label.isEmpty) return;
              unawaited(deptDocRef(deptId)
                  .set({
                    'extra_semesters':
                        FieldValue.arrayUnion(['$section|$newId'])
                  }, SetOptions(merge: true))
                  .catchError((_) {}));
              if (label != defaultSemesterLabel(newId)) {
                final sem = SemRef(deptId, section, newId);
                unawaited(sem.doc
                    .set({'label': label}, SetOptions(merge: true))
                    .catchError((_) {}));
                unawaited(LocalDb.upsertSemesterLabel(sem, label));
              }
              Navigator.pop(dialogContext);
              if (context.mounted) showSnack(context, '$label added');
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelsStream = liveQuery(FirebaseFirestore.instance
        .collection('departments')
        .doc(deptId)
        .collection('sections')
        .doc(section)
        .collection('semesters'));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: deptDocRef(deptId).snapshots(),
      builder: (context, secSnap) {
        final semIds = semestersFrom(secSnap.data?.data(), section);
        return Scaffold(
          appBar: headerAppBar(title: deptName, subtitle: 'Section $section'),
          floatingActionButton: AppSession.isAdmin
              ? GradFab(
                  onPressed: () => _showAddSemesterDialog(context, semIds))
              : null,
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: labelsStream,
            builder: (context, snapshot) {
              final labels = <String, String>{};
              for (final d in snapshot.data?.docs ?? []) {
                final l = (d.data()['label'] ?? '').toString();
                if (l.isNotEmpty) labels[d.id] = l;
              }

              return ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 90),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text('Choose a semester',
                        style: TextStyle(color: kMuted, fontSize: 14)),
                  ),
                  for (final sid in semIds)
                    Builder(builder: (context) {
                      final sem = SemRef(deptId, section, sid);
                      final label = labels[sid] ?? defaultSemesterLabel(sid);
                      return AppCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SubjectsScreen(
                              deptName: deptName,
                              sem: sem,
                              semLabel: label,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const IconBadge(icon: Icons.event_note_outlined),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(label, style: kNameStyle),
                            ),
                            if (AppSession.isAdmin)
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    color: kMuted),
                                tooltip: 'Rename semester',
                                onPressed: () =>
                                    _editLabelDialog(context, sem, label),
                              )
                            else
                              const Icon(Icons.chevron_right, color: kMuted),
                          ],
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// Subjects screen (one department, section and semester)
// Admin: add / delete / open. Teacher: claim / unclaim / open (own subjects only).
class SubjectsScreen extends StatelessWidget {
  final String deptName;
  final SemRef sem;
  final String semLabel;
  const SubjectsScreen(
      {super.key,
      required this.deptName,
      required this.sem,
      required this.semLabel});

  void _confirmDeleteSubject(BuildContext context, String subjectName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Subject?'),
        content: Text(
            "Delete '$subjectName'? All of its attendance will also be permanently deleted."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await deleteSubjectEverywhere(sem, subjectName);
              if (context.mounted) {
                showSnack(context, "Deleted subject '$subjectName'");
              }
            },
            child: const Text('Delete', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameSubjectDialog(
      BuildContext context, String subjectName) async {
    final done = await showRenameDialog(
      context,
      title: 'Rename Subject',
      label: 'Subject Name',
      initial: subjectName,
      caps: TextCapitalization.characters,
      note:
          'All attendance, student changes and the teacher claim of this subject move to the new name. Internet is required.',
      onSave: (v) => renameSubjectEverywhere(sem, subjectName, v),
    );
    if (done && context.mounted) showSnack(context, 'Subject renamed');
  }

  void _showAddSubjectDialog(BuildContext context) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add New Subject'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Subject Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim().toUpperCase();
              if (name.isEmpty || name.contains('/')) return;
              // merge, so adding the same name again does not erase the claim
              unawaited(sem.subjectDoc(name).set(
                  {'name': name}, SetOptions(merge: true)).catchError((_) {}));
              unawaited(LocalDb.upsertSubject(sem, name));
              unawaited(refreshSubjectSummary(sem, name));
              Navigator.pop(dialogContext);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _openSubject(BuildContext context, String subjectName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubjectAttendanceScreen(
          sem: sem,
          semLabel: semLabel,
          subjectName: subjectName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.isAdmin;
    final myId = AppSession.teacherId;

    return Scaffold(
      appBar: headerAppBar(
        title: '$semLabel • ${sem.section}',
        actions: [
          if (isAdmin)
            HeaderTile(
              icon: Icons.groups_outlined,
              tooltip: 'Manage Students',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManageStudentsScreen(
                          sem: sem, semLabel: semLabel, deptName: deptName),
                ),
              ),
            ),
          if (isAdmin)
            HeaderTile(
              icon: Icons.sync_rounded,
              tooltip: 'Rebuild summaries (everything)',
              onTap: () async {
                // Keep the messenger, so messages show even if screen closes.
                final messenger = ScaffoldMessenger.of(context);
                summaryRebuildFails = 0;
                showStickySnack(messenger,
                    'Rebuilding summaries for everything... this can take a while');
                try {
                  final n = await rebuildAllSummaries();
                  if (summaryRebuildFails > 0) {
                    showStickySnack(
                        messenger,
                        'Rebuild had errors ($summaryRebuildFails failed). '
                        '$n subject(s) done. Please try again.',
                        color: Colors.red.shade700);
                  } else {
                    showStickySnack(messenger,
                        'Summaries rebuilt for $n subject(s) in all departments',
                        color: Colors.green.shade700);
                  }
                } catch (e) {
                  showStickySnack(messenger, 'Rebuild failed: $e',
                      color: Colors.red.shade700);
                }
              },
            ),
        ],
      ),
      floatingActionButton: isAdmin
          ? GradFab(onPressed: () => _showAddSubjectDialog(context))
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: liveQuery(sem.subjects.orderBy('name')),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return EmptyState(
              icon: Icons.menu_book_outlined,
              text: isAdmin
                  ? 'No subjects yet. Tap + to add.'
                  : 'No subjects here yet.',
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 90),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final subjectName = docs[index].id;
              final data = docs[index].data();
              final claimedBy = (data['claimed_by'] ?? '').toString();
              final claimedByName = (data['claimed_by_name'] ?? '').toString();
              final isMine = !isAdmin && claimedBy == myId && claimedBy.isNotEmpty;
              final takenByOther = claimedBy.isNotEmpty && !isMine;

              String? subtitle;
              if (takenByOther) {
                subtitle = 'Taken by ${claimedByName.isEmpty ? 'a teacher' : claimedByName}';
              } else if (isMine) {
                subtitle = 'Yours';
              }

              return AppCard(
                onTap: () {
                  if (isAdmin || isMine) {
                    _openSubject(context, subjectName);
                  } else if (takenByOther) {
                    showSnack(context, 'Taken by $claimedByName');
                  } else {
                    claimSubject(context, sem, subjectName);
                  }
                },
                child: Row(
                  children: [
                    IconBadge(
                      icon: Icons.menu_book_outlined,
                      color: takenByOther ? kMuted : kAccent,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subjectName,
                              style: kNameStyle.copyWith(fontSize: 15)),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isMine ? kPresent : kMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isAdmin) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: kAccent),
                        tooltip: 'Rename subject',
                        onPressed: () =>
                            _showRenameSubjectDialog(context, subjectName),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: kAbsent),
                        tooltip: 'Delete subject',
                        onPressed: () =>
                            _confirmDeleteSubject(context, subjectName),
                      ),
                    ] else if (isMine)
                      IconButton(
                        icon: const Icon(Icons.logout, color: kMuted),
                        tooltip: 'Leave this subject',
                        onPressed: () => unclaimSubject(context, sem, subjectName),
                      )
                    else if (!takenByOther)
                      const Icon(Icons.add_circle_outline, color: kAccent),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// My subjects (subjects the teacher has claimed, with full context)
class SemLabelText extends StatelessWidget {
  final SemRef sem;
  final TextStyle? style;
  const SemLabelText({super.key, required this.sem, this.style});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: safeGetDocOrNull(sem.doc),
      builder: (context, snap) {
        final l = (snap.data?.data()?['label'] ?? '').toString();
        return Text(l.isEmpty ? defaultSemesterLabel(sem.semester) : l,
            style: style);
      },
    );
  }
}

// Teacher home: only the subjects this teacher has claimed.
// The full department list is behind the "Claim Subject" icon.
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _approvalTimer;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    unawaited(AppSession.recheckTeacher());
    _approvalTimer = Timer.periodic(const Duration(minutes: 30),
        (_) => unawaited(AppSession.recheckTeacher()));
    unawaited(syncLocalDbIfStale());
    unawaited(prefetchAllData());
    unawaited(_isOnline().then((on) => _wasOffline = !on));
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      resetNetCache();
      final isOffline = results.every((r) => r == ConnectivityResult.none);
      if (_wasOffline && !isOffline) {
        unawaited(AppSession.recheckTeacher());
        unawaited(prefetchAllData());
        unawaited(syncLocalDbIfStale());
      }
      _wasOffline = isOffline;
    });
  }

  @override
  void dispose() {
    _approvalTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _open(BuildContext context, SemRef sem, String subject) async {
    final snap = await safeGetDocOrNull(sem.subjectDoc(subject));
    final cb = (snap?.data()?['claimed_by'] ?? '').toString();
    // Remove the entry only if the server confirms the subject is gone or reassigned.
    // Offline or unreadable: just open it and never remove a claim.
    final lost = snap != null &&
        !snap.metadata.isFromCache &&
        (!snap.exists || cb != AppSession.teacherId);
    if (lost) {
      unawaited(teacherClaimsRef(AppSession.teacherId)
          .doc(sem.claimKey(subject))
          .delete()
          .catchError((_) {}));
      unawaited(LocalDb.deleteClaim(AppSession.teacherId, sem, subject));
      if (context.mounted) {
        showSnack(context, 'This subject is no longer assigned to you.');
      }
      return;
    }
    final label = (await safeGetDocOrNull(sem.doc))?.data()?['label']?.toString();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubjectAttendanceScreen(
          sem: sem,
          semLabel: (label == null || label.isEmpty)
              ? defaultSemesterLabel(sem.semester)
              : label,
          subjectName: subject,
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Map<String, String>> raw) {
    if (raw.isEmpty) {
      return const EmptyState(
        icon: Icons.bookmark_border,
        text:
            'You have not claimed any subject yet.\nTap the + button (top right) to claim one.',
      );
    }
    final items = raw.toList()
      ..sort((a, b) => (a['subject'] ?? '').compareTo(b['subject'] ?? ''));

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final c = items[i];
        final dept = c['dept'] ?? '';
        final section = c['section'] ?? '';
        final semId = c['semester'] ?? '';
        final subject = c['subject'] ?? '';
        final sem = SemRef(dept, section, semId);

        const chipStyle = TextStyle(
            color: kLabelBlue, fontSize: 11, fontWeight: FontWeight.w700);
        Widget chip(Widget child) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: kAccent2.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kAccentLine.withValues(alpha: 0.7)),
              ),
              child: child,
            );

        // Long-press a card to leave the subject (the arrow opens it).
        return GestureDetector(
          onLongPress: () => unclaimSubject(context, sem, subject),
          child: AppCard(
            onTap: () => _open(context, sem, subject),
            child: Row(
              children: [
                const IconBadge(icon: Icons.menu_book_outlined),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subject.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: kNameStyle.copyWith(
                              fontSize: 14.5, letterSpacing: 0.3)),
                      const SizedBox(height: 2),
                      Text(dept,
                          style: const TextStyle(
                              color: kMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          chip(Text('Section $section', style: chipStyle)),
                          chip(SemLabelText(sem: sem, style: chipStyle)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: kMuted, size: 20),
                  tooltip: 'Leave this subject',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unclaimSubject(context, sem, subject),
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0x1AFFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kGlassBorder),
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: kMuted, size: 20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Header card (avatar, welcome, claim and logout).
  Widget _page(BuildContext context, int count, Widget list) {
    final name = AppSession.teacherName.toString();
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final initials =
        parts.isEmpty ? '?' : parts.take(2).map((p) => p[0].toUpperCase()).join();
    Widget squareButton(IconData icon, String tip, VoidCallback onTap,
        {bool filled = false}) {
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: filled
                  ? const LinearGradient(colors: [kAccent, kAccent2])
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: filled ? null : Border.all(color: kAccentLine),
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kGlass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kGlassBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [kAccent, kAccent2]),
                      ),
                      child: Text(initials,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Welcome back',
                              style: TextStyle(color: kMuted, fontSize: 12.5)),
                          Text(name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    squareButton(
                      Icons.add_rounded,
                      'Claim Subject',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const DepartmentsScreen(claimMode: true)),
                      ),
                      filled: true,
                    ),
                    const SizedBox(width: 8),
                    squareButton(Icons.logout, 'Logout',
                        () => confirmAndLogout(context)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
            child: Row(
              children: [
                const Text('MY CLASSES',
                    style: TextStyle(
                        color: kLabelBlue,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4)),
                const Spacer(),
                Text('$count ${count == 1 ? 'class' : 'classes'}',
                    style: const TextStyle(
                        color: kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: liveQuery(teacherClaimsRef(AppSession.teacherId)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final snap = snapshot.data;
          final items = <Map<String, String>>[
            for (final d
                in snap?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              {
                'dept': (d.data()['dept'] ?? '').toString(),
                'section': (d.data()['section'] ?? '').toString(),
                'semester': (d.data()['semester'] ?? '').toString(),
                'subject': (d.data()['subject'] ?? '').toString(),
              }
          ];
          // Nothing in the Firestore cache? Use the SQLite copy of the claims.
          if (items.isEmpty && (snap == null || snap.metadata.isFromCache)) {
            return FutureBuilder<List<Map<String, String>>>(
              future: LocalDb.claimsOf(AppSession.teacherId),
              builder: (context, f) {
                if (!f.hasData) return const SizedBox.shrink();
                return _page(context, f.data!.length, _buildList(context, f.data!));
              },
            );
          }
          return _page(context, items.length, _buildList(context, items));
        },
      ),
    );
  }
}

// Import students (Excel .xlsx / CSV / TXT)
// Only names are needed. Rolls follow file order: first name 1, second 2, and so on.
// Used by both the admin (semester list) and the teacher (subject list).
final RegExp _importLetterRe = RegExp(r'\p{L}', unicode: true);

void _importSnack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

List<List<String>> _parseCsvText(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final firstLine = text
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  var delim = ',';
  var best = -1;
  for (final d in [',', ';', '\t']) {
    final c = d.allMatches(firstLine).length;
    if (c > best) {
      best = c;
      delim = d;
    }
  }
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == delim) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().trim());
    rows.add(row);
  }
  return rows;
}

// The cell value type differs between excel package versions, so read it as
// dynamic and convert it to text.
String _excelCellText(dynamic data) {
  try {
    final v = data?.value;
    if (v == null) return '';
    final inner = (v as dynamic).value;
    if (inner is String) return inner.trim();
    try {
      final t = (inner as dynamic).text;
      if (t is String) return t.trim();
    } catch (e) {
      debugPrint('browse_screens.dart:1869: $e');
    }
    return inner.toString().trim();
  } catch (_) {
    return '';
  }
}

// Rows that are never student names (totals, signature lines, ...).
final RegExp _importSkipRowRe = RegExp(
    r'^(total|grand total|average|signature|remarks?|present|absent)$',
    caseSensitive: false);

// Cleans a name cell: odd spaces, serial prefixes ("1.", "01)", "12 Rahul") and
// punctuation at the ends.
String _cleanImportedName(String raw) {
  var s = raw.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^\(?\d{1,6}\s*[.)\]:\-\u2013]\s*'), '');
  s = s.replaceFirst(RegExp(r'^\d{1,6}\s+(?=\p{L})', unicode: true), '');
  s = s.replaceAll(RegExp(r'^[\s,;:\-\u2013]+|[\s,;:\-\u2013]+$'), '');
  return s.trim();
}
