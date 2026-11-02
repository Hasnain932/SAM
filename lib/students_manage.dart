part of 'main.dart';

// ---------------------------------------------------------------------------
// Smart matching helpers (used by the student import AND the old attendance
// import). Case, spaces and punctuation don't matter; common spelling
// variants (Muhammad / Mohammad / Mohd / M., Abdul / Abd ...) are treated as
// the same word; small typos are tolerated with a safe threshold.
// ---------------------------------------------------------------------------
const Map<String, String> _kNameAliases = {
  'mohammad': 'muhammad',
  'mohammed': 'muhammad',
  'muhammed': 'muhammad',
  'mohamed': 'muhammad',
  'mohamad': 'muhammad',
  'muhamad': 'muhammad',
  'mohd': 'muhammad',
  'muhd': 'muhammad',
  'mhd': 'muhammad',
  'md': 'muhammad',
  'abd': 'abdul',
  'abdu': 'abdul',
  'abdur': 'abdul',
  'abdel': 'abdul',
  'rehman': 'rahman',
};

String _canonPerson(String s) {
  final t = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return '';
  final parts = t.split(' ');
  for (var i = 0; i < parts.length; i++) {
    if (i == 0 && parts[i] == 'm' && parts.length > 1) {
      parts[i] = 'muhammad';
    } else {
      parts[i] = _kNameAliases[parts[i]] ?? parts[i];
    }
  }
  return parts.join(' ');
}

// Same words in any order give the same key ("Khan Ali" == "Ali Khan").
String _sortedCanon(String s) {
  final t = _canonPerson(s).split(' ')..sort();
  return t.join(' ').trim();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
      cur[j] = v;
    }
    prev = cur;
  }
  return prev[b.length];
}

double _stringRatio(String a, String b) {
  final m = a.length > b.length ? a.length : b.length;
  if (m == 0) return 1;
  return 1 - _levenshtein(a, b) / m;
}

// 0..1 similarity of two person names.
double _personSim(String a, String b) {
  final x = _canonPerson(a);
  final y = _canonPerson(b);
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  final r1 = _stringRatio(x, y);
  final r2 = _stringRatio(_sortedCanon(a), _sortedCanon(b));
  return r1 > r2 ? r1 : r2;
}

// Father names: true = same person's father, false = clearly different,
// null = unknown (one of them is empty).
bool? _fatherCompat(String a, String b) {
  if (a.trim().isEmpty || b.trim().isEmpty) return null;
  return _personSim(a, b) >= 0.8;
}

// ---------------------------------------------------------------------------
// Student import (Excel .xlsx / .xls / CSV / TXT): Name + Father Name columns.
// Roll numbers are NOT read from the file; they follow file order.
// ---------------------------------------------------------------------------
class ImportedStudent {
  final String name;
  final String father;
  const ImportedStudent(this.name, this.father);
}

// Header text -> letters only, lowercase. "F. Name" -> "fname", "S/O" -> "so".
String _compactHeader(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{M}]', unicode: true), '');

// 0 = not a name header, 1 = full name, 2 = first name, 3 = last name,
// 4 = father name. The header wording does not matter.
int _studentHeaderKind(String raw) {
  final c = _compactHeader(raw);
  if (c.isEmpty || c.length > 40) return 0;
  const fatherExact = {
    'fo', 'fname', 'so', 'do', 'sodo', 'sdo', 'walid', 'wald', 'waldiyat',
    'guardian', 'gaurdian', 'parent', 'parentname',
  };
  if (c.contains('father') ||
      fatherExact.contains(c) ||
      c.startsWith('walid') ||
      c.startsWith('wald') ||
      c.startsWith('guardian') ||
      c.contains('पिता') ||
      c.contains('والد')) {
    return 4;
  }
  if (RegExp(r'mother|husband|spouse').hasMatch(c)) return 0;
  if ((c.startsWith('first') || c.startsWith('given')) && c.contains('name')) {
    return 2;
  }
  if ((c.startsWith('last') || c.startsWith('sur') || c.startsWith('family')) &&
      c.contains('name')) {
    return 3;
  }
  if (c == 'student' || c == 'students') return 1;
  if (c.contains('name') ||
      c.contains('naam') ||
      c.contains('नाम') ||
      c.contains('نام')) {
    return 1;
  }
  return 0;
}

bool _importLooksLikeName(String n) =>
    n.length >= 2 &&
    _importLetterRe.hasMatch(n) &&
    !RegExp(r'\d').hasMatch(n) &&
    !_importSkipRowRe.hasMatch(n);

// Father name cell: same cleanup as a name, minus "S/O", "D/O" prefixes.
String _cleanImportedFather(String raw) {
  var s = _cleanImportedName(raw);
  s = s.replaceFirst(
      RegExp(r'^(s\s*/\s*o|d\s*/\s*o|w\s*/\s*o|son\s+of|daughter\s+of)\s*[:.\-]?\s*',
          caseSensitive: false),
      '');
  s = s.trim();
  if (!_importLetterRe.hasMatch(s)) return '';
  const empties = {'na', 'n/a', 'nil', 'none', 'null'};
  if (empties.contains(s.toLowerCase())) return '';
  return s;
}

class _StudentCols {
  final int firstRow; // first data row
  final int nameCol; // -1 when first + last name columns are used
  final int fatherCol; // -1 = none
  final int firstNameCol;
  final int lastNameCol;
  final bool sure; // false: ask the user which column is which
  const _StudentCols(this.firstRow, this.nameCol, this.fatherCol,
      this.firstNameCol, this.lastNameCol, this.sure);
}

// How many cells of each column look like a person's name.
List<int> _nameLikeCounts(List<List<String>> rows) {
  var w = 0;
  for (final r in rows) {
    if (r.length > w) w = r.length;
  }
  final out = List<int>.filled(w, 0);
  for (final r in rows) {
    for (var c = 0; c < r.length; c++) {
      if (_importLooksLikeName(_cleanImportedName(r[c]))) out[c]++;
    }
  }
  return out;
}

