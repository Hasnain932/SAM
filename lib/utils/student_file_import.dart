part of '../main.dart';

// Reads student names from an Excel / CSV / TXT file.

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
    } catch (_) {}
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

// 0 = not a name header, 1 = full name, 2 = first name, 3 = last name.
int _importNameHeaderKind(String raw) {
  final c = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (c.isEmpty || c.length > 32) return 0;
  if (RegExp(r'father|mother|guardian|parent|husband|spouse').hasMatch(c) ||
      c.contains('\u092A\u093F\u0924\u093E') ||
      c.contains('\u092E\u093E\u0924\u093E')) {
    return 0;
  }
  if (RegExp(r'^(first|given)\b').hasMatch(c) && c.contains('name')) return 2;
  if (RegExp(r'^(last|sur|family)').hasMatch(c) && c.contains('name')) {
    return 3;
  }
  if (c == 'student' || c == 'students') return 1;
  if (RegExp(r'\b(names?|naam)\b').hasMatch(c) || c.contains('\u0928\u093E\u092E')) {
    return 1;
  }
  return 0;
}

bool _importLooksLikeName(String n) =>
    n.length >= 2 &&
    _importLetterRe.hasMatch(n) &&
    !RegExp(r'\d').hasMatch(n) &&
    !_importSkipRowRe.hasMatch(n);

List<String> _namesFromRows(List<List<String>> rows) {
  final data = rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
  if (data.isEmpty) return [];

  final out = <String>[];
  void add(String raw) {
    final name = _cleanImportedName(raw);
    if (name.isEmpty || !_importLetterRe.hasMatch(name)) return;
    if (_importSkipRowRe.hasMatch(name)) return;
    out.add(name);
  }

  // 1) Find a header row in the first 15 rows (rows above it are ignored). Supports
  // "Name", "Student Name", "Name of Student", "naam", or separate First / Last Name.
  var headerRow = -1;
  var nameCol = -1, firstCol = -1, lastCol = -1;
  final scan = data.length < 15 ? data.length : 15;
  for (var i = 0; i < scan && headerRow < 0; i++) {
    var n = -1, f = -1, l = -1;
    for (var c = 0; c < data[i].length; c++) {
      final k = _importNameHeaderKind(data[i][c]);
      if (k == 1 && n < 0) {
        n = c;
      } else if (k == 2 && f < 0) {
        f = c;
      } else if (k == 3 && l < 0) {
        l = c;
      }
    }
    if (n >= 0 || (f >= 0 && l >= 0)) {
      headerRow = i;
      nameCol = n;
      firstCol = f;
      lastCol = l;
    }
  }

  if (headerRow >= 0) {
    for (final r in data.skip(headerRow + 1)) {
      String at(int c) => (c >= 0 && c < r.length) ? r[c] : '';
      if (nameCol >= 0) {
        add(at(nameCol));
      } else {
        add('${at(firstCol)} ${at(lastCol)}');
      }
    }
    return out;
  }

  // 2) No name header: skip any roll/serial header row, then pick the column that
  // looks most like names (letters, no digits, several words). Codes like "21CS001" aren't names.
  const headerWords = {
    'roll', 'roll no', 'roll no.', 'roll number', 'rollno', 'sr', 'sr.',
    'sr no', 'sr no.', 'sr#', 's.no', 's no', 'sno', 'serial', 'serial no',
    '#', 'no', 'no.', 'id', 'reg no', 'registration no',
  };
  final firstNorm = data.first
      .map((c) => c.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim())
      .toList();
  final body = data.skip(firstNorm.any(headerWords.contains) ? 1 : 0).toList();
  var width = 0;
  for (final r in body) {
    if (r.length > width) width = r.length;
  }
  var bestCol = 0;
  var bestScore = -1;
  for (var c = 0; c < width; c++) {
    var score = 0;
    for (final r in body) {
      if (c >= r.length) continue;
      final n = _cleanImportedName(r[c]);
      if (_importLooksLikeName(n)) score += n.contains(' ') ? 3 : 2;
    }
    if (score > bestScore) {
      bestScore = score;
      bestCol = c;
    }
  }
  for (final r in body) {
    if (bestCol < r.length) add(r[bestCol]);
  }
  return out;
}

// Pick a file and read the list of names from it. Returns null on error.
Future<List<String>?> pickStudentNamesFromFile(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'csv', 'txt'],
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
  List<String> names;
  try {
    if (ext == 'xlsx' || ext == 'xlsm') {
      var rows = <List<String>>[];
      for (final r in _allXlsxGrids(bytes, forAttendance: false)) {
        if (_namesFromRows(r).isNotEmpty) {
          rows = r;
          break;
        }
      }
      names = _namesFromRows(rows);
    } else if (ext == 'txt') {
      final lines = utf8
          .decode(bytes, allowMalformed: true)
          .replaceFirst('\uFEFF', '')
          .split(RegExp(r'\r?\n'));
      names = _namesFromRows([
        for (final l in lines) [l.trim()]
      ]);
    } else {
      names = _namesFromRows(
          _parseCsvText(utf8.decode(bytes, allowMalformed: true)));
    }
  } catch (e) {
    debugPrint('Import parse error: $e');
    if (!context.mounted) return null;
    _importSnack(context,
        'Could not read this file. Please use .xlsx, .csv or .txt (old .xls is not supported).');
    return null;
  }

  if (names.isEmpty) {
    if (!context.mounted) return null;
    _importSnack(context, 'No student names found in this file.');
    return null;
  }
  return names;
}

// Confirm dialog: asks for the first roll number (default 1), null if cancelled.
// Shows the resulting roll range live and warns if any rolls are already used.
Future<int?> confirmStudentImport(
  BuildContext context,
  List<String> names,
  String where, {
  Set<String> existingRolls = const <String>{},
}) {
  final startCtrl = TextEditingController(text: '1');
  final seen = <String>{};
  var dupes = 0;
  for (final n in names) {
    if (!seen.add(n.toLowerCase())) dupes++;
  }
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final parsed = int.tryParse(startCtrl.text.trim());
        final int? start = (parsed != null && parsed >= 1) ? parsed : null;
        var clash = 0;
        if (start != null) {
          for (var i = 0; i < names.length; i++) {
            if (existingRolls.contains((start + i).toString())) clash++;
          }
        }
        return AlertDialog(
          title: Text(
              'Import ${names.length} student${names.length == 1 ? '' : 's'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Into: $where',
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 10),
                for (final n in names.take(5))
                  Text('\u2022 $n', maxLines: 1, overflow: TextOverflow.ellipsis),
                if (names.length > 5)
                  Text('\u2026 and ${names.length - 5} more',
                      style: const TextStyle(color: kMuted)),
                if (dupes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$dupes name${dupes == 1 ? '' : 's'} appear more than once in the file.',
                    style: const TextStyle(color: kAccent, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Roll numbers are given in file order, counting up from '
                  'the number you enter (first name = first roll number).',
                  style: TextStyle(color: kMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: startCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    labelText: 'First roll number',
                    errorText:
                        start != null ? null : 'Enter a number (1 or more)',
                    helperText: start != null
                        ? 'Roll $start to ${start + names.length - 1}'
                        : null,
                  ),
                ),
                if (clash > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$clash of these roll numbers already exist. The new '
                    'students will be added next to them with the same roll '
                    'number; nothing is overwritten.',
                    style: const TextStyle(color: kAccent, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  start != null ? () => Navigator.pop(ctx, start) : null,
              child: const Text('Import'),
            ),
          ],
        );
      },
    ),
  );
}
