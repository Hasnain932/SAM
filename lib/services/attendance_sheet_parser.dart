part of '../main.dart';

// Understands any attendance sheet layout.

// parseAttendanceSheet (works with any layout)
// Detects the layout itself and uses the one with the most P/A entries:
//   1) WIDE: dates in one row, names in one column
//   2) TRANSPOSED: dates in one column, names in the top row
//   3) LONG: each row = Date | Name | Status (any column order)
// Column order, extra columns and status wording don't matter.
class _ImportHeader {
  final int row;
  final Map<int, DateTime> dates;
  _ImportHeader(this.row, this.dates);
}

class _ImportDraft {
  final List<ImportColumn> columns;
  final List<ImportRow> rows;
  _ImportDraft(this.columns, this.rows);
  int get score {
    var n = 0;
    for (final r in rows) {
      n += r.status.length;
    }
    return n;
  }
}

class _ImportLongRec {
  final String name;
  final String roll;
  final DateTime date;
  final int sess;
  final String status;
  _ImportLongRec(this.name, this.roll, this.date, this.sess, this.status);
}

final RegExp _importSessionRe = RegExp(
    r'(?:session|lecture|lec|class|period|slot)\s*#?\s*[-:]?\s*(\d+)',
    caseSensitive: false);

final RegExp _importSkipNameRe = RegExp(
    r'^(time|total|totals|session|date|name|names|percentage|percent|present|absent|average|avg|summary|signature|sign|sr|sno|roll|remarks?|day|month|week|subject|faculty|teacher)\b',
    caseSensitive: false);

bool _importIsNameHeader(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return false;
  if (RegExp(r'father|mother|parent|guardian').hasMatch(t)) return false;
  return t == 'student' || t == 'naam' || t.contains('name');
}

bool _importIsRollHeader(String raw) {
  final t = raw.trim().toLowerCase();
  return t.contains('roll') ||
      t.startsWith('reg') ||
      t.contains('enrol') ||
      t.contains('admission');
}

// "1. Ali Khan" / "01 Ali Khan" -> "Ali Khan"
String _importCleanName(String raw) {
  final s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final stripped =
      s.replaceFirst(RegExp(r'^\d+\s*[.)\-:]\s*|^\d+\s+(?=\p{L})', unicode: true), '');
  return _importLetterRe.hasMatch(stripped) ? stripped.trim() : s;
}

List<List<String>> _importPad(List<List<String>> rows) {
  var w = 0;
  for (final r in rows) {
    if (r.length > w) w = r.length;
  }
  return [
    for (final r in rows)
      [for (var c = 0; c < w; c++) c < r.length ? r[c].trim() : '']
  ];
}

List<List<String>> _importTranspose(List<List<String>> g) {
  if (g.isEmpty) return g;
  final nC = g[0].length;
  return [
    for (var c = 0; c < nC; c++) [for (var r = 0; r < g.length; r++) g[r][c]]
  ];
}

_ImportHeader? _importHeaderFromRow(List<List<String>> g, int r) {
  final dates = <int, DateTime>{};
  for (var c = 0; c < g[r].length; c++) {
    final d = _parseImportDate(g[r][c]);
    if (d != null) dates[c] = d;
  }
  return dates.isEmpty ? null : _ImportHeader(r, dates);
}