_StudentCols? _detectStudentCols(List<List<String>> data) {
  if (data.isEmpty) return null;

  // 1) A header row in the first 15 rows (title rows above it are ignored).
  final scan = data.length < 15 ? data.length : 15;
  for (var i = 0; i < scan; i++) {
    var n = -1, f = -1, l = -1, fa = -1;
    for (var c = 0; c < data[i].length; c++) {
      switch (_studentHeaderKind(data[i][c])) {
        case 1:
          if (n < 0) n = c;
        case 2:
          if (f < 0) f = c;
        case 3:
          if (l < 0) l = c;
        case 4:
          if (fa < 0) fa = c;
      }
    }
    final hasName = n >= 0 || (f >= 0 && l >= 0);
    if (!hasName && fa < 0) continue;
    var nameCol = n;
    if (!hasName) {
      // Only a father header was recognised: the name is the best text column left.
      final counts = _nameLikeCounts(data.skip(i + 1).toList());
      var best = -1, bestV = 0;
      for (var c = 0; c < counts.length; c++) {
        if (c == fa) continue;
        if (counts[c] > bestV) {
          bestV = counts[c];
          best = c;
        }
      }
      if (best < 0) continue;
      nameCol = best;
    }
    return _StudentCols(i + 1, hasName && n < 0 ? -1 : nameCol, fa, f, l, true);
  }

  // 2) No header: skip a roll / serial header row, then take the text columns
  // from left to right (first = name, second = father name).
  const headerWords = {
    'roll', 'roll no', 'roll no.', 'roll number', 'rollno', 'sr', 'sr.',
    'sr no', 'sr no.', 'sr#', 's.no', 's no', 'sno', 'serial', 'serial no',
    '#', 'no', 'no.', 'id', 'reg no', 'registration no',
  };
  final firstNorm = data.first
      .map((c) => c.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim())
      .toList();
  final start = firstNorm.any(headerWords.contains) ? 1 : 0;
  final body = data.skip(start).toList();
  if (body.isEmpty) return null;
  final counts = _nameLikeCounts(body);
  final need = (body.length * 0.5).ceil();
  final textCols = <int>[
    for (var c = 0; c < counts.length; c++)
      if (counts[c] > 0 && counts[c] >= need) c
  ];
  if (textCols.isEmpty) {
    // Weak columns: use the single best one as the name.
    var best = -1, bestV = 0;
    for (var c = 0; c < counts.length; c++) {
      if (counts[c] > bestV) {
        bestV = counts[c];
        best = c;
      }
    }
    if (best < 0) return null;
    return _StudentCols(start, best, -1, -1, -1, true);
  }
  return _StudentCols(start, textCols[0],
      textCols.length > 1 ? textCols[1] : -1, -1, -1, textCols.length < 2);
}

List<ImportedStudent> _extractStudents(
    List<List<String>> data, _StudentCols c) {
  final out = <ImportedStudent>[];
  for (final r in data.skip(c.firstRow)) {
    String at(int i) => (i >= 0 && i < r.length) ? r[i] : '';
    final raw = c.nameCol >= 0
        ? at(c.nameCol)
        : '${at(c.firstNameCol)} ${at(c.lastNameCol)}';
    final name = _cleanImportedName(raw);
    if (name.isEmpty || !_importLetterRe.hasMatch(name)) continue;
    if (_importSkipRowRe.hasMatch(name)) continue;
    final father = c.fatherCol >= 0 ? _cleanImportedFather(at(c.fatherCol)) : '';
    out.add(ImportedStudent(name, father));
  }
  return out;
}

