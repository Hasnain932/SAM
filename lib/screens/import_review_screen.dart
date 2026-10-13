part of '../main.dart';

// Pick a file, then review what will be imported.

// Pick a file and parse it. Returns null on error (a snackbar is shown).
Future<ImportSheet?> pickAttendanceSheetFromFile(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'csv'],
    );
  } catch (e) {
    debugPrint('File picker error: $e');
    if (!context.mounted) return null;
    _importSnack(context, 'Could not open the file picker.');
    return null;
  }
  if (f == null) return null;

  Uint8List? bytes;
  try {
    bytes = await f.readAsBytes();
  } catch (_) {}
  if (bytes == null) {
    if (!context.mounted) return null;
    _importSnack(context, 'Could not read the selected file.');
    return null;
  }

  final ext = (f.extension ?? f.name.split('.').last).toLowerCase();
  ImportSheet? sheet;
  var anyGrid = false;
  try {
    final isZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (ext == 'xlsx' || ext == 'xlsm' || isZip) {
      var bestScore = 0;
      for (final g in _allXlsxGrids(bytes, forAttendance: true)) {
        anyGrid = true;
        final sh = parseAttendanceSheet(g);
        if (sh == null) continue;
        var sc = 0;
        for (final r in sh.rows) {
          sc += r.status.length;
        }
        if (sc > bestScore) {
          bestScore = sc;
          sheet = sh;
        }
      }
    } else {
      final g = _parseCsvText(utf8.decode(bytes, allowMalformed: true));
      anyGrid = g.isNotEmpty;
      sheet = parseAttendanceSheet(g);
    }
  } catch (e) {
    debugPrint('Attendance import parse error: $e');
    if (!context.mounted) return null;
    _importSnack(context, 'Could not read this file: $e');
    return null;
  }

  if (!anyGrid) {
    if (!context.mounted) return null;
    _importSnack(context,
        'Could not read this file. Please use .xlsx or .csv (old .xls is not supported - open it and Save As .xlsx).');
    return null;
  }

  if (sheet == null) {
    if (!context.mounted) return null;
    _importSnack(context,
        'No attendance found. The file needs a row of dates on top and student names on the left with P / A under each date.');
    return null;
  }
  return sheet;
}

// Review screen: shows what will be imported and the unmatched names. The user can
// link a name to a student or skip it.
class ImportReviewScreen extends StatefulWidget {
  final ImportSheet sheet;
  final List<Map<String, String>> students;
  final Set<String> existingIds;
  final bool canOverwrite;
  const ImportReviewScreen({
    super.key,
    required this.sheet,
    required this.students,
    required this.existingIds,
    required this.canOverwrite,
  });

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late final Map<int, String> _map;
  late final Set<int> _autoRows;
  late final Set<int> _cols;
  bool _blankPresent = true;

  bool _locked(ImportColumn c) =>
      widget.existingIds.contains(c.docId) && !widget.canOverwrite;

  @override
  void initState() {
    super.initState();
    _map = autoMatchImportRows(widget.sheet.rows, widget.students);
    _autoRows = _map.keys.toSet();
    _cols = {
      for (final c in widget.sheet.columns)
        if (!_locked(c)) c.col
    };
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.sheet.rows;
    final unmatched = [
      for (var i = 0; i < rows.length; i++)
        if (!_autoRows.contains(i)) i
    ];
    final noRow =
        widget.students.where((s) => !_map.containsValue(s['roll'])).length;
    final overwriteCount = widget.sheet.columns
        .where((c) => _cols.contains(c.col) && widget.existingIds.contains(c.docId))
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Import attendance')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _cols.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      ImportPlan(Map<int, String>.from(_map),
                          Set<int>.from(_cols), _blankPresent)),
              child: Text(
                'Import ${_cols.length} date${_cols.length == 1 ? '' : 's'}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.sheet.columns.length} dates • ${rows.length} names in file',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_map.length} matched'
                  '${noRow > 0 ? ' • $noRow students of this subject have no row in the file' : ''}',
                  style: const TextStyle(color: kMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Empty cells count as',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Present')),
                    ButtonSegment(value: false, label: Text('Absent')),
                  ],
                  selected: {_blankPresent},
                  onSelectionChanged: (s) =>
                      setState(() => _blankPresent = s.first),
                ),
              ],
            ),
          ),
          if (unmatched.isNotEmpty) ...[
            InfoBanner(
              text:
                  '${unmatched.length} name${unmatched.length == 1 ? '' : 's'} could not be matched. Choose the right student for each, or skip it.',
              icon: Icons.person_search_outlined,
            ),
            for (final i in unmatched)
              AppCard(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rows[i].name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    DropdownButton<String?>(
                      isExpanded: true,
                      value: _map[i],
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Skip (not matched)')),
                        for (final s in widget.students)
                          if (s['roll'] == _map[i] ||
                              !_map.containsValue(s['roll']))
                            DropdownMenuItem<String?>(
                              value: s['roll'],
                              child: Text(
                                '${rollOf(s['roll']!)} • ${s['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: (v) => setState(() {
                        if (v == null) {
                          _map.remove(i);
                        } else {
                          _map[i] = v;
                        }
                      }),
                    ),
                  ],
                ),
              ),
          ],
          if (overwriteCount > 0)
            InfoBanner(
              text:
                  '$overwriteCount of the selected dates already have attendance. Importing will replace it.',
              icon: Icons.warning_amber_rounded,
              color: kAbsent,
            ),
          if (widget.sheet.columns.any(_locked))
            const InfoBanner(
              text:
                  'Dates that already have attendance are locked for teachers. Only an admin can replace them.',
              icon: Icons.lock_outline,
            ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text('Dates (${_cols.length} selected)',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                children: [
                  for (final c in widget.sheet.columns)
                    CheckboxListTile(
                      dense: true,
                      value: _cols.contains(c.col),
                      onChanged: _locked(c)
                          ? null
                          : (v) => setState(() {
                                if (v == true) {
                                  _cols.add(c.col);
                                } else {
                                  _cols.remove(c.col);
                                }
                              }),
                      title: Text(
                          '${DateFormat('dd MMM yyyy').format(c.date)} • Session ${c.session}'),
                      subtitle: widget.existingIds.contains(c.docId)
                          ? Text(
                              _locked(c)
                                  ? 'Already taken (locked)'
                                  : 'Already taken (will be replaced)',
                              style: const TextStyle(
                                  color: kMuted, fontSize: 12))
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