// Gets [year, month] from the title or header (e.g. "September 2025", "09/2025").
List<int>? _importFindMonthYear(List<List<String>> g, int upToRow) {
  final monthRe = RegExp(
      r"\b(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)\b(?:[\s,.\-/']*(20\d{2}))?",
      caseSensitive: false);
  final mYRe = RegExp(r'\b(\d{1,2})\s*[/\-.]\s*(20\d{2})\b');
  final yMRe = RegExp(r'\b(20\d{2})\s*[-/.]\s*(\d{1,2})\b');
  final yearRe = RegExp(r'\b(20\d{2})\b');
  int? looseYear;
  for (var r = 0; r <= upToRow && r < g.length; r++) {
    for (final t in g[r]) {
      if (t.isEmpty) continue;
      looseYear ??= int.tryParse(yearRe.firstMatch(t)?.group(1) ?? '');
    }
  }
  for (var r = 0; r <= upToRow && r < g.length; r++) {
    for (final t in g[r]) {
      if (t.isEmpty) continue;
      var m = monthRe.firstMatch(t);
      if (m != null) {
        final mon = _kImportMonths[m.group(1)!.toLowerCase().substring(0, 3)];
        if (mon != null) {
          final y = int.tryParse(m.group(2) ?? '') ??
              looseYear ??
              DateTime.now().year;
          return [y, mon];
        }
      }
      m = mYRe.firstMatch(t);
      if (m != null) {
        final mon = int.parse(m.group(1)!);
        if (mon >= 1 && mon <= 12) return [int.parse(m.group(2)!), mon];
      }
      m = yMRe.firstMatch(t);
      if (m != null) {
        final mon = int.parse(m.group(2)!);
        if (mon >= 1 && mon <= 12) return [int.parse(m.group(1)!), mon];
      }
      final d = _parseImportDate(t);
      if (d != null) return [d.year, d.month];
    }
  }
  return null;
}

// A header row with only day numbers (1 2 3 ... 31), with month and year above it.
_ImportHeader? _importDayNumberHeader(List<List<String>> g, int limit) {
  final dayRe = RegExp(r'^(\d{1,2})$');
  for (var r = 0; r < limit; r++) {
    final cols = <int>[];
    final nums = <int>[];
    for (var c = 0; c < g[r].length; c++) {
      final m = dayRe.firstMatch(g[r][c]);
      if (m == null) continue;
      final v = int.parse(m.group(1)!);
      if (v >= 1 && v <= 31) {
        cols.add(c);
        nums.add(v);
      }
    }
    if (cols.length < 5) continue;
    var inc = 0;
    for (var i = 1; i < nums.length; i++) {
      if (nums[i] > nums[i - 1]) inc++;
    }
    if (inc < (nums.length - 1) * 0.7) continue;
    final my = _importFindMonthYear(g, r);
    if (my == null) continue;
    final dates = <int, DateTime>{};
    for (var i = 0; i < cols.length; i++) {
      final d = _importMakeDate(my[0], my[1], nums[i]);
      if (d != null) dates[cols[i]] = d;
    }
    if (dates.length >= 2) return _ImportHeader(r, dates);
  }
  return null;
}

_ImportHeader? _importFindDateHeader(List<List<String>> g) {
  final nR = g.length;
  final limit = nR < 40 ? nR : 40;
  var bestRow = -1;
  var bestCnt = 0;
  for (var r = 0; r < limit; r++) {
    var cnt = 0;
    for (final t in g[r]) {
      if (_parseImportDate(t) != null) cnt++;
    }
    if (cnt > bestCnt) {
      bestCnt = cnt;
      bestRow = r;
    }
  }
  if (bestCnt >= 2) return _importHeaderFromRow(g, bestRow);
  final alt = _importDayNumberHeader(g, limit);
  if (alt != null) return alt;
  if (bestCnt == 1) return _importHeaderFromRow(g, bestRow);
  return null;
}

