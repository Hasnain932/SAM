part of 'main.dart';

// Import old attendance (Excel .xlsx / CSV) into a subject's attendance
// Layout: dates in a row on top, names on the left, P / A under each date.
// Each date becomes one session record. Files exported by this app import directly.
class ImportColumn {
  final int col;
  final DateTime date;
  final int session;
  final bool isLab; // column has a "Lab" label above it
  ImportColumn(this.col, this.date, this.session, {this.isLab = false});
  String get docId =>
      '${DateFormat('yyyy-MM-dd').format(date)}_Session_$session';
}

class ImportRow {
  final String name;
  final String roll; // roll from the file (only if there is a 'Roll' column)
  final Map<int, String> status; // column index -> 'P' / 'A'
  final String father; // father name from the file ('' if there is no column)
  ImportRow(this.name, this.roll, this.status, [this.father = '']);
}

class ImportSheet {
  final List<ImportColumn> columns;
  final List<ImportRow> rows;
  ImportSheet(this.columns, this.rows);
}

class ImportPlan {
  final Map<int, String> rowToStudent; // file row index -> student key
  final Set<int> cols; // date columns to import
  final bool blankPresent; // blank cell = Present (otherwise Absent)
  ImportPlan(this.rowToStudent, this.cols, this.blankPresent);
}

const Map<String, int> _kImportMonths = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

DateTime? _importMakeDate(int y, int m, int d) {
  if (y < 100) y += 2000;
  if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  if (dt.month != m || dt.day != d) return null;
  return dt;
}

// true: 12/09/2025 means 12 Sep (day first); false: Dec 9. Set by parseAttendanceSheet.
bool _importDayFirst = true;

bool _inferDayFirst(List<List<String>> g) {
  var df = 0, mf = 0;
  final re = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$');
  for (final r in g) {
    for (final t in r) {
      final m = re.firstMatch(t.trim());
      if (m == null) continue;
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      if (a > 12 && b <= 12) {
        df++;
      } else if (b > 12 && a <= 12) {
        mf++;
      }
    }
  }
  return mf <= df;
}

// Reads a date from cell text. Numeric formats are day first (dd/mm/yyyy).
DateTime? _parseImportDate(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // Excel serial number (e.g. 45912)
  final serial = double.tryParse(s);
  if (serial != null) {
    if (serial >= 36000 && serial <= 60000) {
      return DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
    }
    return null;
  }

  s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  s = s.replaceAll(
      RegExp(r'\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\b[\s,.\-]*',
          caseSensitive: false),
      ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return null;

  // 2025-09-12 (a time after it is fine too)
  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)').firstMatch(s);
  if (m != null) {
    return _importMakeDate(int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!));
  }

  // 12/09/2025, 12-09-25, 12.09.2025
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    int day, mon;
    if (a > 12 && b <= 12) {
      day = a;
      mon = b;
    } else if (b > 12 && a <= 12) {
      day = b;
      mon = a;
    } else if (_importDayFirst) {
      day = a;
      mon = b;
    } else {
      day = b;
      mon = a;
    }
    return _importMakeDate(y, mon, day);
  }

  // 12 Sep 2025, 12-Sep-25, 12th September
  m = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?[\s,./-]*([A-Za-z]{3,})[\s,./-]*(\d{2,4})?$')
      .firstMatch(s);
  if (m != null) {
    final mon = _kImportMonths[m.group(2)!.toLowerCase().substring(0, 3)];
    if (mon != null) {
      final y = m.group(3) == null ? DateTime.now().year : int.parse(m.group(3)!);
      return _importMakeDate(y, mon, int.parse(m.group(1)!));
    }
  }

  // Sep 12, 2025
  m = RegExp(r'^([A-Za-z]{3,})[\s,./-]*(\d{1,2})(?:st|nd|rd|th)?[\s,./-]*(\d{2,4})?$')
      .firstMatch(s);
  if (m != null) {
    final mon = _kImportMonths[m.group(1)!.toLowerCase().substring(0, 3)];
    if (mon != null) {
      final y = m.group(3) == null ? DateTime.now().year : int.parse(m.group(3)!);
      return _importMakeDate(y, mon, int.parse(m.group(2)!));
    }
  }
  return null;
}

