part of '../main.dart';

// Writes the .xlsx file directly.

// ---- Shared Excel layout ----
// Both exports use this layout: info section (Program, Semester, Instructor,
// Course, Section, Marks), three header rows (Week, Date, Class No.), then students.
// Attendance is 1 (present) / 0 (absent). Totals, Percentage and Marks are formulas.

// Default attendance marks. Only the starting value of the "Marks" cell; the
// formulas read that cell, so it can be changed per course in Excel.
const double kDefaultAttendanceMarks = 5;

// Info section details. Nothing is hardcoded; all values come from the export.
class ExcelInfo {
  final String program;
  final String semester;
  final String instructor;
  final String course;
  final String section;
  final double marks;
  const ExcelInfo({
    required this.program,
    required this.semester,
    required this.instructor,
    required this.course,
    required this.section,
    this.marks = kDefaultAttendanceMarks,
  });
}

Future<ExcelInfo> loadExcelInfo(SemRef sem, String subject) async {
  String semLabel = defaultSemesterLabel(sem.semester);
  try {
    final labels = await loadSemesterLabels(sem.deptId, sem.section);
    semLabel = labels[sem.semester] ?? semLabel;
  } catch (_) {}

  String instructor = '';
  try {
    final res = await _safeQuery(
        sem.subjects.where(FieldPath.documentId, isEqualTo: subject));
    if (res.docs.isNotEmpty) {
      instructor = (res.docs.first.data()['claimed_by_name'] ?? '').toString();
    }
  } catch (_) {}
  if (instructor.isEmpty && !AppSession.isAdmin) {
    instructor = AppSession.teacherName;
  }

  return ExcelInfo(
    program: sem.deptId,
    semester: semLabel,
    instructor: instructor,
    course: subject,
    section: sem.section,
  );
}