// ---- Layout 1: dates on top, names on the left (or anywhere) ----
_ImportDraft? _importParseWide(List<List<String>> g) {
  final nR = g.length;
  final nC = nR == 0 ? 0 : g[0].length;
  if (nR < 2 || nC < 2) return null;
  String cell(int r, int c) =>
      (r >= 0 && r < nR && c >= 0 && c < nC) ? g[r][c] : '';

  final hdr = _importFindDateHeader(g);
  if (hdr == null) return null;
  final dateRow = hdr.row;
  final dates = hdr.dates;
  final dateKeys = dates.keys.toList()..sort();
  final firstDateCol = dateKeys.first;

  // Name column: the one with 'name' in its header, else the one with the most text.
  var nameCol = -1;
  var bestScore = 0.0;
  for (var c = 0; c < nC; c++) {
    if (dates.containsKey(c)) continue;
    var bonus = 0.0;
    for (var r = 0; r <= dateRow + 2 && r < nR; r++) {
      if (_importIsNameHeader(cell(r, c))) {
        bonus = 1000000.0;
        break;
      }
    }
    var txt = 0, stat = 0, filled = 0;
    for (var r = dateRow + 1; r < nR; r++) {
      final t = cell(r, c);
      if (t.isEmpty) continue;
      filled++;
      if (_parseImportStatus(t) != null) {
        stat++;
        continue;
      }
      if (!_importLetterRe.hasMatch(t) || _parseImportDate(t) != null) continue;
      txt += t.length > 40 ? 40 : t.length;
    }
    if (txt == 0 || stat * 2 > filled) continue;
    var score = txt.toDouble();
    if (c > firstDateCol) score *= 0.5;
    score += bonus;
    if (score > bestScore) {
      bestScore = score;
      nameCol = c;
    }
  }
  if (nameCol < 0) return null;

  // Roll column: only if the header has roll / reg / enrol / admission.
  var rollCol = -1;
  for (var c = 0; c < nC && rollCol < 0; c++) {
    if (c == nameCol || dates.containsKey(c)) continue;
    for (var r = 0; r <= dateRow + 2 && r < nR; r++) {
      if (_importIsRollHeader(cell(r, c))) {
        rollCol = c;
        break;
      }
    }
  }

  // Student rows
  final nameRows = <int>[];
  final names = <int, String>{};
  for (var r = dateRow + 1; r < nR; r++) {
    final name = _importCleanName(cell(r, nameCol));
    if (name.isEmpty || !_importLetterRe.hasMatch(name)) continue;
    if (_importSkipNameRe.hasMatch(name)) continue;
    if (_parseImportStatus(name) != null || _parseImportDate(name) != null) {
      continue;
    }
    nameRows.add(r);
    names[r] = name;
  }
  if (nameRows.isEmpty) return null;

  // Merged date header (several sessions under one date): the blank header cells
  // after it that have P/A belong to the same date.
  final colDate = Map<int, DateTime>.from(dates);
  for (final c in dateKeys) {
    for (var k = c + 1; k < nC; k++) {
      if (dates.containsKey(k) || k == nameCol || k == rollCol) break;
      if (cell(dateRow, k).isNotEmpty) break;
      var hits = 0;
      for (final r in nameRows) {
        if (_parseImportStatus(cell(r, k)) != null) hits++;
      }
      if (hits == 0 || hits * 2 < nameRows.length) break;
      colDate[k] = dates[c]!;
    }
  }

  // Session numbers: use "Session 2" from the header, else count 1, 2, 3 for repeated dates.
  final allCols = colDate.keys.toList()..sort();
  final used = <String>{};
  final counter = <String, int>{};
  final columns = <ImportColumn>[];
  for (final c in allCols) {
    final d = colDate[c]!;
    final dayKey = DateFormat('yyyy-MM-dd').format(d);
    int? hint;
    for (final rr in [dateRow + 1, dateRow - 1]) {
      if (names.containsKey(rr)) continue;
      final sm = _importSessionRe.firstMatch(cell(rr, c));
      if (sm != null) {
        hint = int.tryParse(sm.group(1) ?? '');
        break;
      }
    }
    var sess = hint ?? ((counter[dayKey] ?? 0) + 1);
    while (used.contains('${dayKey}_$sess')) {
      sess++;
    }
    used.add('${dayKey}_$sess');
    counter[dayKey] = sess;
    // Files exported by this app have a small "Lab" cell above lab columns.
    var lab = false;
    for (var rr = dateRow - 1; rr >= 0 && rr >= dateRow - 3; rr--) {
      final t = cell(rr, c).trim().toLowerCase();
      if (t == 'lab' || t == 'lab class') {
        lab = true;
        break;
      }
    }
    columns.add(ImportColumn(c, d, sess, isLab: lab));
  }

  final outRows = <ImportRow>[];
  for (final r in nameRows) {
    final st = <int, String>{};
    for (final col in columns) {
      final v = _parseImportStatus(cell(r, col.col));
      if (v != null) st[col.col] = v;
    }
    if (st.isEmpty) continue;
    outRows.add(ImportRow(names[r]!, rollCol >= 0 ? cell(r, rollCol) : '', st));
  }
  if (outRows.isEmpty) return null;

  final usedCols = <int>{for (final row in outRows) ...row.status.keys};
  final keepCols = columns.where((c) => usedCols.contains(c.col)).toList();
  if (keepCols.isEmpty) return null;
  return _ImportDraft(keepCols, outRows);
}

