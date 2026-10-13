part of '../main.dart';

// Mark attendance for a subject.

// Subject attendance screen
// Admin: no limits. Teacher (master switch OFF): only today, only in the first 20
// minutes of each hour, and only new records, unless allowed in Detailed permissions
// (any time, change time, change date, edit, delete). Master switch ON: all open.
// Each subject has its own screen.
class SubjectAttendanceScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  final DateTime? initialDate;
  final int? initialSession;
  const SubjectAttendanceScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
    this.initialDate,
    this.initialSession,
  });

  @override
  State<SubjectAttendanceScreen> createState() => _SubjectAttendanceScreenState();
}

class _SubjectAttendanceScreenState extends State<SubjectAttendanceScreen> {
  late DateTime selectedDate;
  late int selectedSession;
  Map<String, String> attendanceStatus = {};
  List<Map<String, String>> students = [];
  Map<String, double> studentPercentage = {};
  bool isLoading = true;
  bool copiedFromPreviousSession = false;

  bool existingRecord = false;
  String? timeStr; // 'HH:mm'
  Map<String, String> existingMeta = {};
  String sessionType = kTypeClass; // 'class' or 'lab' for the selected session

  // All records of this subject, loaded once and reused for the selected date,
  // copying the previous session and the percentages.
  List<DateRecord> _records = [];

  TeacherPerms perms = TeacherPerms.none;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permSub;
  Timer? _ticker;
  bool _lastWindowState = true;

  CollectionReference<Map<String, dynamic>> get _datesRef =>
      widget.sem.dates(widget.subjectName);

  bool get _isAdmin => AppSession.isAdmin;
  // Full access: admin, or a teacher while the master switch is ON.
  bool get _unrestricted => _isAdmin || perms.master;
  bool get _canChangeTime => _unrestricted || perms.changeTime;
  bool get _canChangeDate => _unrestricted || perms.changeDate;
  bool get _canEditExisting => _unrestricted || perms.edit;
  bool get _canDeleteRec => _unrestricted || perms.delete;
  bool get _canChangeType => _unrestricted || perms.changeType;
  bool get _isToday {
    final n = DateTime.now();
    return selectedDate.year == n.year &&
        selectedDate.month == n.month &&
        selectedDate.day == n.day;
  }

  bool get _inWindow => DateTime.now().minute < kMarkWindowMinutes;
  bool get _canEdit {
    if (_unrestricted) return true;
    if (existingRecord) return perms.edit;
    return (_isToday || perms.changeDate) && (_inWindow || perms.anytime);
  }

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate ?? DateTime.now();
    selectedSession = widget.initialSession ?? 1;

    _permSub = permissionsRef().snapshots().listen((s) {
      final p = TeacherPerms.from(s.data());
      if (mounted && p != perms) setState(() => perms = p);
    }, onError: (_) {});