// Small screen: which column is the Name and which is the Father Name.
// Only shown when the file has no clear headers and several text columns.
Future<_StudentCols?> _askStudentColumns(
    BuildContext context, List<List<String>> data, _StudentCols guess) {
  var width = 0;
  for (final r in data) {
    if (r.length > width) width = r.length;
  }
  String sample(int c) {
    final vals = <String>[];
    for (final r in data.skip(guess.firstRow)) {
      if (c < r.length && r[c].trim().isNotEmpty) vals.add(r[c].trim());
      if (vals.length == 3) break;
    }
    return vals.join(', ');
  }

  final cols = <int>[
    for (var c = 0; c < width; c++)
      if (sample(c).isNotEmpty) c
  ];
  var nameCol = cols.contains(guess.nameCol) ? guess.nameCol : cols.first;
  var fatherCol = cols.contains(guess.fatherCol) ? guess.fatherCol : -1;

  return showDialog<_StudentCols>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        DropdownMenuItem<int> item(int c) => DropdownMenuItem<int>(
              value: c,
              child: Text('${_excelColLetters(c)}: ${sample(c)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            );
        return AlertDialog(
          title: const Text('Which column is which?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This file has no clear headers. Please choose the columns.',
                  style: TextStyle(color: kMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                const Text('Student name'),
                DropdownButton<int>(
                  isExpanded: true,
                  value: nameCol,
                  items: [for (final c in cols) item(c)],
                  onChanged: (v) => setS(() => nameCol = v ?? nameCol),
                ),
                const SizedBox(height: 8),
                const Text('Father name'),
                DropdownButton<int>(
                  isExpanded: true,
                  value: fatherCol,
                  items: [
                    const DropdownMenuItem<int>(value: -1, child: Text('None')),
                    for (final c in cols) item(c),
                  ],
                  onChanged: (v) => setS(() => fatherCol = v ?? fatherCol),
                ),
                if (nameCol == fatherCol)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Name and father name must be different columns.',
                        style: TextStyle(color: kAbsent, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: nameCol == fatherCol
                  ? null
                  : () => Navigator.pop(ctx,
                      _StudentCols(guess.firstRow, nameCol, fatherCol, -1, -1, true)),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    ),
  );
}

// Pick a file and read students (name + father name) from it. Null on error.
Future<List<ImportedStudent>?> pickStudentsFromFile(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls', 'csv', 'txt'],
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
  } catch (e) {
    debugPrint('students_manage.dart:392: $e');
  }
  if (bytes == null) {
    if (!context.mounted) return null;
    _importSnack(context, 'Could not read the selected file.');
    return null;
  }

  final ext = (f.extension ?? f.name.split('.').last).toLowerCase();
  var grids = <List<List<String>>>[];
  try {
    final isZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (ext == 'xlsx' || ext == 'xlsm' || ext == 'xls' || isZip) {
      grids = _allXlsxGrids(bytes, forAttendance: false);
    } else if (ext == 'txt') {
      final lines = utf8
          .decode(bytes, allowMalformed: true)
          .replaceFirst('﻿', '')
          .split(RegExp(r'\r?\n'));
      grids = [
        [
          for (final l in lines) [l.trim()]
        ]
      ];
    } else {
      grids = [_parseCsvText(utf8.decode(bytes, allowMalformed: true))];
    }
  } catch (e) {
    debugPrint('Import parse error: $e');
  }
  if (grids.isEmpty) {
    if (!context.mounted) return null;
    _importSnack(context,
        'Could not read this file. Please use .xlsx or .csv (an old .xls may need to be opened and saved as .xlsx).');
    return null;
  }

  // First sheet that really contains students.
  List<List<String>>? data;
  _StudentCols? cols;
  for (final g in grids) {
    final d = g.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    final c = _detectStudentCols(d);
    if (c != null && _extractStudents(d, c).isNotEmpty) {
      data = d;
      cols = c;
      break;
    }
  }
  if (data == null || cols == null) {
    if (!context.mounted) return null;
    _importSnack(context, 'No student names found in this file.');
    return null;
  }

  if (!cols.sure) {
    if (!context.mounted) return null;
    cols = await _askStudentColumns(context, data, cols);
    if (cols == null) return null;
  }

  final list = _extractStudents(data, cols);
  if (list.isEmpty) {
    if (!context.mounted) return null;
    _importSnack(context, 'No student names found in this file.');
    return null;
  }
  return list;
}

// ---- Import plan: new students, father names to fill, conflicts ----
class FatherConflict {
  final String key;
  final String name;
  final String oldFather;
  final String newFather;
  const FatherConflict(this.key, this.name, this.oldFather, this.newFather);
}

class FuzzyPair {
  final String fileName;
  final String appName;
  const FuzzyPair(this.fileName, this.appName);
}

class StudentImportPlan {
  final List<MapEntry<String, String>> fills; // student key -> father to fill
  final List<FatherConflict> conflicts; // existing father is different
  final List<ImportedStudent> newOnes; // not in the app yet
  final List<FuzzyPair> fuzzy; // matched with a small spelling difference
  final int unchanged; // matched, nothing to change
  final int fileDupes; // names that appear more than once in the file
  final int total;
  const StudentImportPlan({
    required this.fills,
    required this.conflicts,
    required this.newOnes,
    required this.fuzzy,
    required this.unchanged,
    required this.fileDupes,
    required this.total,
  });
  int get matched => fills.length + conflicts.length + unchanged;
}

// Matches the file against the students already in the app, by NAME.
// Same name twice: the 1st occurrence in the file goes to the lower roll,
// the 2nd to the next one (a father name, when known, decides first).
StudentImportPlan planStudentImport(
    List<ImportedStudent> imported, List<Map<String, String>> existing) {
  final byKey = <String, List<int>>{};
  for (var i = 0; i < existing.length; i++) {
    (byKey[_sortedCanon(existing[i]['name'] ?? '')] ??= <int>[]).add(i);
  }
  final taken = <int>{};
  final matchOf = <int, int>{};
  final isFuzzy = <int>{};

  String fatherOf(int e) => existing[e]['father'] ?? '';

  int? pick(List<int> cands, String father) {
    final free = cands.where((e) => !taken.contains(e)).toList();
    if (free.isEmpty) return null;
    if (father.isEmpty) return free.first;
    for (final e in free) {
      if (_fatherCompat(fatherOf(e), father) == true) return e;
    }
    for (final e in free) {
      if (_fatherCompat(fatherOf(e), father) == null) return e;
    }
    return free.first;
  }

  for (var i = 0; i < imported.length; i++) {
    final cands = byKey[_sortedCanon(imported[i].name)];
    if (cands == null) continue;
    final e = pick(cands, imported[i].father);
    if (e != null) {
      matchOf[i] = e;
      taken.add(e);
    }
  }

  // Small typos: only when exactly one student is clearly the closest.
  for (var i = 0; i < imported.length; i++) {
    if (matchOf.containsKey(i)) continue;
    var best = 0.0, second = 0.0;
    var bi = -1;
    for (var e = 0; e < existing.length; e++) {
      if (taken.contains(e)) continue;
      if (_fatherCompat(fatherOf(e), imported[i].father) == false) continue;
      final s = _personSim(imported[i].name, existing[e]['name'] ?? '');
      if (s > best) {
        second = best;
        best = s;
        bi = e;
      } else if (s > second) {
        second = s;
      }
    }
    if (bi >= 0 && best >= 0.9 && best - second >= 0.05) {
      matchOf[i] = bi;
      taken.add(bi);
      isFuzzy.add(i);
    }
  }

  final fills = <MapEntry<String, String>>[];
  final conflicts = <FatherConflict>[];
  final newOnes = <ImportedStudent>[];
  final fuzzy = <FuzzyPair>[];
  var unchanged = 0;
  for (var i = 0; i < imported.length; i++) {
    final e = matchOf[i];
    if (e == null) {
      newOnes.add(imported[i]);
      continue;
    }
    final s = existing[e];
    final key = (s['roll'] ?? '');
    final oldF = fatherOf(e).trim();
    final newF = imported[i].father.trim();
    if (isFuzzy.contains(i)) {
      fuzzy.add(FuzzyPair(imported[i].name, s['name'] ?? ''));
    }
    if (newF.isEmpty) {
      unchanged++;
    } else if (oldF.isEmpty) {
      fills.add(MapEntry(key, newF));
    } else if (_fatherCompat(oldF, newF) == true) {
      unchanged++;
    } else {
      conflicts.add(FatherConflict(key, s['name'] ?? '', oldF, newF));
    }
  }

  final seen = <String>{};
  var dupes = 0;
  for (final s in imported) {
    if (!seen.add(_sortedCanon(s.name))) dupes++;
  }
  return StudentImportPlan(
    fills: fills,
    conflicts: conflicts,
    newOnes: newOnes,
    fuzzy: fuzzy,
    unchanged: unchanged,
    fileDupes: dupes,
    total: imported.length,
  );
}

class StudentImportDecision {
  final int start; // first roll number for the new students
  final bool overwrite; // replace different father names with the file's
  const StudentImportDecision(this.start, this.overwrite);
}

// Preview + confirm. Null if cancelled.
Future<StudentImportDecision?> confirmStudentImportPlan(
  BuildContext context,
  StudentImportPlan plan,
  String where,
  List<Map<String, String>> existing,
) {
  final existingRolls = {for (final s in existing) rollOf(s['roll'] ?? '')};
  var maxRoll = 0;
  for (final r in existingRolls) {
    final n = int.tryParse(r) ?? 0;
    if (n > maxRoll) maxRoll = n;
  }
  final startCtrl =
      TextEditingController(text: plan.matched > 0 ? '${maxRoll + 1}' : '1');
  var overwrite = false;
  final hasNew = plan.newOnes.isNotEmpty;

  Widget line(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(text, style: TextStyle(fontSize: 13.5, color: color)),
      );

  return showDialog<StudentImportDecision>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final parsed = int.tryParse(startCtrl.text.trim());
        final int? start = (parsed != null && parsed >= 1) ? parsed : null;
        var clash = 0;
        if (hasNew && start != null) {
          for (var i = 0; i < plan.newOnes.length; i++) {
            if (existingRolls.contains((start + i).toString())) clash++;
          }
        }
        final work = plan.fills.length +
            plan.newOnes.length +
            (overwrite ? plan.conflicts.length : 0);
        final canImport = work > 0 && (!hasNew || start != null);
        return AlertDialog(
          title: Text(
              'Import ${plan.total} student${plan.total == 1 ? '' : 's'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Into: $where',
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 10),
                line('Father names to fill: ${plan.fills.length}',
                    color: plan.fills.isEmpty ? kMuted : kPresent),
                line('New students to add: ${plan.newOnes.length}',
                    color: plan.newOnes.isEmpty ? kMuted : kPresent),
                line('Already up to date: ${plan.unchanged}', color: kMuted),
                if (plan.conflicts.isNotEmpty)
                  line(
                      'Different father name: ${plan.conflicts.length}'
                      '${overwrite ? ' (will be replaced)' : ' (skipped)'}',
                      color: kAbsent),
                if (plan.conflicts.isNotEmpty) ...[
                  for (final c in plan.conflicts.take(4))
                    Text(
                        '• ${c.name}: ${c.oldFather} → ${c.newFather}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  if (plan.conflicts.length > 4)
                    Text('… and ${plan.conflicts.length - 4} more',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: overwrite,
                    title: const Text('Replace with the file’s father name',
                        style: TextStyle(fontSize: 13)),
                    onChanged: (v) => setS(() => overwrite = v),
                  ),
                ],
                if (plan.fuzzy.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  line('Matched with a small spelling difference:',
                      color: kAccent),
                  for (final p in plan.fuzzy.take(4))
                    Text('• ${p.fileName} → ${p.appName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  if (plan.fuzzy.length > 4)
                    Text('… and ${plan.fuzzy.length - 4} more',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                ],
                if (hasNew) ...[
                  const SizedBox(height: 8),
                  for (final s in plan.newOnes.take(5))
                    Text(
                        '• ${s.name}${s.father.isEmpty ? '' : '  (F/N ${s.father})'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  if (plan.newOnes.length > 5)
                    Text('… and ${plan.newOnes.length - 5} more',
                        style: const TextStyle(color: kMuted)),
                ],
                if (plan.fileDupes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${plan.fileDupes} name${plan.fileDupes == 1 ? '' : 's'} appear more than once in the file.',
                    style: const TextStyle(color: kAccent, fontSize: 12.5),
                  ),
                ],
                if (hasNew) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'New students get roll numbers in file order, counting up from the number you enter.',
                    style: TextStyle(color: kMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: startCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      labelText: 'First roll number',
                      errorText:
                          start != null ? null : 'Enter a number (1 or more)',
                      helperText: start != null
                          ? 'Roll $start to ${start + plan.newOnes.length - 1}'
                          : null,
                    ),
                  ),
                  if (clash > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$clash of these roll numbers already exist. The new students will be added next to them with the same roll number; nothing is overwritten.',
                      style: const TextStyle(color: kAccent, fontSize: 12.5),
                    ),
                  ],
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
              onPressed: canImport
                  ? () => Navigator.pop(
                      ctx, StudentImportDecision(start ?? 1, overwrite))
                  : null,
              child: const Text('Import'),
            ),
          ],
        );
      },
    ),
  );
}