// ---- Layout 3: each row = Date | Name | Status ----
_ImportDraft? _importParseLong(List<List<String>> g) {
  final nR = g.length;
  final nC = nR == 0 ? 0 : g[0].length;
  if (nR < 3 || nC < 3) return null;

  final dateCnt = List<int>.filled(nC, 0);
  final statCnt = List<int>.filled(nC, 0);
  for (var r = 0; r < nR; r++) {
    for (var c = 0; c < nC; c++) {
      final t = g[r][c];
      if (t.isEmpty) continue;
      if (_parseImportStatus(t) != null) {
        statCnt[c]++;
      } else if (_parseImportDate(t) != null) {
        dateCnt[c]++;
      }
    }
  }
  int argmax(List<int> v, int skip1, int skip2) {
    var bi = -1, bv = 1; // at least 2
    for (var c = 0; c < v.length; c++) {
      if (c == skip1 || c == skip2) continue;
      if (v[c] > bv) {
        bv = v[c];
        bi = c;
      }
    }
    return bi;
  }

  final dateCol = argmax(dateCnt, -1, -1);
  final statusCol = argmax(statCnt, dateCol, -1);
  if (dateCol < 0 || statusCol < 0) return null;

  bool headerHas(int c, bool Function(String) test) {
    for (var r = 0; r < nR && r < 10; r++) {
      if (test(g[r][c])) return true;
    }
    return false;
  }

  var nameCol = -1;
  var bestScore = 0.0;
  for (var c = 0; c < nC; c++) {
    if (c == dateCol || c == statusCol) continue;
    var txt = 0;
    for (var r = 0; r < nR; r++) {
      final t = g[r][c];
      if (t.isEmpty || !_importLetterRe.hasMatch(t)) continue;
      if (_parseImportStatus(t) != null || _parseImportDate(t) != null) continue;
      txt += t.length > 40 ? 40 : t.length;
    }
    if (txt == 0) continue;
    var score = txt.toDouble();
    if (headerHas(c, _importIsNameHeader)) score += 1000000.0;
    if (score > bestScore) {
      bestScore = score;
      nameCol = c;
    }
  }
  if (nameCol < 0) return null;

  var rollCol = -1;
  var sessCol = -1;
  final sessHeaderRe = RegExp(r'session|lecture|period|slot', caseSensitive: false);
  for (var c = 0; c < nC; c++) {
    if (c == dateCol || c == statusCol || c == nameCol) continue;
    if (rollCol < 0 && headerHas(c, _importIsRollHeader)) rollCol = c;
    if (sessCol < 0 && headerHas(c, (t) => sessHeaderRe.hasMatch(t))) sessCol = c;
  }

  final recs = <_ImportLongRec>[];
  final occ = <String, int>{};
  for (var r = 0; r < nR; r++) {
    final d = _parseImportDate(g[r][dateCol]);
    final st = _parseImportStatus(g[r][statusCol]);
    final name = _importCleanName(g[r][nameCol]);
    if (d == null || st == null) continue;
    if (name.isEmpty || !_importLetterRe.hasMatch(name)) continue;
    if (_importSkipNameRe.hasMatch(name)) continue;
    final dayKey = DateFormat('yyyy-MM-dd').format(d);
    final ok = '$dayKey|${_normImportName(name)}';
    final n = (occ[ok] ?? 0) + 1;
    occ[ok] = n;
    var sess = n;
    if (sessCol >= 0) {
      final sm = RegExp(r'\d+').firstMatch(g[r][sessCol]);
      final v = int.tryParse(sm?.group(0) ?? '');
      if (v != null && v > 0) sess = v;
    }
    recs.add(_ImportLongRec(
        name, rollCol >= 0 ? g[r][rollCol] : '', d, sess, st));
  }
  if (recs.isEmpty) return null;

  String keyOf(_ImportLongRec x) =>
      '${DateFormat('yyyy-MM-dd').format(x.date)}|${x.sess.toString().padLeft(4, '0')}';
  final keyRec = <String, _ImportLongRec>{};
  for (final x in recs) {
    keyRec.putIfAbsent(keyOf(x), () => x);
  }
  final sortedKeys = keyRec.keys.toList()..sort();
  final colId = <String, int>{};
  final columns = <ImportColumn>[];
  for (var i = 0; i < sortedKeys.length; i++) {
    final x = keyRec[sortedKeys[i]]!;
    colId[sortedKeys[i]] = i;
    columns.add(ImportColumn(i, x.date, x.sess));
  }

  final byName = <String, ImportRow>{};
  for (final x in recs) {
    final nk = _normImportName(x.name);
    final row =
        byName.putIfAbsent(nk, () => ImportRow(x.name, x.roll, <int, String>{}));
    row.status[colId[keyOf(x)]!] = x.status;
  }
  return _ImportDraft(columns, byName.values.toList());
}