// 'P' / 'A', or null (blank or not understood).
String? _parseImportStatus(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  final n = double.tryParse(s);
  if (n != null) {
    if (n == 1) return 'P';
    if (n == 0) return 'A';
    return null;
  }
  // "P.", "(P)", "Pre sent" -> remove punctuation and spaces
  s = s.replaceAll(RegExp(r'[\s.\-_()\[\]]+'), '');
  if (s.isEmpty) return null;
  const present = {
    'p', 'pr', 'prs', 'prsnt', 'pre', 'present', 'y', 'yes', 'true',
    'late', 'lt', 'od', '✓', '✔', '√', '☑', '✅'
  };
  const absent = {
    'a', 'ab', 'abs', 'abst', 'absnt', 'absent', 'n', 'no', 'false', 'x',
    'l', 'lv', 'leave', '✗', '✘', '✕', '✖', '❌'
  };
  if (present.contains(s)) return 'P';
  if (absent.contains(s)) return 'A';
  if (s.startsWith('present')) return 'P';
  if (s.startsWith('absent')) return 'A';
  return null;
}

// Text of an Excel cell. Date cells become yyyy-MM-dd.
String _importCellText(dynamic data) {
  try {
    final inner = (data?.value) as dynamic;
    if (inner == null) return '';
    final typeName = inner.runtimeType.toString();
    if (typeName.contains('Date')) {
      DateTime? dt;
      try {
        dt = inner.asDateTimeLocal() as DateTime;
      } catch (e) {
        debugPrint('attendance_import.dart:186: $e');
      }
      if (dt == null) {
        try {
          dt = DateTime(inner.year as int, inner.month as int, inner.day as int);
        } catch (e) {
          debugPrint('attendance_import.dart:190: $e');
        }
      }
      if (dt != null) return DateFormat('yyyy-MM-dd').format(dt);
    }
    if (typeName.contains('Double')) {
      final d = inner.value as double;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
  } catch (e) {
    debugPrint('attendance_import.dart:198: $e');
  }
  return _excelCellText(data);
}

// Fallback XLSX reader. The 'excel' package often crashes on files from WPS,
// Google Sheets and mobile apps. This reads the zip's XML directly so any .xlsx opens.
String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&amp;', '&');

String _xmlTextOf(String xml) {
  final cleaned =
      xml.replaceAll(RegExp(r'<rPh\b[^>]*>.*?</rPh>', dotAll: true), '');
  final b = StringBuffer();
  for (final m
      in RegExp(r'<t\b[^>]*?(?:/>|>(.*?)</t>)', dotAll: true).allMatches(cleaned)) {
    b.write(m.group(1) ?? '');
  }
  return _xmlUnescape(b.toString());
}

int _xlsxColIndex(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u >= 65 && u <= 90) {
      n = n * 26 + (u - 64);
    } else if (u >= 97 && u <= 122) {
      n = n * 26 + (u - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

int _xlsxRowIndex(String ref) =>
    (int.tryParse(ref.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1) - 1;

bool _xlsxIsDateFmt(int id, String? code) {
  if ((id >= 14 && id <= 22) ||
      (id >= 27 && id <= 36) ||
      (id >= 45 && id <= 47) ||
      (id >= 50 && id <= 58)) {
    return true;
  }
  if (code == null) return false;
  final c = code
      .replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '')
      .toLowerCase()
      .replaceAll('general', '');
  return RegExp(r'[dmyh]').hasMatch(c);
}

List<bool> _xlsxDateStyles(String xml) {
  final fmts = <int, String>{};
  for (final m in RegExp(r'<numFmt\b([^>]*?)/?>').allMatches(xml)) {
    final a = m.group(1)!;
    final id =
        int.tryParse(RegExp(r'numFmtId="(\d+)"').firstMatch(a)?.group(1) ?? '');
    final code = RegExp(r'formatCode="([^"]*)"').firstMatch(a)?.group(1);
    if (id != null && code != null) fmts[id] = _xmlUnescape(code);
  }
  final out = <bool>[];
  final cx =
      RegExp(r'<cellXfs\b[^>]*>(.*?)</cellXfs>', dotAll: true).firstMatch(xml);
  if (cx == null) return out;
  for (final m in RegExp(r'<xf\b([^>]*?)/?>').allMatches(cx.group(1)!)) {
    final id = int.tryParse(
            RegExp(r'numFmtId="(\d+)"').firstMatch(m.group(1)!)?.group(1) ??
                '') ??
        0;
    out.add(_xlsxIsDateFmt(id, fmts[id]));
  }
  return out;
}

List<List<String>> _xlsxSheetGrid(
    String xml, List<String> shared, List<bool> dateStyle) {
  final cells = <int, Map<int, String>>{};
  var maxC = 0, maxR = 0;
  for (final m
      in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(xml)) {
    final attrs = m.group(1)!;
    final body = m.group(2) ?? '';
    final ref = RegExp(r'\br="([A-Za-z]+\d+)"').firstMatch(attrs)?.group(1);
    if (ref == null) continue;
    final r = _xlsxRowIndex(ref);
    final c = _xlsxColIndex(ref);
    if (r < 0 || c < 0 || r > 4000 || c > 400) continue;
    final t = RegExp(r'\bt="(\w+)"').firstMatch(attrs)?.group(1) ?? 'n';
    final si =
        int.tryParse(RegExp(r'\bs="(\d+)"').firstMatch(attrs)?.group(1) ?? '');
    final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1);
    var text = '';
    if (t == 'inlineStr') {
      text = _xmlTextOf(body);
    } else if (v == null) {
      text = '';
    } else if (t == 's') {
      final i = int.tryParse(v.trim());
      text = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
    } else if (t == 'str' || t == 'e') {
      text = _xmlUnescape(v);
    } else if (t == 'b') {
      text = v.trim() == '1' ? 'TRUE' : 'FALSE';
    } else {
      final n = double.tryParse(v.trim());
      if (n == null) {
        text = v.trim();
      } else if (si != null && si < dateStyle.length && dateStyle[si] && n >= 1) {
        final d = DateTime(1899, 12, 30).add(Duration(days: n.floor()));
        text = DateFormat('yyyy-MM-dd').format(d);
      } else {
        text = n == n.roundToDouble() ? n.toInt().toString() : v.trim();
      }
    }
    text = text.trim();
    if (text.isEmpty) continue;
    (cells[r] ??= <int, String>{})[c] = text;
    if (r > maxR) maxR = r;
    if (c > maxC) maxC = c;
  }
  if (cells.isEmpty) return [];
  return [
    for (var r = 0; r <= maxR; r++)
      [for (var c = 0; c <= maxC; c++) cells[r]?[c] ?? '']
  ];
}

List<List<List<String>>> _rawXlsxGrids(Uint8List bytes) {
  final arch = zip.ZipDecoder().decodeBytes(bytes);
  String? read(String name) {
    for (final f in arch.files) {
      if (f.name.replaceAll('\\', '/') == name) {
        final c = (f as dynamic).content;
        if (c is List<int>) return utf8.decode(c, allowMalformed: true);
      }
    }
    return null;
  }

  final shared = <String>[];
  final ss = read('xl/sharedStrings.xml');
  if (ss != null) {
    for (final m in RegExp(r'<si\b[^>]*?(?:/>|>(.*?)</si>)', dotAll: true)
        .allMatches(ss)) {
      shared.add(_xmlTextOf(m.group(1) ?? ''));
    }
  }
  final st = read('xl/styles.xml');
  final dateStyle = st == null ? <bool>[] : _xlsxDateStyles(st);

  final names = <MapEntry<int, String>>[];
  for (final f in arch.files) {
    final n = f.name.replaceAll('\\', '/');
    final m = RegExp(r'^xl/worksheets/sheet(\d+)\.xml$').firstMatch(n);
    if (m != null) names.add(MapEntry(int.parse(m.group(1)!), n));
  }
  names.sort((a, b) => a.key.compareTo(b.key));

  final out = <List<List<String>>>[];
  for (final e in names) {
    final xml = read(e.value);
    if (xml == null) continue;
    final g = _xlsxSheetGrid(xml, shared, dateStyle);
    if (g.isNotEmpty) out.add(g);
  }
  return out;
}

// Grids of all sheets, from the excel package and the fallback reader.
List<List<List<String>>> _allXlsxGrids(Uint8List bytes,
    {required bool forAttendance}) {
  final out = <List<List<String>>>[];
  try {
    final book = excel_lib.Excel.decodeBytes(bytes);
    for (final table in book.tables.values) {
      final r = table.rows
          .map((row) => row
              .map((c) => forAttendance ? _importCellText(c) : _excelCellText(c))
              .toList())
          .toList();
      if (r.any((x) => x.any((c) => c.isNotEmpty))) out.add(r);
    }
  } catch (e) {
    debugPrint('excel package failed: $e');
  }
  try {
    out.addAll(_rawXlsxGrids(bytes));
  } catch (e) {
    debugPrint('raw xlsx reader failed: $e');
  }
  return out;
}

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
  final String father;
  _ImportLongRec(this.name, this.roll, this.date, this.sess, this.status,
      [this.father = '']);
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
  if (_studentHeaderKind(raw) == 4) return false; // F. Name, S/O, Walid ...
  if (RegExp(r'father|mother|parent|guardian').hasMatch(t)) return false;
  return t == 'student' || t == 'naam' || t.contains('name');
}

bool _importIsFatherHeader(String raw) => _studentHeaderKind(raw) == 4;

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

  // Father name column: any header like Father Name / F/O / S/O / Walid / Guardian.
  var fatherCol = -1;
  for (var c = 0; c < nC && fatherCol < 0; c++) {
    if (dates.containsKey(c)) continue;
    for (var r = 0; r <= dateRow + 2 && r < nR; r++) {
      if (_importIsFatherHeader(cell(r, c))) {
        fatherCol = c;
        break;
      }
    }
  }

  // Name column: the one with 'name' in its header, else the one with the most text.
  var nameCol = -1;
  var bestScore = 0.0;
  for (var c = 0; c < nC; c++) {
    if (dates.containsKey(c) || c == fatherCol) continue;
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
    if (c == nameCol || c == fatherCol || dates.containsKey(c)) continue;
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
      if (dates.containsKey(k) || k == nameCol || k == rollCol || k == fatherCol) {
        break;
      }
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
    outRows.add(ImportRow(
        names[r]!,
        rollCol >= 0 ? cell(r, rollCol) : '',
        st,
        fatherCol >= 0 ? _cleanImportedFather(cell(r, fatherCol)) : ''));
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

  var fatherCol = -1;
  for (var c = 0; c < nC && fatherCol < 0; c++) {
    if (c == dateCol || c == statusCol) continue;
    if (headerHas(c, _importIsFatherHeader)) fatherCol = c;
  }

  var nameCol = -1;
  var bestScore = 0.0;
  for (var c = 0; c < nC; c++) {
    if (c == dateCol || c == statusCol || c == fatherCol) continue;
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
    if (c == dateCol || c == statusCol || c == nameCol || c == fatherCol) {
      continue;
    }
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
    final father =
        fatherCol >= 0 ? _cleanImportedFather(g[r][fatherCol]) : '';
    final dayKey = DateFormat('yyyy-MM-dd').format(d);
    final ok = '$dayKey|${_normImportName(name)}|${_normImportName(father)}';
    final n = (occ[ok] ?? 0) + 1;
    occ[ok] = n;
    var sess = n;
    if (sessCol >= 0) {
      final sm = RegExp(r'\d+').firstMatch(g[r][sessCol]);
      final v = int.tryParse(sm?.group(0) ?? '');
      if (v != null && v > 0) sess = v;
    }
    recs.add(_ImportLongRec(
        name, rollCol >= 0 ? g[r][rollCol] : '', d, sess, st, father));
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
    final nk = '${_normImportName(x.name)}|${_normImportName(x.father)}';
    final row = byName.putIfAbsent(
        nk, () => ImportRow(x.name, x.roll, <int, String>{}, x.father));
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

// Matches file rows to app students. Only sure matches count; the rest are shown
// to the user. Order of checks:
//   1) same name (any word order, spelling variants like Muhammad / Mohd / M.)
//      - when the file has a father name, name + father name must agree;
//      - same name twice: the father name decides first, and only if that cannot
//        decide, the Nth row in the file goes to the Nth student (roll order);
//   2) roll number, 3) a unique close spelling (typo) with a compatible father.
Map<int, String> autoMatchImportRows(
    List<ImportRow> rows, List<Map<String, String>> students) {
  final result = <int, String>{};
  final taken = <String>{};
  void take(int i, Map<String, String> s) {
    result[i] = (s['roll'] ?? '');
    taken.add(s['roll'] ?? '');
  }

  final byKey = <String, List<Map<String, String>>>{};
  for (final s in students) {
    (byKey[_sortedCanon(s['name'] ?? '')] ??= <Map<String, String>>[]).add(s);
  }
  List<Map<String, String>> freeOf(int i) => [
        for (final s in byKey[_sortedCanon(rows[i].name)] ??
            const <Map<String, String>>[])
          if (!taken.contains(s['roll'] ?? '')) s
      ];

  // 1a) rows that have a father name: name + father name together.
  for (var i = 0; i < rows.length; i++) {
    final f = rows[i].father;
    if (f.isEmpty) continue;
    for (final s in freeOf(i)) {
      if (_fatherCompat(s['father'] ?? '', f) == true) {
        take(i, s);
        break;
      }
    }
  }

  // 1b) the rest: same name. Students with no father name filled yet are fine;
  // a student whose father name is clearly different is never taken.
  for (var i = 0; i < rows.length; i++) {
    if (result.containsKey(i)) continue;
    final f = rows[i].father;
    for (final s in freeOf(i)) {
      if (f.isEmpty || _fatherCompat(s['father'] ?? '', f) == null) {
        take(i, s);
        break;
      }
    }
  }

  // 2) roll number from the file (only if the father name does not contradict it)
  for (var i = 0; i < rows.length; i++) {
    if (result.containsKey(i) || rows[i].roll.isEmpty) continue;
    for (final s in students) {
      if (taken.contains(s['roll'] ?? '')) continue;
      if (rows[i].roll.trim() != rollOf(s['roll'] ?? '').trim()) continue;
      if (_fatherCompat(s['father'] ?? '', rows[i].father) == false) continue;
      take(i, s);
      break;
    }
  }

  // 3) small typos: only when exactly one student is clearly the closest.
  for (var i = 0; i < rows.length; i++) {
    if (result.containsKey(i)) continue;
    var best = 0.0, second = 0.0;
    Map<String, String>? bs;
    for (final s in students) {
      if (taken.contains(s['roll'] ?? '')) continue;
      if (_fatherCompat(s['father'] ?? '', rows[i].father) == false) continue;
      final sim = _personSim(rows[i].name, s['name'] ?? '');
      if (sim > best) {
        second = best;
        best = sim;
        bs = s;
      } else if (sim > second) {
        second = sim;
      }
    }
    if (bs != null && best >= 0.9 && best - second >= 0.05) take(i, bs);
  }
  return result;
}

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
  } catch (e) {
    debugPrint('attendance_import.dart:1022: $e');
  }
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
    setAppBusy(true);
    _map = autoMatchImportRows(widget.sheet.rows, widget.students);
    _autoRows = _map.keys.toSet();
    _cols = {
      for (final c in widget.sheet.columns)
        if (!_locked(c)) c.col
    };
  }

  @override
  void dispose() {
    setAppBusy(false);
    super.dispose();
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
 float: false,
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
 float: false,
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
 float: false,
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        rows[i].father.isEmpty
                            ? rows[i].name
                            : '${rows[i].name}  (F/N ${rows[i].father})',
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
                                '${rollOf(s['roll'] ?? '')} • ${s['name']}'
                                '${(s['father'] ?? '').isEmpty ? '' : ' (F/N ${s['father']})'}',
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
 float: false,
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
