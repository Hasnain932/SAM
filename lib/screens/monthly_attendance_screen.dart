part of '../main.dart';

// Attendance for one chosen month.

// Monthly attendance (admin and teacher): pick a month to see only that month's
// records. Read from local SQLite (works offline), refreshed first when online.
class MonthlyAttendanceScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  const MonthlyAttendanceScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
  });

  @override
  State<MonthlyAttendanceScreen> createState() =>
      _MonthlyAttendanceScreenState();
}

class _MonthlyAttendanceScreenState extends State<MonthlyAttendanceScreen> {
  late DateTime _month; // always the 1st of the month
  bool _loading = true;
  bool _syncing = false;
  List<Map<String, String>> _students = [];
  List<DateRecord> _records = [];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _init();
  }

  Future<void> _init() async {
    try {
      _students = await loadSubjectStudents(widget.sem, widget.subjectName);
    } catch (e) {
      debugPrint('Monthly students load error: $e');
    }
    await _loadMonth();
    unawaited(_refreshFromServer());
  }

  Future<void> _loadMonth({bool spinner = true}) async {
    final month = _month;
    if (spinner && mounted) setState(() => _loading = true);
    final prefix = DateFormat('yyyy-MM').format(month);
    final recs = await LocalDb.dateRecords(widget.sem, widget.subjectName,
        monthPrefix: prefix);
    if (!mounted || month != _month) return;
    setState(() {
      _records = recs;
      _loading = false;
    });
  }

  // Online: pull this subject's latest records into SQLite, then redraw.
  Future<void> _refreshFromServer() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    final ok = await LocalDb.refreshSubjectAttendance(
        widget.sem, widget.subjectName);
    if (ok) await _loadMonth(spinner: false);
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _setMonth(DateTime m) async {
    _month = DateTime(m.year, m.month);
    await _loadMonth();
  }

  Future<void> _pickMonth() async {
    int month = _month.month;
    int year = _month.year.clamp(2020, 2030).toInt();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Select month'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: month,
                items: [
                  for (int m = 1; m <= 12; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(DateFormat('MMMM').format(DateTime(2000, m))),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => month = v);
                },
              ),
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: year,
                items: [
                  for (int y = 2020; y <= 2030; y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => year = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, DateTime(year, month)),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) await _setMonth(picked);
  }

  // ---- Excel export of the selected month (admin and teacher, every subject) ----
  bool _exporting = false;

  Future<void> _exportExcel() async {
    if (_exporting || _records.isEmpty || _students.isEmpty) return;
    final opt = await askExportOptions(context, _records);
    if (opt == null || !mounted) return;
    final recs = filterRecordsByScope(_records, opt.scope)
      ..sort((a, b) => a.id.compareTo(b.id));
    if (recs.isEmpty) {
      showSnack(context, 'No ${scopeLabel(opt.scope)} sessions in this month.',
          color: kAbsent);
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = buildAttendanceExcelBytes(
        info: await loadExcelInfo(widget.sem, widget.subjectName),
        recs: recs,
        students: _students,
        useLetters: opt.useLetters,
      );
      if (bytes == null) throw Exception('Excel file could not be created');

      // File name: Subject_Section_A_Semester_3_2026-10_[Class_|Lab_]Monthly_Report.xlsx
      final base =
          exportFileBase(widget.sem, widget.semLabel, widget.subjectName);
      final monthKey = DateFormat('yyyy-MM').format(_month);
      final fileName =
          '${base}_${monthKey}_${scopeFileTag(opt.scope)}Monthly_Report.xlsx';
      if (kIsWeb) {
        downloadBytes(bytes, fileName);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$fileName';
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        text:
            '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} - ${DateFormat('MMMM yyyy').format(_month)} Attendance',
      ));
    } catch (e) {
      debugPrint('Monthly Excel export error: $e');
      if (mounted) {
        showSnack(context, 'Could not create Excel file: $e', color: kAbsent);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildList() {
    if (_students.isEmpty) {
      return const EmptyState(
          icon: Icons.groups_outlined, text: 'No students in this subject.');
    }
    double sum = 0;
    for (final s in _students) {
      final roll = s['roll']!;
      final p = _records.where((r) => r.status[roll] == 'P').length;
      sum += (p / _records.length) * 100;
    }
    final avg = sum / _students.length;
    final monthKey = DateFormat('yyyy-MM').format(_month);

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            '${_records.length} session${_records.length == 1 ? '' : 's'} • average ${avg.toStringAsFixed(1)}%',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 13),
          ),
        ),
        for (final s in _students)
          buildStudentStatCard(s, _records,
              key: ValueKey('$monthKey-${s['roll']}')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_month);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subjectName} - Monthly'),
        actions: [
          IconButton(
            tooltip: 'Download month as Excel',
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            onPressed: (_records.isEmpty || _exporting) ? null : _exportExcel,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                  onPressed: () =>
                      _setMonth(DateTime(_month.year, _month.month - 1)),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickMonth,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(monthLabel,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, color: kAccent),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                  onPressed: () =>
                      _setMonth(DateTime(_month.year, _month.month + 1)),
                ),
              ],
            ),
          ),
          if (_syncing)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? EmptyState(
                        icon: Icons.event_busy,
                        text: 'No attendance recorded in $monthLabel.')
                    : _buildList(),
          ),
        ],
      ),
    );
  }
}