// Manage students screen (admin: master student list of this semester)
class ManageStudentsScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String deptName;
  const ManageStudentsScreen(
      {super.key,
      required this.sem,
      required this.semLabel,
      this.deptName = ''});

  @override
  State<ManageStudentsScreen> createState() => _ManageStudentsScreenState();
}

class _ManageStudentsScreenState extends State<ManageStudentsScreen> {
  SemRef get sem => widget.sem;
  String get semLabel => widget.semLabel;

  // Bulk delete: tap the sweep icon, tick students (or Select all), then Delete.
  bool _selecting = false;
  final Set<String> _selected = {};
  List<String> _allKeys = const [];

  void _toggleSelect(String key) {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  Future<void> _bulkDelete(BuildContext context) async {
    final keys = _selected.toList();
    if (keys.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${keys.length} student${keys.length == 1 ? '' : 's'}?'),
        content: Text(
            'They will be removed from $semLabel ${sem.section}.'
            '${AppSession.isAdmin ? ' Their student logins (ID and key) will be deleted too.' : ''}'
            ' This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: kAbsent))),
        ],
      ),
    );
    if (ok != true) return;

    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    final commits = <Future<void>>[];
    for (final k in keys) {
      batch.delete(sem.students.doc(k));
      unawaited(LocalDb.deleteStudent(sem, k));
      if (++ops >= 400) {
        commits.add(batch.commit());
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    if (ops > 0) commits.add(batch.commit());
    final res = await fsWriteAll(commits, what: 'bulk delete students');
    if (res == SaveResult.saved) {
      unawaited(LocalDb.refreshSemesterStudents(sem));
    }
    var logins = 0;
    if (res == SaveResult.saved && AppSession.isAdmin) {
      try {
        logins = await deleteStudentLoginsFor(sem, keys.toSet());
      } catch (e) {
        debugPrint('bulk delete logins failed: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    if (res == SaveResult.failed) {
      showSnack(this.context, 'Could not delete on the server. Please try again.',
          color: kAbsent);
    } else {
      showSnack(
          this.context,
          '${keys.length} student${keys.length == 1 ? '' : 's'} deleted'
          '${logins > 0 ? ' • $logins login${logins == 1 ? '' : 's'} removed' : ''}');
    }
  }

  void _showStudentDialog(BuildContext context,
      {String? existingRoll, String? existingName, String? existingFather}) {
    final rollController =
        TextEditingController(text: rollOf(existingRoll ?? ''));
    final nameController = TextEditingController(text: existingName ?? '');
    final fatherController = TextEditingController(text: existingFather ?? '');
    bool isEditing = existingRoll != null;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Edit Student' : 'Add Student'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rollController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Roll Number'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Student Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fatherController,
                decoration: const InputDecoration(labelText: 'Father Name'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final roll = rollController.text.trim();
              final name = nameController.text.trim();
              final father =
                  fatherController.text.replaceAll(RegExp(r'\s+'), ' ').trim();
              if (roll.isEmpty || name.isEmpty) return;

              // Roll number changed: move the student and all attendance to the new roll.
              if (existingRoll != null && roll != rollOf(existingRoll)) {
                Navigator.pop(dialogContext);
                await _changeRoll(context, existingRoll, roll, name, father);
                return;
              }

              // Edit: same student (existingRoll is its key). Add: if the roll exists, a new
              // unique key is created so the old student isn't overwritten.
              String key = existingRoll ?? roll;
              if (!isEditing) {
                final existing = await loadSemesterStudents(sem);
                key = uniqueStudentKey(roll, existing.map((s) => (s['roll'] ?? '')));
              }
              // The write is created first, so the list updates at once from the
              // local cache; SQLite is updated immediately too.
              final write = sem.students
                  .doc(key)
                  .set({'roll': key, 'name': name, 'father': father});
              unawaited(LocalDb.upsertStudent(sem, key, name, father));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              final res = await fsWrite(write, what: 'student');
              await finishStudentWrite(context.mounted ? context : null, sem, res);
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeRoll(
      BuildContext context, String oldKey, String newRoll, String name,
      [String father = '']) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    String? err;
    try {
      await changeStudentRoll(sem, oldKey, newRoll, name, father);
    } on RenameException catch (e) {
      err = e.message;
    } catch (_) {
      err = 'Could not change the roll number. Please check your internet and try again.';
    }
    if (!context.mounted) return;
    Navigator.pop(context); // close the progress dialog
    showSnack(context, err ?? 'Roll number changed to $newRoll');
  }

  Future<void> _showCopyDialog(BuildContext context) async {
    final labels = await loadSemesterLabels(sem.deptId, sem.section);
    final semIds = await loadSemesterIds(sem.deptId, sem.section);
    if (!context.mounted) return;
    String? target;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Copy students to…'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'All students of $semLabel ${sem.section} will be copied. '
                  'They stay in this semester too, and nothing in the other '
                  'semester is overwritten.',
                  style: const TextStyle(color: kMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                for (final id in semIds)
                  if (id != sem.semester)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(labels[id] ?? defaultSemesterLabel(id)),
                      trailing: target == id
                          ? const Icon(Icons.check_circle, color: kAccent)
                          : const Icon(Icons.circle_outlined, color: kMuted),
                      onTap: () => setLocal(() => target = id),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  target == null ? null : () => Navigator.pop(dialogContext, target),
              child: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final res = await copyStudentsToSemester(
        sem, SemRef(sem.deptId, sem.section, chosen));
    if (!context.mounted) return;
    final count = res.copied;
    final destLabel = labels[chosen] ?? defaultSemesterLabel(chosen);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count == 0
          ? 'No students to copy.'
          : '$count student${count == 1 ? '' : 's'} copied to $destLabel'
              '${res.logins > 0 ? ' • ${res.logins} login${res.logins == 1 ? '' : 's'} moved along' : ''}'),
    ));
  }

  Future<void> _importStudents(BuildContext context) async {
    final list = await pickStudentsFromFile(context);
    if (list == null || !context.mounted) return;
    final existing = await loadSemesterStudents(sem);
    if (!context.mounted) return;
    final plan = planStudentImport(list, existing);
    final decision = await confirmStudentImportPlan(
        context, plan, '$semLabel ${sem.section}', existing);
    if (decision == null) return;

    final byKey = {for (final s in existing) (s['roll'] ?? ''): s};
    final taken = existing.map((s) => (s['roll'] ?? '')).toSet();
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    final commits = <Future<void>>[];
    void flushIfFull() {
      if (++ops >= 400) {
        commits.add(batch.commit());
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }

    // 1) Existing students: only the father name is filled (no duplicates).
    final fatherWrites = <MapEntry<String, String>>[
      ...plan.fills,
      if (decision.overwrite)
        for (final c in plan.conflicts) MapEntry(c.key, c.newFather),
    ];
    for (final w in fatherWrites) {
      final name = byKey[w.key]?['name'] ?? '';
      batch.set(sem.students.doc(w.key), {'father': w.value},
          SetOptions(merge: true));
      unawaited(LocalDb.upsertStudent(sem, w.key, name, w.value));
      flushIfFull();
    }

    // 2) New students: roll numbers follow file order from the chosen start.
    for (var i = 0; i < plan.newOnes.length; i++) {
      // If the roll exists, a new unique key is created; nothing is overwritten.
      final key = uniqueStudentKey((decision.start + i).toString(), taken);
      taken.add(key);
      final s = plan.newOnes[i];
      batch.set(sem.students.doc(key),
          {'roll': key, 'name': s.name, 'father': s.father});
      unawaited(LocalDb.upsertStudent(sem, key, s.name, s.father));
      flushIfFull();
    }
    if (ops > 0) commits.add(batch.commit());
    if (!context.mounted) return;

    final skipped = decision.overwrite ? 0 : plan.conflicts.length;
    final parts = <String>[
      '${fatherWrites.length} father name${fatherWrites.length == 1 ? '' : 's'} filled',
      '${plan.newOnes.length} new student${plan.newOnes.length == 1 ? '' : 's'} added',
      if (skipped > 0) '$skipped skipped (different father name)',
    ];
    _importSnack(context, parts.join(', '));

    // Online: wait for the server, then refresh SQLite from it. A failure is shown.
    final res = await fsWriteAll(commits, what: 'student import');
    await finishStudentWrite(context.mounted ? context : null, sem, res);
  }

  void _confirmDeleteStudent(BuildContext context, String roll, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student?'),
        content: Text('Delete $name (Roll ${rollOf(roll)})? This will remove them from all subjects of this semester.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final write = sem.students.doc(roll).delete();
              unawaited(LocalDb.deleteStudent(sem, roll));
              final res = await fsWrite(write, what: 'delete student');
              if (res == SaveResult.saved) {
                unawaited(LocalDb.refreshSemesterStudents(sem));
                if (AppSession.isAdmin) {
                  unawaited(deleteStudentLoginsFor(sem, {roll}).then((_) {},
                      onError: (Object e) =>
                          debugPrint('delete student login failed: $e')));
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: headerAppBar(
        title: 'Students',
        subtitle: '$semLabel • Section ${sem.section}',
        actions: [
          HeaderTile(
            icon: Icons.upload_file_outlined,
            tooltip: 'Import students (Excel / CSV)',
            onTap: () => _importStudents(context),
          ),
          HeaderTile(
            icon: Icons.copy_all_outlined,
            tooltip: 'Copy students to another semester',
            onTap: () => _showCopyDialog(context),
          ),
          HeaderTile(
            icon: _selecting ? Icons.close : Icons.delete_sweep_outlined,
            tooltip: _selecting ? 'Cancel' : 'Delete many students',
            onTap: () => setState(() {
              _selecting = !_selecting;
              _selected.clear();
            }),
          ),
          if (AppSession.isAdmin)
            HeaderTile(
              icon: Icons.vpn_key_outlined,
              tooltip: 'Student logins',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        StudentLoginsScreen(
                            sem: sem,
                            semLabel: semLabel,
                            deptName: widget.deptName)),
              ),
            ),
        ],
      ),
      floatingActionButton: _selecting
          ? null
          : GradFab(
              icon: Icons.person_add_alt_1,
              onPressed: () => _showStudentDialog(context),
            ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          if (_selected.length == _allKeys.length) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(_allKeys);
                          }
                        }),
                        child: Text(_selected.length == _allKeys.length &&
                                _allKeys.isNotEmpty
                            ? 'Clear all'
                            : 'Select all'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kAbsent,
                            foregroundColor: Colors.white),
                        onPressed: _selected.isEmpty
                            ? null
                            : () => _bulkDelete(context),
                        child: Text('Delete (${_selected.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: liveQuery(sem.students),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const EmptyState(
                icon: Icons.groups_outlined,
                text: 'No students yet. Tap + to add.');
          }

          final docs = snapshot.data!.docs.toList();
          docs.sort((a, b) => compareStudentKeys(
              (a.data()['roll'] ?? a.id).toString(),
              (b.data()['roll'] ?? b.id).toString()));
          _allKeys =
              docs.map((d) => (d.data()['roll'] ?? d.id).toString()).toList();

          return ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 90),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final roll = (data['roll'] ?? docs[index].id).toString();
              final name = (data['name'] ?? '').toString();
              final father = (data['father'] ?? '').toString();

              return AppCard(
 float: false,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    RollBadge(roll: roll),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _selecting ? () => _toggleSelect(roll) : null,
                        child: StudentNameBlock(name: name, father: father),
                      ),
                    ),
                    if (_selecting)
                      Checkbox(
                        value: _selected.contains(roll),
                        activeColor: kAccent,
                        onChanged: (_) => _toggleSelect(roll),
                      )
                    else ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: kAccent),
                        onPressed: () => _showStudentDialog(context,
                            existingRoll: roll,
                            existingName: name,
                            existingFather: father),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: kAbsent),
                        onPressed: () =>
                            _confirmDeleteStudent(context, roll, name),
                      ),
                    ],
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

