part of 'main.dart';

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
  String examPhase = kPhaseMid; // current Mid / Final phase of this subject
  String sessionPhase = kPhaseMid; // phase the selected session is saved with
  bool _phaseChangedLocally = false;
  // What the admin has announced (null = nothing announced yet). A teacher whose
  // subject is in the other phase must switch before taking new attendance.
  String? announcedPhase;
  bool _announceFromServer = false;

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
  // Edit permission also allows deleting.
  bool get _canDeleteRec => _unrestricted || perms.edit;
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
    setAppBusy(true); // web: do not auto-reload for an update while marking

    _permSub = permissionsRef().snapshots().listen((s) {
      final data = s.data();
      final p = TeacherPerms.from(data);
      // Trust the announcement when the field is there, or when the server
      // says it was never set. An empty offline cache must not reset it.
      String? a;
      var known = false;
      if (data != null && data.containsKey(kAnnouncedPhaseField)) {
        a = announcedPhaseFrom(data);
        known = true;
      } else if (!s.metadata.isFromCache) {
        a = null; // server says: nothing announced
        known = true;
      }
      if (known) {
        _announceFromServer = true;
        if (a != announcedPhase) unawaited(cacheAnnouncedPhase(a));
      }
      if (mounted && (p != perms || (known && a != announcedPhase))) {
        setState(() {
          perms = p;
          if (known) announcedPhase = a;
        });
      }
    }, onError: (_) {});

    // Last known announcement, so the reminder also works offline / on restart.
    unawaited(readLocalAnnouncedPhase().then((v) {
      if (!mounted || _announceFromServer || v == announcedPhase) return;
      setState(() => announcedPhase = v);
    }));

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
    setAppBusy(false);
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
      examPhase = await readLocalSubjectPhase(widget.sem, widget.subjectName);
      _fetchAttendanceForDate();
      _computePercentages();
    } catch (e) {
      debugPrint('Attendance load error: $e');
    }
    // Always stop the spinner, even if something above failed.
    if (mounted) setState(() => isLoading = false);
    unawaited(_syncPhaseFromServer());

    if (copiedFromPreviousSession && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSnack(context,
            'Attendance copied from the previous session. Change if needed and tap Save.');
      });
    }
  }

  // Picks up a phase change made on another device (offline keeps the local value).
  Future<void> _syncPhaseFromServer() async {
    final v = await fetchServerSubjectPhase(widget.sem, widget.subjectName);
    if (v == null || !mounted || _phaseChangedLocally || v == examPhase) return;
    await cacheSubjectPhase(widget.sem, widget.subjectName, v);
    if (!mounted) return;
    setState(() {
      examPhase = v;
      if (!existingRecord) sessionPhase = v;
      _computePercentages();
    });
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
    sessionPhase = examPhase; // new sessions use the subject's current phase

    final cur = _recordById(_getDocumentId());
    if (cur != null) {
      attendanceStatus = Map<String, String>.from(cur.status);
      existingRecord = true;
      existingMeta = Map<String, String>.from(cur.meta);
      timeStr = cur.meta['_time'];
      sessionType = cur.isLab ? kTypeLab : kTypeClass;
      // An existing session keeps its own stored phase.
      sessionPhase = cur.isFinal ? kPhaseFinal : kPhaseMid;
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
    // Only sessions of the selected exam phase (Mid / Final) are counted.
    final recs = _records
        .where((r) => examPhase == kPhaseFinal ? r.isFinal : r.isMid)
        .toList();
    final total = recs.length;
    final counts = <String, int>{};
    for (final r in recs) {
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

  // Opens the full attendance sheet inside the app (works offline).
  void _viewSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceSheetScreen(
          sem: widget.sem,
          semLabel: widget.semLabel,
          subjectName: widget.subjectName,
        ),
      ),
    );
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

    if (!_guardPhase()) return;

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
    data['_phase'] = sessionPhase; // Mid or Final

    final status = <String, String>{
      for (final s in students) s['roll']!: attendanceStatus[s['roll']!] ?? 'P',
    };

    // Not awaited: this never completes while offline.
    unawaited(_datesRef.doc(docId).set(stamped(data)).catchError((_) {}));
    unawaited(LocalDb.saveAttendance(
      widget.sem,
      widget.subjectName,
      docId,
      status,
      time: time,
      markedBy: byId,
      markedByName: byName,
      sessionType: sessionType,
      phase: sessionPhase,
    ));

    final newMeta = <String, String>{
      '_time': ?time,
      '_marked_by': byId,
      '_marked_by_name': byName,
      '_type': sessionType,
      '_phase': sessionPhase,
    };
    final rec = DateRecord(docId, Map<String, String>.from(status),
        Map<String, String>.from(newMeta));

    // Edit of a saved session: only students whose mark changed need a new summary.
    // A new session (or a Class/Lab change) changes everyone, so write all.
    final oldIdx = _records.indexWhere((r) => r.id == docId);
    List<String> summaryRolls = [for (final s in students) s['roll'] ?? ''];
    if (oldIdx >= 0 && _records[oldIdx].isLab == (sessionType == kTypeLab)) {
      final old = _records[oldIdx];
      summaryRolls = [
        for (final s in students)
          if (old.status[s['roll']] != status[s['roll']]) s['roll'] ?? ''
      ];
    }

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
    if (summaryRolls.isNotEmpty) {
      unawaited(pushAttendanceSummaries(
          widget.sem, widget.subjectName, _records, summaryRolls));
    }

    if (mounted) {
      showSnack(context,
          'Attendance Saved/Updated for Session $selectedSession (${typeLabel(sessionType)}, ${phaseLabel(sessionPhase)})!');
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
    unawaited(pushAttendanceSummaries(widget.sem, widget.subjectName, _records,
        students.map((s) => s['roll'] ?? '')));

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
      // New sessions get the subject's current phase; old ones keep theirs.
      final phase =
          old != null ? (old.isFinal ? kPhaseFinal : kPhaseMid) : examPhase;
      final data = <String, dynamic>{
        ...status,
        '_time': ?time,
        '_marked_by': byId,
        '_marked_by_name': byName,
        '_type': type,
        '_phase': phase,
      };

      // Not awaited: this never completes while offline.
      unawaited(_datesRef.doc(docId).set(stamped(data)).catchError((_) {}));
      await LocalDb.saveAttendance(
        widget.sem,
        widget.subjectName,
        docId,
        status,
        time: time,
        markedBy: byId,
        markedByName: byName,
        sessionType: type,
        phase: phase,
      );

      final newMeta = <String, String>{
        '_time': ?time,
        '_marked_by': byId,
        '_marked_by_name': byName,
        '_type': type,
        '_phase': phase,
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
    if (imported > 0) {
      unawaited(pushAttendanceSummaries(widget.sem, widget.subjectName,
          _records, students.map((s) => s['roll'] ?? '')));
    }
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
    final picked = filterRecordsByScope(recs, opt.scope, phase: opt.phase);
    if (picked.isEmpty) {
      showSnack(context, 'No ${optionsLabel(opt)} sessions to export.',
          color: kAbsent);
      return;
    }
    final fileBytes = buildAttendanceExcelBytes(
      info: await loadExcelInfo(widget.sem, widget.subjectName),
      recs: picked,
      students: students,
      useLetters: opt.useLetters,
    );
    // File name: Subject_Section_A_Semester_3_[Mid_|Final_][Class_|Lab_]Full_Report.xlsx
    final base = exportFileBase(widget.sem, widget.semLabel, widget.subjectName);
    final fileName =
        '${base}_${phaseFileTag(opt.phase)}${scopeFileTag(opt.scope)}Full_Report.xlsx';
    if (!mounted) return;
    if (kIsWeb) {
      await webShareOrDownload(context, fileBytes!, fileName,
          text:
              '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} Attendance Report');
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
    return GradPill(
      label: label,
      filled: selected,
      enabled: enabled,
      onTap: enabled ? () => setState(() => sessionType = type) : null,
    );
  }

  // Mid / Final button (same look as the Class / Lab buttons).
  Widget _phaseButton(String label, String phase, bool enabled) {
    final selected = examPhase == phase;
    return GradPill(
      label: label,
      filled: selected,
      enabled: enabled,
      onTap: (enabled && !selected) ? () => _confirmSwitchPhase(phase) : null,
    );
  }

  // Asks before switching the subject between Mid and Final (both directions).
  Future<void> _confirmSwitchPhase(String newPhase) async {
    final name = phaseLabel(newPhase);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Switch to $name?'),
        content: Text(
            'New attendance for this subject will be saved as $name. Old attendance is not changed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _phaseChangedLocally = true;
    setState(() {
      examPhase = newPhase;
      if (!existingRecord) sessionPhase = newPhase;
      _computePercentages();
    });
    await saveSubjectPhase(widget.sem, widget.subjectName, newPhase);
    if (mounted) showSnack(context, 'Subject is now in $name phase.');
  }

  // Teachers only: the phase the admin announced, when this subject is still in
  // the other phase (null = nothing to do). Shows every time the subject is opened
  // until the teacher switches it (or the admin announces the other phase again).
  String? get _pendingSwitch {
    final a = announcedPhase;
    if (_isAdmin || a == null || a == examPhase) return null;
    return a;
  }

  // Stops NEW attendance (Present / Absent / Mark all / Save) while a phase switch
  // is pending, and shows the reminder again with a Switch button.
  // Returns true when marking may go on.
  bool _guardPhase() {
    final target = _pendingSwitch;
    if (target == null || existingRecord) return true;
    final name = phaseLabel(target);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Switch to $name first'),
        content: Text(
            'The admin has announced the $name phase. Please switch this subject to $name before taking attendance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmSwitchPhase(target);
            },
            child: Text('Switch to $name'),
          ),
        ],
      ),
    );
    return false;
  }

  Widget _finalReminderBanner() {
    final target = _pendingSwitch;
    if (target == null) return const SizedBox.shrink();
    final toFinal = target == kPhaseFinal;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kViolet.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kViolet.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.campaign_outlined, color: kViolet, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  toFinal
                      ? 'The Mid phase has ended and the Final phase has started. '
                          'Please switch this subject from Mid to Final. '
                          'You cannot take attendance until you do.'
                      : 'The Final phase has ended and the Mid phase has started. '
                          'Please switch this subject from Final to Mid. '
                          'You cannot take attendance until you do.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GradPill(
              label: toFinal ? 'Switch to Final' : 'Switch to Mid',
              icon: toFinal ? Icons.emoji_events_outlined : Icons.flag_outlined,
              height: 36,
              enabled: _canEdit,
              onTap: _canEdit ? () => _confirmSwitchPhase(target) : null,
            ),
          ),
        ],
      ),
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
              icon: Icons.table_chart_outlined,
              label: 'View',
              onTap: _viewSheet,
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
                    child: GradPill(
                      onTap: _openMonthly,
                      icon: Icons.calendar_month_outlined,
                      label: 'Monthly attendance',
                      filled: false,
                      expand: true,
                      height: 46,
                      radius: 14,
                    ),
                  ),
                ),
                _finalReminderBanner(),
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
                            style: kLabelStyle.copyWith(fontSize: 16),
                          ),
                          if (_canChangeDate)
                            GradPill(
                              onTap: () async {
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
                              icon: Icons.calendar_today,
                              label: 'Change Date',
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
                              style: kLabelStyle.copyWith(fontSize: 16),
                            ),
                            GradPill(
                              onTap: () async {
                                final picked =
                                    await pickClassTime(context, parseHhmm(timeStr));
                                if (picked != null) {
                                  setState(() => timeStr = hhmm(picked));
                                }
                              },
                              icon: Icons.access_time,
                              label: 'Change Time',
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Lecture / Session:",
                            style: kLabelStyle.copyWith(fontSize: 15),
                          ),
                          DropdownButton<int>(
                            value: selectedSession,
                            style: kLabelStyle.copyWith(fontSize: 16),
                            iconEnabledColor: kAccent,
                            dropdownColor: kSurface,
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
                          child: Text('Exam:',
                              style: kLabelStyle),
                        ),
                        const SizedBox(width: 10),
                        _phaseButton('Mid', kPhaseMid, canEdit),
                        const SizedBox(width: 8),
                        _phaseButton('Final', kPhaseFinal, canEdit),
                      ],
                    ),
                  ),
                if (students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 52,
                          child: Text('Type:',
                              style: kLabelStyle),
                        ),
                        const SizedBox(width: 10),
                        _typeButton('Class', kTypeClass, canEdit),
                        const SizedBox(width: 8),
                        _typeButton('Lab Class', kTypeLab, canEdit),
                      ],
                    ),
                  ),
                if (students.isNotEmpty)
                  Builder(builder: (context) {
                    var absentCount = 0;
                    for (final st in students) {
                      if ((attendanceStatus[st['roll']!] ?? 'P') == 'A') {
                        absentCount++;
                      }
                    }
                    final presentCount = students.length - absentCount;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
                      child: Row(
                        children: [
                          Text('Present $presentCount',
                              style: const TextStyle(
                                  color: kAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 14),
                          Text('Absent $absentCount',
                              style: const TextStyle(
                                  color: kAbsent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 14),
                          Text('Total ${students.length}',
                              style: const TextStyle(
                                  color: kMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
                if (students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        const Text('Mark all:',
                            style: kLabelStyle),
                        const SizedBox(width: 10),
                        GradPill(
                          label: 'All Present',
                          enabled: canEdit,
                          onTap: canEdit
                              ? () {
                                  if (!_guardPhase()) return;
                                  setState(() {
                                    for (final st in students) {
                                      attendanceStatus[st['roll']!] = 'P';
                                    }
                                  });
                                }
                              : null,
                        ),
                        const SizedBox(width: 8),
                        GradPill(
                          label: 'All Absent',
                          gradient: kRedGrad,
                          enabled: canEdit,
                          onTap: canEdit
                              ? () {
                                  if (!_guardPhase()) return;
                                  setState(() {
                                    for (final st in students) {
                                      attendanceStatus[st['roll']!] = 'A';
                                    }
                                  });
                                }
                              : null,
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
 float: false,
                              subtle: true,
                              borderColor: isLow ? kAbsent : null,
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                              child: Row(
                                children: [
                                  RollBadge(roll: roll),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        StudentNameBlock(
                                          name: student['name']!,
                                          father: student['father'] ?? '',
                                          color: isLow ? kAbsent : null,
                                          extra: pct == null
                                              ? null
                                              : '${pct.toStringAsFixed(1)}% attendance',
                                          extraColor: isLow ? kAbsent : kMuted,
                                        ),
                                        if (pct != null) ...[
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: (pct / 100).clamp(0.0, 1.0),
                                              minHeight: 4,
                                              backgroundColor:
                                                  const Color(0xFF22308A),
                                              color: isLow ? kAbsent : kAccent,
                                            ),
                                          ),
                                        ],
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
                                            ? () {
                                                if (!_guardPhase()) return;
                                                setState(() =>
                                                    attendanceStatus[roll] = 'P');
                                              }
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
                                            ? () {
                                                if (!_guardPhase()) return;
                                                setState(() =>
                                                    attendanceStatus[roll] = 'A');
                                              }
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
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAbsent,
                                foregroundColor: const Color(0xFF2A0A12),
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
                        child: Opacity(
                          opacity: canEdit ? 1 : 0.5,
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [kAccent, kAccent2]),
                              borderRadius: BorderRadius.circular(27),
                              boxShadow: [
                                BoxShadow(
                                  color: kAccent2.withValues(alpha: 0.40),
                                  blurRadius: 14,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: canEdit ? _saveAttendance : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white,
                              ),
                              child: Text(
                                existingRecord ? 'Save / Update' : 'Save Attendance',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
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

// Manage attendance screen (edit / delete old records)
// Admin, or a teacher with Edit, Delete and/or Class/Lab permission (or master
// switch ON). Each button follows its own permission.
class ManageAttendanceScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  const ManageAttendanceScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
  });

  @override
  State<ManageAttendanceScreen> createState() => _ManageAttendanceScreenState();
}

// One saved session shown on the Records screen.
class _RecItem {
  final String docId;
  final String label; // "22 Oct 2026 - Session 1" (dialogs / messages)
  final DateTime? date;
  final int? session;
  final int present;
  final int absent;
  final String time;
  final String by;
  final bool isLab;
  final bool isFinal;
  const _RecItem({
    required this.docId,
    required this.label,
    required this.date,
    required this.session,
    required this.present,
    required this.absent,
    required this.time,
    required this.by,
    required this.isLab,
    required this.isFinal,
  });
}

class _ManageAttendanceScreenState extends State<ManageAttendanceScreen> {
  SemRef get sem => widget.sem;
  String get semLabel => widget.semLabel;
  String get subjectName => widget.subjectName;

  String _filter = 'all'; // all | class | lab | mid | final

  void _confirmDelete(BuildContext context, String docId, String label) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Record?'),
        content: Text('Delete the attendance record for $label? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              unawaited(sem.dates(subjectName).doc(docId).delete().catchError((_) {}));
              unawaited(LocalDb.deleteAttendance(sem, subjectName, docId));
              unawaited(refreshSubjectSummary(sem, subjectName,
                  tweak: (l) => l.removeWhere((r) => r.id == docId)));
              if (context.mounted) showSnack(context, 'Deleted record for $label');
            },
            child: const Text('Delete', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
  }

  // Moves one session between Class and Lab Class (fixes a wrong choice).
  void _confirmChangeType(
      BuildContext context, String docId, String label, String newType) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change session type?'),
        content: Text('Change $label to ${typeLabel(newType)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Not awaited: this never completes while offline.
              unawaited(sem
                  .dates(subjectName)
                  .doc(docId)
                  .update(stamped({'_type': newType})).catchError((_) {}));
              unawaited(LocalDb.setSessionType(sem, subjectName, docId, newType));
              unawaited(refreshSubjectSummary(sem, subjectName, tweak: (l) {
                final i = l.indexWhere((r) => r.id == docId);
                if (i >= 0) {
                  l[i] = DateRecord(l[i].id, l[i].status,
                      {...l[i].meta, '_type': newType});
                }
              }));
              if (context.mounted) {
                showSnack(context, '$label is now ${typeLabel(newType)}');
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  // Moves one session between Mid and Final (single toggle).
  void _confirmChangePhase(
      BuildContext context, String docId, String label, String newPhase) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change exam phase?'),
        content: Text('Change phase of $label to ${phaseLabel(newPhase)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Not awaited: this never completes while offline.
              unawaited(sem
                  .dates(subjectName)
                  .doc(docId)
                  .update(stamped({'_phase': newPhase})).catchError((_) {}));
              unawaited(LocalDb.setSessionPhase(sem, subjectName, docId, newPhase));
              if (context.mounted) {
                showSnack(context, '$label is now ${phaseLabel(newPhase)}');
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  // Marks one student Present or Absent in every saved session of this subject.
  // Returns how many sessions were changed.
  Future<int> _markStudentEverywhere(String roll, String status) async {
    final records = await loadDateRecords(sem, subjectName);
    for (final r in records) {
      // Not awaited: this never completes while offline. merge keeps the
      // other students and the session's meta fields untouched.
      unawaited(sem
          .dates(subjectName)
          .doc(r.id)
          .set(stamped({roll: status}), SetOptions(merge: true)).catchError((_) {}));
    }
    unawaited(LocalDb.setStudentStatusAll(sem, subjectName, roll, status));
    unawaited(refreshSubjectSummary(sem, subjectName, tweak: (l) {
      for (var i = 0; i < l.length; i++) {
        l[i] = DateRecord(
            l[i].id, {...l[i].status, roll: status}, Map.of(l[i].meta));
      }
    }));
    return records.length;
  }

  Widget _bulkMarkButton(String text, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }

  Future<void> _confirmBulkMark(BuildContext context, BuildContext sheetContext,
      Map<String, String> student, String status) async {
    final roll = student['roll'] ?? '';
    final name = student['name'] ?? '';
    final word = status == 'P' ? 'Present' : 'Absent';
    final ok = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mark all $word?'),
        content: Text(
            'Mark $name (Roll $roll) as $word in ALL past attendance records '
            'of $subjectName? This overwrites their existing marks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(word,
                style: TextStyle(
                    color: status == 'P' ? kPresent : kAbsent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await _markStudentEverywhere(roll, status);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    if (context.mounted) {
      showSnack(context,
          '$name marked $word in $n record${n == 1 ? '' : 's'}.');
    }
  }

  // Bottom sheet: pick a student, then tap P or A to mark them in every record.
  Future<void> _openStudentBulkSheet(BuildContext context) async {
    final students = await loadSubjectStudents(sem, subjectName);
    if (!context.mounted) return;
    if (students.isEmpty) {
      showSnack(context, 'No students found in this subject.', color: kAbsent);
      return;
    }
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final q = query.trim().toLowerCase();
          final list = q.isEmpty
              ? students
              : students
                  .where((s) =>
                      (s['name'] ?? '').toLowerCase().contains(q) ||
                      (s['roll'] ?? '').toLowerCase().contains(q))
                  .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                      child: Text(
                        'Mark a student in all past records',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Tap P (Present) or A (Absent) next to a student.',
                        style: TextStyle(color: kMuted, fontSize: 12.5),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: TextField(
                        onChanged: (v) => setSheetState(() => query = v),
                        decoration: const InputDecoration(
                          hintText: 'Search name or roll number',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(
                              child: Text('No student matches.',
                                  style: TextStyle(color: kMuted)))
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final s = list[i];
                                return ListTile(
                                  title: Text(s['name'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text('Roll: ${s['roll'] ?? ''}',
                                      style: const TextStyle(
                                          color: kMuted, fontSize: 12)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _bulkMarkButton(
                                          'P',
                                          kPresent,
                                          () => _confirmBulkMark(context,
                                              sheetContext, s, 'P')),
                                      const SizedBox(width: 8),
                                      _bulkMarkButton(
                                          'A',
                                          kAbsent,
                                          () => _confirmBulkMark(context,
                                              sheetContext, s, 'A')),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: permissionsRef().snapshots(),
      builder: (context, permSnap) {
        final perms = TeacherPerms.from(permSnap.data?.data());
        final full = AppSession.isAdmin || perms.master;
        return _buildRecords(
            context, full || perms.edit, full || perms.edit, true, true);
      },
    );
  }

  // One saved session, parsed from its Firestore document.
  _RecItem _parseRecord(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final docId = doc.id;
    DateTime? date;
    int? session;
    String label = docId;
    try {
      final parts = docId.split('_Session_');
      date = DateFormat('yyyy-MM-dd').parse(parts[0]);
      session = int.parse(parts[1]);
      label = '${DateFormat('dd MMM yyyy').format(date)} - Session $session';
    } catch (_) {
      date = null;
      session = null;
      label = docId;
    }
    final parsed = parseAttendance(doc.data());
    return _RecItem(
      docId: docId,
      label: label,
      date: date,
      session: session,
      present: parsed.status.values.where((v) => v == 'P').length,
      absent: parsed.status.values.where((v) => v == 'A').length,
      time: fmtHhmm(parsed.meta['_time']),
      by: parsed.meta['_marked_by_name'] ?? '',
      isLab: parsed.meta['_type'] == kTypeLab,
      isFinal: parsed.meta['_phase'] == kPhaseFinal,
    );
  }

  Widget _recStatTile(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF16215F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kGlassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.1)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _recTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _recCountChip(String text, Color color) {
    return Text(text,
        style: TextStyle(
            color: color, fontSize: 13.5, fontWeight: FontWeight.w700));
  }

  // Small pill under a record (Lab / Final / Edit / Delete).
  Widget _recAction({
    required IconData icon,
    required String text,
    required VoidCallback? onTap,
    bool filled = false,
    bool red = false,
  }) {
    return Expanded(
      child: GradPill(
        label: text,
        icon: icon,
        onTap: onTap,
        enabled: onTap != null,
        filled: filled,
        gradient: red ? kRedGrad : kBlueGrad,
        height: 34,
        fontSize: 13,
      ),
    );
  }

  Widget _recordCard(BuildContext context, _RecItem it, bool canEdit,
      bool canDelete, bool canChangeType, bool canChangePhase) {
    final total = it.present + it.absent;
    final pct = total > 0 ? it.present / total * 100 : 0.0;
    final meta = <String>[
      if (it.time.isNotEmpty) it.time,
      if (it.by.isNotEmpty) it.by,
    ].join(' · ');

    final actions = <Widget>[
      if (canChangeType)
        _recAction(
          // Shows what it will become.
          icon: it.isLab ? Icons.class_outlined : Icons.science_outlined,
          text: it.isLab ? 'Class' : 'Lab',
          onTap: () => _confirmChangeType(
              context, it.docId, it.label, it.isLab ? kTypeClass : kTypeLab),
        ),
      if (canChangePhase)
        _recAction(
          icon: it.isFinal
              ? Icons.hourglass_top_rounded
              : Icons.emoji_events_outlined,
          text: it.isFinal ? 'Mid' : 'Final',
          filled: true,
          onTap: () => _confirmChangePhase(context, it.docId, it.label,
              it.isFinal ? kPhaseMid : kPhaseFinal),
        ),
      if (canEdit)
        _recAction(
          icon: Icons.edit_outlined,
          text: 'Edit',
          onTap: (it.date == null || it.session == null)
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SubjectAttendanceScreen(
                        sem: sem,
                        semLabel: semLabel,
                        subjectName: subjectName,
                        initialDate: it.date,
                        initialSession: it.session,
                      ),
                    ),
                  );
                },
        ),
      if (canDelete)
        _recAction(
          icon: Icons.delete_outline,
          text: 'Delete',
          red: true,
          onTap: () => _confirmDelete(context, it.docId, it.label),
        ),
    ];

    return AppCard(
      subtle: true,
      radius: 20,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: kBlueGrad,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  it.session == null ? '-' : 'S${it.session}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _recTag(it.isLab ? 'Lab' : 'Class',
                            it.isLab ? kLabelBlue : kAccent),
                        _recTag(it.isFinal ? 'Final' : 'Mid',
                            it.isFinal ? kAbsent : kViolet),
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.schedule, color: kMuted, size: 14),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: kMuted, fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PanelRing(
                  pct: pct,
                  color: kAccent,
                  size: 46,
                  stroke: 4,
                  fontSize: 12),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _recCountChip('Present ${it.present}', kAccent),
                _recCountChip('Absent ${it.absent}', kAbsent),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecords(BuildContext context, bool canEdit, bool canDelete,
      bool canChangeType, bool canChangePhase) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Column(
          children: [
            HeaderCard(
              title: subjectName,
              subtitle: 'Records',
              actions: [
                if (canEdit)
                  HeaderTile(
                    icon: Icons.how_to_reg_outlined,
                    tooltip: 'Mark a student in all records',
                    onTap: () => _openStudentBulkSheet(context),
                  ),
              ],
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: liveQuery(sem.dates(subjectName)),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return EmptyState(
                      icon: Icons.event_busy,
                      text: 'No attendance records found.',
                      actionLabel: 'Mark attendance',
                      // This screen is opened from the marking screen, so go back to it.
                      onAction: () => Navigator.pop(context),
                    );
                  }

                  final docs = snapshot.data!.docs.toList();
                  docs.sort((a, b) => b.id.compareTo(a.id));
                  final items = [for (final d in docs) _parseRecord(d)];

                  // Top numbers: all sessions of this subject.
                  double pctSum = 0;
                  int counted = 0;
                  for (final it in items) {
                    final t = it.present + it.absent;
                    if (t > 0) {
                      pctSum += it.present / t * 100;
                      counted++;
                    }
                  }
                  final avg = counted == 0 ? 0.0 : pctSum / counted;
                  final midCount = items.where((i) => !i.isFinal).length;

                  final shown = items.where((i) {
                    switch (_filter) {
                      case 'class':
                        return !i.isLab;
                      case 'lab':
                        return i.isLab;
                      case 'mid':
                        return !i.isFinal;
                      case 'final':
                        return i.isFinal;
                      default:
                        return true;
                    }
                  }).toList();

                  // Group by date (already newest first).
                  final children = <Widget>[];
                  String? lastKey;
                  for (final it in shown) {
                    final key = it.date == null
                        ? it.docId
                        : DateFormat('dd MMM yyyy')
                            .format(it.date!)
                            .toUpperCase();
                    if (key != lastKey) {
                      lastKey = key;
                      children.add(Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 0, 4),
                        child: Text(key,
                            style: TextStyle(
                                color: kViolet.withValues(alpha: 0.95),
                                fontSize: 12.5,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w600)),
                      ));
                    }
                    children.add(_recordCard(context, it, canEdit, canDelete,
                        canChangeType, canChangePhase));
                  }

                  Widget filterPill(String label, String key) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GradPill(
                          label: label,
                          filled: _filter == key,
                          height: 34,
                          fontSize: 13.5,
                          onTap: () => setState(() => _filter = key),
                        ),
                      );

                  final listItems = <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            _recStatTile(
                                '${items.length}', 'Sessions', Colors.white),
                            const SizedBox(width: 8),
                            _recStatTile(
                                '${avg.round()}%', 'Avg present', kAccent),
                            const SizedBox(width: 8),
                            _recStatTile('$midCount', 'Mid sessions', kViolet),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            filterPill('All', 'all'),
                            filterPill('Class', 'class'),
                            filterPill('Lab', 'lab'),
                            filterPill('Mid', 'mid'),
                            filterPill('Final', 'final'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (children.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text('No records match this filter.',
                                style: TextStyle(color: kMuted, fontSize: 15)),
                          ),
                        )
                      else
                        ...children,
                  ];
                  // Builder: only the cards on screen are laid out and painted.
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
                    itemCount: listItems.length,
                    itemBuilder: (context, i) => listItems[i],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