    // Update the screen when the window opens or closes
    _lastWindowState = _inWindow;
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _isAdmin) return;
      final now = _inWindow;
      if (now != _lastWindowState) {
        _lastWindowState = now;
        setState(() {});
      }
    });

    _loadAll();
  }

  @override
  void dispose() {
    _permSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _getDocumentId([int? session]) {
    String dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    return "${dateStr}_Session_${session ?? selectedSession}";
  }

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    try {
      final studentsF = loadSubjectStudents(widget.sem, widget.subjectName);
      final recordsF = loadDateRecords(widget.sem, widget.subjectName);
      students = await studentsF;
      _records = await recordsF;
      _fetchAttendanceForDate();
      _computePercentages();
    } catch (e) {
      debugPrint('Attendance load error: $e');
    }
    // Always stop the spinner, even if something above failed.
    if (mounted) setState(() => isLoading = false);

    if (copiedFromPreviousSession && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSnack(context,
            'Attendance copied from the previous session. Change if needed and tap Save.');
      });
    }
  }

  DateRecord? _recordById(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  // Uses the already loaded records: instant, no network.
  void _fetchAttendanceForDate() {
    copiedFromPreviousSession = false;
    existingRecord = false;
    existingMeta = {};
    timeStr = null;

    final cur = _recordById(_getDocumentId());
    if (cur != null) {
      attendanceStatus = Map<String, String>.from(cur.status);
      existingRecord = true;
      existingMeta = Map<String, String>.from(cur.meta);
      timeStr = cur.meta['_time'];
      sessionType = cur.isLab ? kTypeLab : kTypeClass;
      return;
    }

    timeStr = hhmm(TimeOfDay.now());

    for (int s = selectedSession - 1; s >= 1; s--) {
      final prev = _recordById(_getDocumentId(s));
      if (prev != null) {
        attendanceStatus = Map<String, String>.from(prev.status);
        copiedFromPreviousSession = true;
        // A new session usually has the same type as the one before it.
        sessionType = prev.isLab ? kTypeLab : kTypeClass;
        return;
      }
    }

    attendanceStatus = {for (var s in students) s['roll']!: "P"};
  }

  void _computePercentages() {
    final total = _records.length;
    final counts = <String, int>{};
    for (final r in _records) {
      r.status.forEach((roll, st) {
        if (st == 'P') counts[roll] = (counts[roll] ?? 0) + 1;
      });
    }
    final Map<String, double> result = {};
    for (final s in students) {
      final roll = s['roll']!;
      result[roll] = total > 0 ? ((counts[roll] ?? 0) / total) * 100 : 100.0;
    }
    studentPercentage = result;
  }

  Future<void> _afterDateOrSessionChange() async {
    _fetchAttendanceForDate();
    if (mounted) setState(() {});
    if (copiedFromPreviousSession && mounted) {
      showSnack(context, 'Attendance copied from the previous session.');
    }
  }

  void _openMonthly() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonthlyAttendanceScreen(
          sem: widget.sem,
          semLabel: widget.semLabel,
          subjectName: widget.subjectName,
        ),
      ),
    );
  }

  void _saveAttendance() async {
    // Check the rules again when saving (the window may have closed meanwhile)
    if (!_canEdit) {
      showSnack(
          context,
          existingRecord
              ? 'You do not have permission to edit this record. Ask the admin.'
              : (!_isToday && !perms.changeDate)
                  ? 'You can only mark attendance for today.'
                  : 'Attendance can only be marked within the first $kMarkWindowMinutes minutes of each hour.',
          color: kAbsent);
      return;
    }

    final docId = _getDocumentId();

    final data = <String, dynamic>{
      for (final s in students) s['roll']!: attendanceStatus[s['roll']!] ?? 'P',
    };

    // Time: an admin (or a teacher allowed to change time, or master switch ON) picks it.
    // Otherwise a new record gets the current time and an edited one keeps its old time.
    String? time = _canChangeTime
        ? timeStr
        : (existingRecord ? timeStr : hhmm(TimeOfDay.now()));
    if (time == null && !existingRecord) time = hhmm(TimeOfDay.now());
    if (time != null) data['_time'] = time;

    // Who marked it: if an admin edits a teacher's record, the teacher's name stays.
    String byId = AppSession.userId;
    String byName = AppSession.userName;
    if (_isAdmin && (existingMeta['_marked_by'] ?? '').isNotEmpty) {
      byId = existingMeta['_marked_by']!;
      byName = existingMeta['_marked_by_name'] ?? byName;
    }
    data['_marked_by'] = byId;
    data['_marked_by_name'] = byName;
    data['_type'] = sessionType; // Class or Lab Class

    final status = <String, String>{
      for (final s in students) s['roll']!: attendanceStatus[s['roll']!] ?? 'P',
    };

    // Not awaited: this never completes while offline.
    unawaited(_datesRef.doc(docId).set(data).catchError((_) {}));
    unawaited(LocalDb.saveAttendance(
      widget.sem,
      widget.subjectName,
      docId,
      status,
      time: time,
      markedBy: byId,
      markedByName: byName,
      sessionType: sessionType,
    ));

    final newMeta = <String, String>{
      '_time': ?time,
      '_marked_by': byId,
      '_marked_by_name': byName,
      '_type': sessionType,
    };
    final rec = DateRecord(docId, Map<String, String>.from(status),
        Map<String, String>.from(newMeta));

    setState(() {
      final idx = _records.indexWhere((r) => r.id == docId);
      if (idx >= 0) {
        _records[idx] = rec;
      } else {
        _records.add(rec);
        _records.sort((a, b) => a.id.compareTo(b.id));
      }
      existingRecord = true;
      timeStr = time;
      existingMeta = newMeta;
      _computePercentages();
    });

    if (mounted) {
      showSnack(context,
          'Attendance Saved/Updated for Session $selectedSession (${typeLabel(sessionType)})!');
    }
  }

  void _deleteAttendance() async {
    if (!_canDeleteRec) return;
    final docId = _getDocumentId();
    unawaited(_datesRef.doc(docId).delete().catchError((_) {}));
    unawaited(LocalDb.deleteAttendance(widget.sem, widget.subjectName, docId));

    setState(() {
      _records.removeWhere((r) => r.id == docId);
      attendanceStatus = {for (var s in students) s['roll']!: "P"};
      existingRecord = false;
      existingMeta = {};
      timeStr = hhmm(TimeOfDay.now());
      _computePercentages();
    });

    if (mounted) {
      showSnack(context, 'Attendance record for Session $selectedSession deleted!',
          color: kAbsent);
    }
  }

  // ---- Import old attendance from Excel / CSV ----
  // For admin and teacher. This is old-date data, so the time window and "today only"
  // rules don't apply. Changing an existing session needs admin (or master switch ON).
  Future<void> _importFromFile() async {
    if (students.isEmpty) {
      showSnack(context, 'Add students to this subject first.', color: kAbsent);
      return;
    }
    final sheet = await pickAttendanceSheetFromFile(context);
    if (sheet == null || !mounted) return;

    final plan = await Navigator.push<ImportPlan>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportReviewScreen(
          sheet: sheet,
          students: students,
          existingIds: _records.map((r) => r.id).toSet(),
          canOverwrite: _canEditExisting,
        ),
      ),
    );
    if (plan == null || !mounted) return;
    await _applyImport(sheet, plan);
  }

  Future<void> _applyImport(ImportSheet sheet, ImportPlan plan) async {
    final fallback = plan.blankPresent ? 'P' : 'A';
    var imported = 0;
    var skipped = 0;

    for (final col in sheet.columns) {
      if (!plan.cols.contains(col.col)) continue;
      final docId = col.docId;
      final old = _recordById(docId);
      if (old != null && !_canEditExisting) {
        skipped++;
        continue;
      }

      final status = <String, String>{
        for (final s in students) s['roll']!: fallback,
      };
      plan.rowToStudent.forEach((rowIdx, key) {
        final st = sheet.rows[rowIdx].status[col.col];
        if (st != null && status.containsKey(key)) status[key] = st;
      });

      final time = old?.meta['_time'];
      final byId = AppSession.userId;
      final byName = AppSession.userName;
      // Lab label in the file wins; otherwise keep the old type (new = Class).
      final type = col.isLab ? kTypeLab : ((old?.isLab ?? false) ? kTypeLab : kTypeClass);
      final data = <String, dynamic>{
        ...status,
        '_time': ?time,
        '_marked_by': byId,
        '_marked_by_name': byName,
        '_type': type,
      };

      // Not awaited: this never completes while offline.
      unawaited(_datesRef.doc(docId).set(data).catchError((_) {}));
      await LocalDb.saveAttendance(
        widget.sem,
        widget.subjectName,
        docId,
        status,
        time: time,
        markedBy: byId,
        markedByName: byName,
        sessionType: type,
      );

      final newMeta = <String, String>{
        '_time': ?time,
        '_marked_by': byId,
        '_marked_by_name': byName,
        '_type': type,
      };
      final rec = DateRecord(docId, Map<String, String>.from(status), newMeta);
      final idx = _records.indexWhere((r) => r.id == docId);
      if (idx >= 0) {
        _records[idx] = rec;
      } else {
        _records.add(rec);
      }
      imported++;
    }

    _records.sort((a, b) => a.id.compareTo(b.id));
    _fetchAttendanceForDate();
    _computePercentages();
    if (!mounted) return;
    setState(() {});
    showSnack(
      context,
      imported == 0
          ? 'Nothing was imported.'
          : 'Imported $imported date${imported == 1 ? '' : 's'}.'
              '${skipped > 0 ? ' $skipped skipped (already taken, admin only).' : ''}',
      color: imported == 0 ? kAbsent : kPresent,
    );
  }

  void _exportToExcel() async {
    final recs = await loadDateRecords(widget.sem, widget.subjectName);
    if (!mounted) return;
    final opt = await askExportOptions(context, recs);
    if (opt == null || !mounted) return;
    final picked = filterRecordsByScope(recs, opt.scope);
    if (picked.isEmpty) {
      showSnack(context, 'No ${scopeLabel(opt.scope)} sessions to export.',
          color: kAbsent);
      return;
    }
    final fileBytes = buildAttendanceExcelBytes(
      info: await loadExcelInfo(widget.sem, widget.subjectName),
      recs: picked,
      students: students,
      useLetters: opt.useLetters,
    );
    // File name: Subject_Section_A_Semester_3_[Class_|Lab_]Full_Report.xlsx
    final base = exportFileBase(widget.sem, widget.semLabel, widget.subjectName);
    final fileName = '${base}_${scopeFileTag(opt.scope)}Full_Report.xlsx';
    if (kIsWeb) {
      downloadBytes(fileBytes!, fileName);
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    String filePath = '${directory.path}/$fileName';

    File(filePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes!);

    await SharePlus.instance.share(ShareParams(
      files: [XFile(filePath)],
      text:
          '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} Attendance Report',
    ));
  }

  // Class / Lab Class button (same look as the Mark all buttons).
  Widget _typeButton(String label, String type, bool enabled) {
    final selected = sessionType == type;
    return OutlinedButton(
      onPressed: enabled ? () => setState(() => sessionType = type) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? kOnAccent : kAccent,
        backgroundColor: selected ? kAccent : null,
        disabledForegroundColor: selected ? kOnAccent : kMuted,
        disabledBackgroundColor:
            selected ? kAccent.withValues(alpha: 0.45) : null,
        side: BorderSide(color: enabled ? kAccent : kOutline),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label),
    );
  }

  Widget _restrictionBanner() {
    if (_unrestricted) return const SizedBox.shrink();
    if (existingRecord) {
      if (perms.edit) return const SizedBox.shrink();
      return const InfoBanner(
        text: 'Attendance for this session has already been taken. You do not have permission to edit it. Ask the admin.',
        icon: Icons.lock_outline,
      );
    }
    if (!_isToday && !perms.changeDate) {
      return const InfoBanner(
        text: 'Aap sirf aaj ki date ki attendance le sakte hain.',
        icon: Icons.lock_outline,
      );
    }
    if (perms.anytime) return const SizedBox.shrink();
    if (!_inWindow) {
      return InfoBanner(
        text:
            'Attendance can only be taken within the first $kMarkWindowMinutes minutes of each hour (e.g. 10:00-10:$kMarkWindowMinutes). The next window opens at ${DateFormat('hh:00 a').format(DateTime.now().add(const Duration(hours: 1)))}.',
        icon: Icons.schedule,
      );
    }
    final left = kMarkWindowMinutes - DateTime.now().minute;
    return InfoBanner(
      text: 'Attendance window is open — $left minutes remaining.',
      icon: Icons.timer_outlined,
      color: kPresent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;

    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 6),
                          itemCount: (students.isEmpty ? 1 : students.length) + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                        top: MediaQuery.of(context).padding.top),
                                    child: HeaderCard(
          title: widget.subjectName,
          subtitle:
              '${widget.sem.deptId} • Section ${widget.sem.section} • ${widget.semLabel}',
          tabs: [
            HeaderAction(
              icon: Icons.groups_outlined,
              label: 'Students',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubjectStudentsScreen(
                        sem: widget.sem, subjectName: widget.subjectName),
                  ),
                ).then((_) => _loadAll());
              },
            ),
            HeaderAction(
              icon: Icons.bar_chart_rounded,
              label: 'Stats',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubjectStatsScreen(
                        sem: widget.sem, subjectName: widget.subjectName),
                  ),
                );
              },
            ),
            if (_canEditExisting || _canDeleteRec || _canChangeType)
              HeaderAction(
                icon: Icons.edit_calendar_outlined,
                label: 'Records',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManageAttendanceScreen(
                        sem: widget.sem,
                        semLabel: widget.semLabel,
                        subjectName: widget.subjectName,
                      ),
                    ),
                  );
                },
              ),
            HeaderAction(
              icon: Icons.upload_file_outlined,
              label: 'Import',
              onTap: _importFromFile,
            ),
            HeaderAction(
              icon: Icons.file_download_outlined,
              label: 'Export',
              onTap: _exportToExcel,
            ),
          ],
        ),
                                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openMonthly,
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: const Text('Monthly attendance'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAccent,
                        side: const BorderSide(color: kOutline),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                _restrictionBanner(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Date: ${DateFormat('dd MMM yyyy').format(selectedDate)}",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          if (_canChangeDate)
                            ElevatedButton.icon(
                              onPressed: () async {
                                DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  selectedDate = picked;
                                  await _afterDateOrSessionChange();
                                }
                              },
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: const Text('Change Date'),
                            ),
                        ],
                      ),
                      if (_canChangeTime) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Time: ${timeStr == null ? '—' : fmtHhmm(timeStr)}",
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked =
                                    await pickClassTime(context, parseHhmm(timeStr));
                                if (picked != null) {
                                  setState(() => timeStr = hhmm(picked));
                                }
                              },
                              icon: const Icon(Icons.access_time, size: 16),
                              label: const Text('Change Time'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Lecture / Session:",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          DropdownButton<int>(
                            value: selectedSession,
                            items: List.generate(5, (index) => index + 1)
                                .map((val) => DropdownMenuItem(
                                      value: val,
                                      child: Text("Session $val"),
                                    ))
                                .toList(),
                            onChanged: (newVal) async {
                              if (newVal != null) {
                                selectedSession = newVal;
                                await _afterDateOrSessionChange();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: kOutline),
                if (students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 52,
                          child: Text('Type:',
                              style: TextStyle(color: kMuted, fontSize: 13)),
                        ),
                        const SizedBox(width: 10),
                        _typeButton('Class', kTypeClass, canEdit),
                        const SizedBox(width: 8),
                        _typeButton('Lab Class', kTypeLab, canEdit),
                      ],
                    ),
                  ),
                if (students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        const Text('Mark all:',
                            style: TextStyle(color: kMuted, fontSize: 13)),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: canEdit
                              ? () => setState(() {
                                    for (final st in students) {
                                      attendanceStatus[st['roll']!] = 'A';
                                    }
                                  })
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kAbsent,
                            side: BorderSide(
                                color: canEdit ? kAbsent : kOutline),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('All Absent'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: canEdit
                              ? () => setState(() {
                                    for (final st in students) {
                                      attendanceStatus[st['roll']!] = 'P';
                                    }
                                  })
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kPresent,
                            side: BorderSide(
                                color: canEdit ? kPresent : kOutline),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('All Present'),
                        ),
                      ],
                    ),
                  ),
                                ],
                              );
                            }
                            if (students.isEmpty) {
                              return const SizedBox(
                                height: 260,
                                child: EmptyState(
                                  icon: Icons.groups_outlined,
                                  text: 'There are no students in this subject yet.\nAdmin can add them from Manage Students.',
                                ),
                              );
                            }
                            var student = students[index - 1];
                            String roll = student['roll']!;
                            double? pct = studentPercentage[roll];
                            bool isLow = pct != null && pct < 75;

                            return RepaintBoundary(
                                child: AppCard(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                              child: Row(
                                children: [
                                  RollBadge(roll: roll),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          student['name']!,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: isLow ? kAbsent : null,
                                          ),
                                        ),
                                        if (pct != null)
                                          Text('${pct.toStringAsFixed(1)}% attendance',
                                              style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: isLow ? kAbsent : kMuted)),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AttendanceChip(
                                        label: 'P',
                                        selected:
                                            (attendanceStatus[roll] ?? 'P') ==
                                                'P',
                                        color: kPresent,
                                        onTap: canEdit
                                            ? () => setState(() =>
                                                attendanceStatus[roll] = 'P')
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      AttendanceChip(
                                        label: 'A',
                                        selected:
                                            (attendanceStatus[roll] ?? 'P') ==
                                                'A',
                                        color: kAbsent,
                                        onTap: canEdit
                                            ? () => setState(() =>
                                                attendanceStatus[roll] = 'A')
                                            : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ));
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      if (_canDeleteRec) ...[
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAbsent,
                                foregroundColor: kOnAccent,
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Attendance?'),
                                    content: Text('Are you sure you want to delete the attendance for Session $selectedSession?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteAttendance();
                                        },
                                        child: const Text('Delete', style: TextStyle(color: kAbsent)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: const Icon(Icons.delete),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: canEdit ? _saveAttendance : null,
                            child: Text(
                              existingRecord ? 'Save / Update' : 'Save Attendance',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
    );
  }
}