// Student name with the father name as a smaller muted line under it.
// Old students without a father name show just the name.
class StudentNameBlock extends StatelessWidget {
  final String name;
  final String father;
  final Color? color;
  final String? extra; // optional extra line (e.g. attendance percentage)
  final Color? extraColor;
  const StudentNameBlock({
    super.key,
    required this.name,
    this.father = '',
    this.color,
    this.extra,
    this.extraColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
            style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        if (father.trim().isNotEmpty)
          Text('F/N ${father.trim()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: kMuted)),
        if (extra != null)
          Text(extra!,
              style: TextStyle(fontSize: 12.5, color: extraColor ?? kMuted)),
      ],
    );
  }
}

class RollBadge extends StatelessWidget {
  final String roll;
  const RollBadge({super.key, required this.roll});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 40),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(rollOf(roll),
          style: const TextStyle(
              color: kAccent, fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }
}

// Subject students (add / "remove" for this subject only)
// Soft remove: the student stays in the admin's master list and is only hidden here.
class SubjectStudentsScreen extends StatefulWidget {
  final SemRef sem;
  final String subjectName;
  const SubjectStudentsScreen(
      {super.key, required this.sem, required this.subjectName});

  @override
  State<SubjectStudentsScreen> createState() => _SubjectStudentsScreenState();
}

