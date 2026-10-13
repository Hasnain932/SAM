part of '../main.dart';

// Backup .xlsx reader for files the excel package cannot open.

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