String _excelColLetters(int c) {
  var n = c + 1;
  var s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _ordinal(int n) {
  final m100 = n % 100;
  if (m100 >= 11 && m100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

// ---- Direct .xlsx writer ----
// The excel package dropped styles and merges on some builds, so the sheet is
// written directly as xlsx XML. Styles, merges, widths and heights are exact.
class _XlsxBuilder {
  final List<String> _fonts = [
    '<font><sz val="11"/><name val="Arial"/><family val="2"/></font>'
  ];
  final List<String> _fills = [
    '<fill><patternFill patternType="none"/></fill>',
    '<fill><patternFill patternType="gray125"/></fill>'
  ];
  final List<String> _borders = [
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
  ];
  final List<String> _xfs = [
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
  ];
  final Map<int, Map<int, String>> _cells = {};
  final Map<int, double> rowHeights = {};
  final Map<int, double> colWidths = {};
  final List<String> merges = [];
  int freezeRows = 7; // rows kept on top while scrolling (header rows)

  int _idx(List<String> list, String xml) {
    final i = list.indexOf(xml);
    if (i >= 0) return i;
    list.add(xml);
    return list.length - 1;
  }

  String _side(String tag, String? style, String color) => style == null
      ? '<$tag/>'
      : '<$tag style="$style"><color rgb="$color"/></$tag>';

  int style({
    String font = 'FF000000',
    String? bg,
    int size = 11,
    bool bold = true,
    bool left = false,
    bool wrap = false,
    bool border = true,
    bool thick = false,
  }) {
    final fontId = _idx(
        _fonts,
        '<font>${bold ? '<b/>' : ''}<sz val="$size"/>'
        '<color rgb="$font"/><name val="Arial"/><family val="2"/></font>');
    final fillId = bg == null
        ? 0
        : _idx(
            _fills,
            '<fill><patternFill patternType="solid"><fgColor rgb="$bg"/>'
            '<bgColor indexed="64"/></patternFill></fill>');
    final bStyle = border ? (thick ? 'medium' : 'thin') : null;
    final bColor = thick ? 'FF1F3864' : 'FFB4C0D8';
    final borderId = _idx(
        _borders,
        '<border>${_side('left', bStyle, bColor)}${_side('right', bStyle, bColor)}'
        '${_side('top', bStyle, bColor)}${_side('bottom', bStyle, bColor)}'
        '<diagonal/></border>');
    return _idx(
        _xfs,
        '<xf numFmtId="0" fontId="$fontId" fillId="$fillId" borderId="$borderId" '
        'xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
        '<alignment horizontal="${left ? 'left' : 'center'}" vertical="center"'
        '${wrap ? ' wrapText="1"' : ''}/></xf>');
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _num(num v) => v == v.roundToDouble() ? v.round().toString() : '$v';

  void _put(int c, int r, String xml) =>
      (_cells[r] ??= <int, String>{})[c] = xml;

  String _ref(int c, int r) => '${_excelColLetters(c)}${r + 1}';

  void blank(int c, int r, int s) => _put(c, r, '<c r="${_ref(c, r)}" s="$s"/>');

  void text(int c, int r, String v, int s) => _put(
      c,
      r,
      '<c r="${_ref(c, r)}" s="$s" t="inlineStr"><is>'
      '<t xml:space="preserve">${_esc(v)}</t></is></c>');

  void number(int c, int r, num v, int s) =>
      _put(c, r, '<c r="${_ref(c, r)}" s="$s"><v>${_num(v)}</v></c>');

  void formula(int c, int r, String f, num cached, int s) => _put(c, r,
      '<c r="${_ref(c, r)}" s="$s"><f>${_esc(f)}</f><v>${_num(cached)}</v></c>');

  // Merged area: every cell gets the style (so colour + borders are kept),
  // the text is written in the first cell only.
  void merge(int c1, int r1, int c2, int r2, String? v, int s) {
    for (int r = r1; r <= r2; r++) {
      for (int c = c1; c <= c2; c++) {
        blank(c, r, s);
      }
    }
    if (v != null) text(c1, r1, v, s);
    if (c1 != c2 || r1 != r2) merges.add('${_ref(c1, r1)}:${_ref(c2, r2)}');
  }

  List<int> build() {
    final rows = <int>{..._cells.keys, ...rowHeights.keys}.toList()..sort();
    final sb = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
        '<sheetViews><sheetView showGridLines="0" workbookViewId="0" tabSelected="1">'
        '<pane xSplit="2" ySplit="$freezeRows" topLeftCell="C${freezeRows + 1}" activePane="bottomRight" state="frozen"/>'
        '</sheetView></sheetViews>'
        '<sheetFormatPr defaultRowHeight="22" customHeight="1"/>');
    if (colWidths.isNotEmpty) {
      sb.write('<cols>');
      final keys = colWidths.keys.toList()..sort();
      for (final c in keys) {
        sb.write('<col min="${c + 1}" max="${c + 1}" '
            'width="${colWidths[c]}" customWidth="1"/>');
      }
      sb.write('</cols>');
    }
    sb.write('<sheetData>');
    for (final r in rows) {
      final h = rowHeights[r];
      sb.write('<row r="${r + 1}"'
          '${h != null ? ' ht="$h" customHeight="1"' : ''}>');
      final row = _cells[r];
      if (row != null) {
        final cols = row.keys.toList()..sort();
        for (final c in cols) {
          sb.write(row[c]);
        }
      }
      sb.write('</row>');
    }
    sb.write('</sheetData>');
    if (merges.isNotEmpty) {
      sb.write('<mergeCells count="${merges.length}">'
          '${merges.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>');
    }
    // Print: A4 landscape, whole sheet fitted on ONE page, centered.
    sb.write('<printOptions horizontalCentered="1"/>'
        '<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.5" '
        'header="0.3" footer="0.3"/>'
        '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="1"/>'
        '<headerFooter><oddFooter>&amp;CPage &amp;P of &amp;N</oddFooter></headerFooter>'
        '</worksheet>');

    final styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="${_fonts.length}">${_fonts.join()}</fonts>'
        '<fills count="${_fills.length}">${_fills.join()}</fills>'
        '<borders count="${_borders.length}">${_borders.join()}</borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${_xfs.length}">${_xfs.join()}</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';

    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>';
    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';
    const workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
        '<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>';
    const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>';

    final out = zip.Archive();
    void add(String name, String content) {
      final data = utf8.encode(content);
      out.addFile(zip.ArchiveFile(name, data.length, data));
    }

    add('[Content_Types].xml', contentTypes);
    add('_rels/.rels', rootRels);
    add('xl/workbook.xml', workbook);
    add('xl/_rels/workbook.xml.rels', workbookRels);
    add('xl/styles.xml', styles);
    add('xl/worksheets/sheet1.xml', sb.toString());
    return zip.ZipEncoder().encode(out) ?? <int>[];
  }
}