ImportSheet? parseAttendanceSheet(List<List<String>> rows) {
  if (rows.isEmpty) return null;
  final grid = _importPad(rows);
  if (grid.isEmpty || grid[0].isEmpty) return null;
  _importDayFirst = _inferDayFirst(grid);
  final candidates = <_ImportDraft?>[
    _importParseWide(grid),
    _importParseWide(_importTranspose(grid)),
    _importParseLong(grid),
  ];
  _ImportDraft? best;
  for (final d in candidates) {
    if (d == null) continue;
    if (best == null || d.score > best.score) best = d;
  }
  if (best == null || best.rows.isEmpty || best.columns.isEmpty) return null;
  return ImportSheet(best.columns, best.rows);
}

String _normImportName(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _sortedImportName(String s) {
  final t = _normImportName(s).split(' ')..sort();
  return t.join(' ');
}

// Matches file names to app students. Only sure matches count (full name, same words
// in another order, or roll number); the rest are shown to the user.
Map<int, String> autoMatchImportRows(
    List<ImportRow> rows, List<Map<String, String>> students) {
  final result = <int, String>{};
  final taken = <String>{};

  void pass(bool Function(ImportRow row, Map<String, String> s) same) {
    for (var i = 0; i < rows.length; i++) {
      if (result.containsKey(i)) continue;
      for (final s in students) {
        final key = s['roll']!;
        if (taken.contains(key)) continue;
        if (same(rows[i], s)) {
          result[i] = key;
          taken.add(key);
          break;
        }
      }
    }
  }

  pass((r, s) => _normImportName(r.name) == _normImportName(s['name'] ?? ''));
  pass((r, s) =>
      _sortedImportName(r.name) == _sortedImportName(s['name'] ?? ''));
  pass((r, s) =>
      r.roll.isNotEmpty && r.roll.trim() == rollOf(s['roll']!).trim());
  return result;
}