class _SubjectStudentsScreenState extends State<SubjectStudentsScreen> {
  bool _loading = true;
  Map<String, String> _master = {};
  Map<String, String> _masterFather = {};
  // roll -> {'name': ..., 'father': ..., 'kind': 'extra' | 'hidden'}
  Map<String, Map<String, String>> _overrides = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final masterF = loadSemesterStudents(widget.sem);
      final ovF = loadOverrides(widget.sem, widget.subjectName);
      final master = await masterF;
      _overrides = await ovF;
      _master = {for (final s in master) (s['roll'] ?? ''): (s['name'] ?? '')};
      _masterFather = {for (final s in master) (s['roll'] ?? ''): s['father'] ?? ''};
    } catch (e) {
      debugPrint('Subject students load error: $e');
    }
    if (mounted) setState(() => _loading = false);
    // Online: bring SQLite in line with Firebase for this subject.
    unawaited(LocalDb.refreshSemesterStudents(widget.sem));
    unawaited(LocalDb.refreshSubjectOverrides(widget.sem, widget.subjectName));
  }

  Map<String, String> get _effective {
    final m = Map<String, String>.from(_master);
    _overrides.forEach((roll, o) {
      if (o['kind'] == 'hidden') {
        m.remove(roll);
      } else if (o['kind'] == 'extra') {
        m[roll] = o['name'] ?? '';
      }
    });
    return m;
  }

  Map<String, String> get _effectiveFather {
    final m = Map<String, String>.from(_masterFather);
    _overrides.forEach((roll, o) {
      if (o['kind'] == 'hidden') {
        m.remove(roll);
      } else if (o['kind'] == 'extra') {
        m[roll] = o['father'] ?? '';
      }
    });
    return m;
  }

  void _addStudent() {
    final rollController = TextEditingController();
    final nameController = TextEditingController();
    final fatherController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add student to this subject'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rollController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Roll Number'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Student Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fatherController,
                decoration: const InputDecoration(labelText: 'Father Name'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final typedRoll = rollController.text.trim();
              final name = nameController.text.trim();
              final father =
                  fatherController.text.replaceAll(RegExp(r'\s+'), ' ').trim();
              if (typedRoll.isEmpty || name.isEmpty) return;
              // If the roll already exists (master / extra / hidden), create a unique key.
              final roll = uniqueStudentKey(
                  typedRoll, [..._master.keys, ..._overrides.keys]);
              final sem = widget.sem;
              final sub = widget.subjectName;
              final write = sem.overrides(sub).doc(roll).set({
                'roll': roll,
                'name': name,
                'father': father,
                'kind': 'extra',
              });
              unawaited(
                  LocalDb.upsertOverride(sem, sub, roll, name, 'extra', father));
              setState(() => _overrides[roll] =
                  {'name': name, 'father': father, 'kind': 'extra'});
              Navigator.pop(dialogContext);
              final res = await fsWrite(write, what: 'subject student');
              if (res == SaveResult.saved) {
                unawaited(refreshSubjectSummary(sem, sub));
              }
              if (!mounted) return;
              await finishStudentWrite(context, sem, res, subject: sub);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _importStudents() async {
    final list = await pickStudentsFromFile(context);
    if (list == null || !mounted) return;
    final taken = {..._master.keys, ..._overrides.keys};
    // Students already in this subject: match by name so father names get
    // filled for them too, and only really new names are added.
    final eff = _effective;
    final effFather = _effectiveFather;
    final inSubject = [
      for (final e in eff.entries)
        {'roll': e.key, 'name': e.value, 'father': effFather[e.key] ?? ''}
    ];
    final plan = planStudentImport(list, inSubject);
    final decision = await confirmStudentImportPlan(
        context,
        plan,
        '${widget.subjectName} (this subject)',
        [for (final k in taken) {'roll': k, 'name': ''}]);
    if (decision == null || !mounted) return;
    final start = decision.start;

    final sem = widget.sem;
    final sub = widget.subjectName;
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    final commits = <Future<void>>[];
    void flushIfFull() {
      if (++ops >= 400) {
        commits.add(batch.commit());
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }

    final added = <String, Map<String, String>>{};
    // Students of the master list that get a NEW father name: the father name is
    // also saved on the master student (students collection), in its own batch
    // so a permission problem there never blocks the subject changes.
    final masterFills = <MapEntry<String, String>>[
      for (final w in plan.fills)
        if (_master.containsKey(w.key)) w
    ];

    // 1) Existing students: only the father name is filled (this subject only).
    final fatherWrites = <MapEntry<String, String>>[
      ...plan.fills,
      if (decision.overwrite)
        for (final c in plan.conflicts) MapEntry(c.key, c.newFather),
    ];
    for (final w in fatherWrites) {
      final name = eff[w.key] ?? '';
      batch.set(sem.overrides(sub).doc(w.key), {
        'roll': w.key,
        'name': name,
        'father': w.value,
        'kind': 'extra',
      });
      unawaited(
          LocalDb.upsertOverride(sem, sub, w.key, name, 'extra', w.value));
      added[w.key] = {'name': name, 'father': w.value, 'kind': 'extra'};
      flushIfFull();
    }
    final masterCommits = <Future<void>>[];
    for (var i = 0; i < masterFills.length; i += 400) {
      final mb = FirebaseFirestore.instance.batch();
      for (final w in masterFills.skip(i).take(400)) {
        mb.set(sem.students.doc(w.key), {'father': w.value},
            SetOptions(merge: true));
        unawaited(LocalDb.upsertStudent(sem, w.key, _master[w.key] ?? '', w.value));
        _masterFather[w.key] = w.value;
      }
      masterCommits.add(mb.commit());
    }

    // 2) New students: roll numbers follow file order from the chosen start.
    for (var i = 0; i < plan.newOnes.length; i++) {
      final st = plan.newOnes[i];
      final key = uniqueStudentKey((start + i).toString(), taken);
      taken.add(key);
      batch.set(sem.overrides(sub).doc(key), {
        'roll': key,
        'name': st.name,
        'father': st.father,
        'kind': 'extra',
      });
      unawaited(
          LocalDb.upsertOverride(sem, sub, key, st.name, 'extra', st.father));
      added[key] = {'name': st.name, 'father': st.father, 'kind': 'extra'};
      flushIfFull();
    }
    if (ops > 0) commits.add(batch.commit());
    if (!mounted) return;
    setState(() => _overrides.addAll(added));

    final n = plan.newOnes.length;
    final skipped = decision.overwrite ? 0 : plan.conflicts.length;
    final parts = <String>[
      '${fatherWrites.length} father name${fatherWrites.length == 1 ? '' : 's'} filled',
      '$n new student${n == 1 ? '' : 's'} added',
      if (skipped > 0) '$skipped skipped (different father name)',
    ];
    _importSnack(context, parts.join(', '));

    final res = await fsWriteAll(commits, what: 'subject import');
    final masterRes = await fsWriteAll(masterCommits, what: 'master father fill');
    if (!mounted) return;
    await finishStudentWrite(
        context, sem, res == SaveResult.saved ? masterRes : res,
        subject: sub);
    if (res == SaveResult.saved) {
      await LocalDb.refreshSubjectOverrides(sem, sub);
    }
  }

  void _removeStudent(String roll, String name) {
    final father = _effectiveFather[roll] ?? '';
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from this subject?'),
        content: Text(
            "$name (Roll ${rollOf(roll)}) will only be removed from this subject's list. They will remain in the admin's master list, and existing attendance history stays safe."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final sem = widget.sem;
              final sub = widget.subjectName;
              dropSubjectFromSummary(sem, sub, roll);
              if (_master.containsKey(roll)) {
                // Student from the master list: add a "hidden" marker
                unawaited(fsWrite(
                        sem.overrides(sub).doc(roll).set({
                          'roll': roll,
                          'name': name,
                          'father': father,
                          'kind': 'hidden',
                        }),
                        what: 'hide student')
                    .then((r) {
                  if (r == SaveResult.saved) {
                    unawaited(LocalDb.refreshSubjectOverrides(sem, sub));
                  }
                }));
                unawaited(
                    LocalDb.upsertOverride(sem, sub, roll, name, 'hidden', father));
                setState(() => _overrides[roll] =
                    {'name': name, 'father': father, 'kind': 'hidden'});
              } else {
                // Student added only to this subject: remove the override
                unawaited(fsWrite(sem.overrides(sub).doc(roll).delete(),
                        what: 'remove student')
                    .then((r) {
                  if (r == SaveResult.saved) {
                    unawaited(LocalDb.refreshSubjectOverrides(sem, sub));
                  }
                }));
                unawaited(LocalDb.deleteOverride(sem, sub, roll));
                setState(() => _overrides.remove(roll));
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Remove', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _sortedStudents(_effective, _effectiveFather);
    return Scaffold(
      appBar: headerAppBar(
        title: widget.subjectName,
        subtitle: 'Students of this subject',
        actions: [
          HeaderTile(
            icon: Icons.upload_file_outlined,
            tooltip: 'Import students (Excel / CSV)',
            onTap: _importStudents,
          ),
        ],
      ),
      floatingActionButton: GradFab(
        icon: Icons.person_add_alt_1,
        onPressed: _addStudent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const InfoBanner(
                  text:
                      "This list is specific to this subject. Removing a student here does not delete them from the admin's master list.",
                ),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyState(
                          icon: Icons.groups_outlined,
                          text: 'No students in this subject.')
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 6, bottom: 90),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final s = list[i];
                            return AppCard(
 float: false,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                              child: Row(
                                children: [
                                  RollBadge(roll: (s['roll'] ?? '')),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StudentNameBlock(
                                        name: (s['name'] ?? ''),
                                        father: s['father'] ?? ''),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.person_remove_outlined,
                                        color: kAbsent),
                                    tooltip: 'Remove from this subject',
                                    onPressed: () =>
                                        _removeStudent(s['roll'] ?? '', (s['name'] ?? '')),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// Time picker (6:00 AM to 6:00 PM only)
// Flutter's picker can't limit the range, so this is a small custom dialog:
// 6 AM to 6 PM, with only :00 at 6 PM.
Future<TimeOfDay?> pickClassTime(BuildContext context, TimeOfDay? initial) {
  int hour = (initial?.hour ?? 9).clamp(kPickerStartHour, kPickerEndHour).toInt();
  int minute = initial?.minute ?? 0;
  if (hour == kPickerEndHour) minute = 0;

  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final maxMinute = hour == kPickerEndHour ? 0 : 59;
        return AlertDialog(
          title: const Text('Select class time'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: hour,
                items: [
                  for (int h = kPickerStartHour; h <= kPickerEndHour; h++)
                    DropdownMenuItem(
                      value: h,
                      child: Text(DateFormat('hh a').format(DateTime(2000, 1, 1, h))),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() {
                    hour = v;
                    if (hour == kPickerEndHour) minute = 0;
                  });
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(':', style: TextStyle(fontSize: 20)),
              ),
              DropdownButton<int>(
                value: minute > maxMinute ? 0 : minute,
                items: [
                  for (int m = 0; m <= maxMinute; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => minute = v);
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
              onPressed: () =>
                  Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
              child: const Text('OK'),
            ),
          ],
        );
      },
    ),
  );
}
