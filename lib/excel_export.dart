part of 'main.dart';

// ---- Shared Excel layout ----
// Both exports use this layout:
//   row 1      merged title banner (institution name)
//   rows 2-4   info grid: Program | Course, Semester | Section, Marks | Instructor
//   next rows  Week (merged over its sessions) / Date / Class No., with Roll No,
//              Name, Totals merged over the three header rows, then the students.
// Attendance is P / A or 1 / 0. Totals, Percentage and Marks are formulas.
// The file is plain .xlsx (shared strings, valid element order, no overlapping
// merges), so Excel 2010 and newer open it without any repair prompt.

// Default attendance marks. Only the starting value of the "Marks" cell; the
// formulas read that cell, so it can be changed per course in Excel.
const double kDefaultAttendanceMarks = 5;

// Info section details. All values come from the export; the institution name
// in the title row comes from kInstitutionName (main.dart).
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
  } catch (e) {
    debugPrint('excel_export.dart:35: $e');
  }

  String instructor = '';
  try {
    final res = await _safeQuery(
        sem.subjects.where(FieldPath.documentId, isEqualTo: subject));
    if (res.docs.isNotEmpty) {
      instructor = (res.docs.first.data()['claimed_by_name'] ?? '').toString();
    }
  } catch (e) {
    debugPrint('excel_export.dart:44: $e');
  }
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

// Approximate width (in Excel column units) a text needs so it is fully
// visible: lets every column grow to fit its longest text.
double _textUnits(String s, {double size = 12, bool bold = true}) {
  double px = 0;
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (r == 32) {
      px += 3.5;
    } else if ('ijlI.,:;\'|!()'.contains(ch)) {
      px += 4;
    } else if ('mwMW@'.contains(ch)) {
      px += 11;
    } else if (r >= 65 && r <= 90) {
      px += 8.8;
    } else if (r >= 0x0600) {
      px += 9; // Urdu / Arabic and other wide scripts
    } else {
      px += 7.2;
    }
  }
  px *= (size / 11) * (bold ? 1.1 : 1.0);
  return px / 7 + 2.5;
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
  // Strings are stored in a shared-strings table, exactly like Excel itself
  // saves them (older Excel versions, e.g. 2010, are fussier with inline strings).
  final List<String> _strings = [];
  final Map<String, int> _stringIdx = {};
  // A4 landscape page with normal margins, written explicitly so Excel 2010
  // print preview (Ctrl+P) never has to guess the page settings. The sheet is
  // fitted to one page wide (as many pages tall as needed). No freeze panes,
  // no print titles.

  int _sst(String v) {
    final clean = v.replaceAll(_badXml, '');
    return _stringIdx.putIfAbsent(clean, () {
      _strings.add(clean);
      return _strings.length - 1;
    });
  }

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
    bool shrink = false,
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
        '${wrap ? ' wrapText="1"' : ''}${shrink ? ' shrinkToFit="1"' : ''}/></xf>');
  }

  // Characters that are illegal in XML 1.0 (control codes, e.g. from imported
  // names) make Excel crash or "repair" the file, so they are removed first.
  static final RegExp _badXml =
      RegExp('[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\uFFFE\\uFFFF]');

  String _esc(String s) => s
      .replaceAll(_badXml, '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _num(num v) => v == v.roundToDouble() ? v.round().toString() : '$v';

  void _put(int c, int r, String xml) =>
      (_cells[r] ??= <int, String>{})[c] = xml;

  String _ref(int c, int r) => '${_excelColLetters(c)}${r + 1}';

  void blank(int c, int r, int s) => _put(c, r, '<c r="${_ref(c, r)}" s="$s"/>');

  void text(int c, int r, String v, int s) => _put(c, r,
      '<c r="${_ref(c, r)}" s="$s" t="s"><v>${_sst(v)}</v></c>');

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
    // Used range (A1:lastCol lastRow).
    var maxCol = 0;
    for (final row in _cells.values) {
      for (final c in row.keys) {
        if (c > maxCol) maxCol = c;
      }
    }
    final dimension =
        'A1:${_excelColLetters(maxCol)}${rows.isEmpty ? 1 : rows.last + 1}';
    final sb = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
        '<dimension ref="$dimension"/>'
        '<sheetViews><sheetView workbookViewId="0" tabSelected="1"/></sheetViews>'
        '<sheetFormatPr defaultRowHeight="22"/>');
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
    sb.write('<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" '
        'header="0.3" footer="0.3"/>'
        '<pageSetup paperSize="9" orientation="landscape" '
        'fitToWidth="1" fitToHeight="0"/>');
    sb.write('</worksheet>');

    final sst = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'count="${_strings.length}" uniqueCount="${_strings.length}">');
    for (final t in _strings) {
      sst.write('<si><t xml:space="preserve">${_esc(t)}</t></si>');
    }
    sst.write('</sst>');

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
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '</Types>';
    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>';
    final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="20000" windowHeight="10000"/></bookViews>'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
        '<calcPr calcId="124519"/></workbook>';
    const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
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
    add('xl/sharedStrings.xml', sst.toString());
    add('xl/worksheets/sheet1.xml', sb.toString());
    add(
        'docProps/core.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:creator>Attendance</dc:creator></cp:coreProperties>');
    add(
        'docProps/app.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>Microsoft Excel</Application></Properties>');
    return zip.ZipEncoder().encode(out) ?? <int>[];
  }
}

// What goes into the Excel file and how attendance is written.
class ExportOptions {
  final String scope; // 'all' (Class + Lab Class), kTypeClass or kTypeLab
  final bool useLetters; // true: P / A letters, false: 1 / 0 digits
  final String phase; // 'all' (Overall), kPhaseMid or kPhaseFinal
  const ExportOptions(this.scope, this.useLetters, [this.phase = 'all']);
}

// Sessions that belong in the file for the chosen scope (Class/Lab) and
// exam phase (Overall / Mid / Final). Both filters combine.
List<DateRecord> filterRecordsByScope(List<DateRecord> recs, String scope,
    {String phase = 'all'}) {
  var out = List<DateRecord>.from(recs);
  if (phase == kPhaseFinal) out = out.where((r) => r.isFinal).toList();
  if (phase == kPhaseMid) out = out.where((r) => r.isMid).toList();
  if (scope == kTypeLab) return out.where((r) => r.isLab).toList();
  if (scope == kTypeClass) return out.where((r) => !r.isLab).toList();
  return out;
}

// Text for "No ... sessions" messages, e.g. "Mid", "Final Lab Class".
String optionsLabel(ExportOptions o) {
  final ph = o.phase == 'all' ? '' : phaseLabel(o.phase);
  final sc = (o.scope == 'all' && o.phase != 'all') ? '' : scopeLabel(o.scope);
  return [ph, sc].where((e) => e.isNotEmpty).join(' ');
}

// Part of the file name for the phase ('' for Overall).
String phaseFileTag(String phase) =>
    phase == kPhaseFinal ? 'Final_' : (phase == kPhaseMid ? 'Mid_' : '');

String scopeLabel(String scope) => scope == kTypeLab
    ? 'Lab Class'
    : scope == kTypeClass
        ? 'Class'
        : 'Class + Lab Class';

// Part of the file name for the scope ('' for combined).
String scopeFileTag(String scope) =>
    scope == kTypeLab ? 'Lab_' : (scope == kTypeClass ? 'Class_' : '');

// File name start: [Department_]Subject_Section_A_Semester_3
String exportFileBase(SemRef sem, String semLabel, String subject,
    {String deptName = ''}) {
  String clean(String v) => v
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return [
    clean(deptName),
    clean(subject),
    'Section_${clean(sem.section)}',
    clean(semLabel),
  ].where((e) => e.isNotEmpty).join('_');
}

// One dialog for both exports (overall and monthly): what to include
// (Class + Lab Class / Class only / Lab Class only), which exam phase
// (Overall / Mid / Final) and the P/A format.
Future<ExportOptions?> askExportOptions(
    BuildContext context, List<DateRecord> recs) {
  var scope = 'all';
  var phase = 'all';
  var letters = true;
  final midCount = recs.where((r) => r.isMid).length;
  final finalCount = recs.length - midCount;

  return showDialog<ExportOptions>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Widget choice(String title, String sub, bool selected, VoidCallback? onTap) {
          return ListTile(
            dense: true,
            enabled: onTap != null,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: onTap == null ? kOutline : kAccent,
            ),
            title: Text(title),
            subtitle: sub.isEmpty ? null : Text(sub),
            onTap: onTap,
          );
        }

        // Class / Lab counts follow the chosen phase.
        final inPhase = filterRecordsByScope(recs, 'all', phase: phase);
        final classCount = inPhase.where((r) => !r.isLab).length;
        final labCount = inPhase.length - classCount;

        String n(int c) => '$c session${c == 1 ? '' : 's'}';
        return AlertDialog(
          title: const Text('Export Excel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Include',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
                choice('Class + Lab Class (combined)', n(inPhase.length),
                    scope == 'all', () => setS(() => scope = 'all')),
                choice('Class only', n(classCount), scope == kTypeClass,
                    classCount == 0 ? null : () => setS(() => scope = kTypeClass)),
                choice('Lab Class only', n(labCount), scope == kTypeLab,
                    labCount == 0 ? null : () => setS(() => scope = kTypeLab)),
                const Divider(),
                const Text('Exam phase',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
                choice('Overall (Mid + Final)', n(recs.length), phase == 'all',
                    () => setS(() => phase = 'all')),
                choice('Mid', n(midCount), phase == kPhaseMid,
                    midCount == 0 ? null : () => setS(() => phase = kPhaseMid)),
                choice('Final', n(finalCount), phase == kPhaseFinal,
                    finalCount == 0
                        ? null
                        : () => setS(() => phase = kPhaseFinal)),
                const Divider(),
                const Text('Format',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
                choice('P / A   (Present / Absent)', '', letters,
                    () => setS(() => letters = true)),
                choice('1 / 0   (1 = Present, 0 = Absent)', '', !letters,
                    () => setS(() => letters = false)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, ExportOptions(scope, letters, phase)),
              child: const Text('Export'),
            ),
          ],
        );
      },
    ),
  );
}

// Asks which format the Excel file should use.
// true = P / A letters, false = 1 / 0 digits, null = cancelled.
Future<bool?> askExportFormat(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Export format'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('P / A   (Present / Absent)'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('1 / 0   (1 = Present, 0 = Absent)'),
        ),
      ],
    ),
  );
}

List<int>? buildAttendanceExcelBytes({
  required ExcelInfo info,
  required List<DateRecord> recs,
  required List<Map<String, String>> students,
  bool useLetters = false, // true: P / A letters, false: 1 / 0 digits
  bool showFather = true, // false: no Father Name column (monthly export)
  bool showMarks = true, // false: no Marks column at the end (monthly export)
}) {
  final records = List<DateRecord>.from(recs)
    ..sort((a, b) => a.id.compareTo(b.id));
  final x = _XlsxBuilder();

  // ---- Colour theme (Navy Gold) ----
  const navy = 'FF1F3864';
  const head = 'FF2F4F8F';
  const gold = 'FFC9A227';
  const bandA = 'FFFFFFFF';
  const bandB = 'FFF3F6FB';
  const infoBg = 'FFE9EFF9';
  const green = 'FF1B7F3B';
  const red = 'FFD92D20';
  const white = 'FFFFFFFF';

  // ---- Header styles ----
  final titleStyle =
      x.style(size: 16, font: white, bg: navy, border: false);
  final infoLabelStyle = x.style(size: 10, font: white, bg: navy);
  final infoValueStyle =
      x.style(size: 11, font: navy, bg: infoBg, shrink: true);
  final idHeadStyle =
      x.style(size: 12, font: white, bg: head, wrap: true, thick: true);
  final totalHeadStyle =
      x.style(size: 10, font: navy, bg: gold, wrap: true, thick: true);
  final weekStyle = x.style(size: 11, font: white, bg: head);
  final dateStyle = x.style(size: 10, font: navy, bg: 'FFD9E2F3', wrap: true);
  final serialStyle =
      x.style(size: 9, font: navy, bg: 'FFE9EFF9', bold: false);
  // Small "Lab" label above lab session columns.
  final labStyle = x.style(size: 9, font: navy, bg: gold);

  // ---- Body styles (two alternating row backgrounds, bold 12 pt) ----
  // Present (P / 1) = green text, Absent (A / 0) = red text. Colours are
  // written straight into each cell (no conditional formatting), so WPS /
  // mobile viewers show them too.
  const int bodySize = 12;
  final cellStyle = x.style(size: bodySize, bg: bandA);
  final cellStyleAlt = x.style(size: bodySize, bg: bandB);
  final nameStyle = x.style(size: bodySize, left: true, bg: bandA);
  final nameStyleAlt = x.style(size: bodySize, left: true, bg: bandB);
  final goodStyle = x.style(size: bodySize, font: green, bg: bandA);
  final goodStyleAlt = x.style(size: bodySize, font: green, bg: bandB);
  final badStyle = x.style(size: bodySize, font: red, bg: bandA);
  final badStyleAlt = x.style(size: bodySize, font: red, bg: bandB);

  // ---- Columns ----
  // 0 Roll No, 1 Name, 2 Father Name (only when showFather), then sessions,
  // then Total Classes, Total Present, Percentage (and Marks when showMarks).
  final int firstSessionCol = showFather ? 3 : 2;
  final n = records.length;
  final totalClassesCol = firstSessionCol + n;
  final presentCol = totalClassesCol + 1;
  final pctCol = totalClassesCol + 2;
  final marksCol = totalClassesCol + 3; // used only when showMarks
  final int lastCol = showMarks ? marksCol : pctCol;

  // ---- Column widths: every text gets the width it needs (nothing cut off) ----
  double maxRoll = _textUnits('Roll No');
  double maxName = _textUnits('Name');
  double maxFather = _textUnits('Father Name');
  for (final st in students) {
    final rw = _textUnits(rollOf(st['roll'] ?? ''));
    final nw = _textUnits(st['name'] ?? '');
    final fw = _textUnits(st['father'] ?? '');
    if (rw > maxRoll) maxRoll = rw;
    if (nw > maxName) maxName = nw;
    if (fw > maxFather) maxFather = fw;
  }
  const double narrow = 8.5; // session / info columns, all equal
  final colW = <int, double>{
    0: maxRoll < 8 ? 8 : maxRoll,
    1: maxName < 22 ? 22 : maxName,
  };
  if (showFather) colW[2] = maxFather < 16 ? 16 : maxFather;
  double widthOf(int c) => colW[c] ?? narrow;

  // ---- Row positions (0-based) ----
  // 0 title banner, 1..3 info grid, [lab row], then Week / Date / Class No.
  // (merged vertically for the fixed columns), then the students.
  final bool hasLab = records.any((r) => r.isLab);
  final int top = hasLab ? 1 : 0;
  const int labRow = 4;
  final int weekRow = 4 + top;
  final int dateRow = 5 + top;
  final int serialRow = 6 + top;
  final int firstStudentRow = 7 + top;

  // ---- Title banner + info grid (merged cells) ----
  // Width of the banner / grid: the table width (at least 11 columns so the
  // info grid always has room for its labels and values).
  final int wb = lastCol + 1 < 11 ? 11 : lastCol + 1;
  final int rest = wb - 5; // columns left for the two value cells
  final int v1End = 1 + (rest + 1) ~/ 2; // value 1 = C .. v1End
  final int l2Start = v1End + 1; // label 2 = 3 columns
  final int l2End = l2Start + 2;
  final int v2Start = l2End + 1; // value 2 = v2Start .. last column
  final int v2End = wb - 1;

  x.merge(0, 0, wb - 1, 0, kInstitutionName, titleStyle);
  x.rowHeights[0] = 30;

  void putValue(int c1, int c2, int row, Object value) {
    if (value is num) {
      x.merge(c1, row, c2, row, null, infoValueStyle);
      x.number(c1, row, value, infoValueStyle);
    } else {
      final t = value.toString();
      x.merge(c1, row, c2, row, t.isEmpty ? null : t, infoValueStyle);
    }
  }

  void infoPair(int row, String label1, Object value1, String label2,
      Object value2) {
    x.merge(0, row, 1, row, label1, infoLabelStyle);
    putValue(2, v1End, row, value1);
    x.merge(l2Start, row, l2End, row, label2, infoLabelStyle);
    putValue(v2Start, v2End, row, value2);
    x.rowHeights[row] = 21;
  }

  final num marksValue =
      info.marks == info.marks.roundToDouble() ? info.marks.round() : info.marks;
  infoPair(1, 'Program', info.program, 'Course', info.course);
  infoPair(2, 'Semester', info.semester, 'Section', info.section);
  infoPair(3, 'Marks', marksValue, 'Instructor', info.instructor);
  // The Marks value sits in C4; the Marks formulas read it from there.
  final marksRef = '\$${_excelColLetters(2)}\$4';

  // ---- Header rows: Week / Date / Class No. ----
  // Fixed columns: one merged cell over the three header rows.
  void headCell(int c, String label, int st) {
    x.merge(c, weekRow, c, serialRow, label, st);
  }

  headCell(0, 'Roll No', idHeadStyle);
  headCell(1, 'Name', idHeadStyle);
  if (showFather) headCell(2, 'Father Name', idHeadStyle);

  DateTime mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  final dates = <DateTime?>[];
  for (final r in records) {
    dates.add(DateTime.tryParse(r.id.split('_Session_')[0]));
  }
  DateTime? firstMonday;
  for (final d in dates) {
    if (d != null) {
      final m = mondayOf(d);
      if (firstMonday == null || m.isBefore(firstMonday)) firstMonday = m;
    }
  }

  final weekOf = List<int>.filled(n, 1);
  for (int i = 0; i < n; i++) {
    final d = dates[i];
    if (d != null && firstMonday != null) {
      final md = mondayOf(d);
      final days = DateTime.utc(md.year, md.month, md.day)
          .difference(DateTime.utc(
              firstMonday.year, firstMonday.month, firstMonday.day))
          .inDays;
      weekOf[i] = days ~/ 7 + 1;
    } else if (i > 0) {
      weekOf[i] = weekOf[i - 1];
    }
  }

  // "Week N" is one merged cell over all the sessions of that week.
  int runStart = 0;
  while (runStart < n) {
    int runEnd = runStart;
    while (runEnd + 1 < n && weekOf[runEnd + 1] == weekOf[runStart]) {
      runEnd++;
    }
    x.merge(firstSessionCol + runStart, weekRow, firstSessionCol + runEnd,
        weekRow, 'Week ${weekOf[runStart]}', weekStyle);
    runStart = runEnd + 1;
  }

  // Date and class number (1st, 2nd, 3rd ...) of every session.
  int classInWeek = 0;
  for (int i = 0; i < n; i++) {
    final d = dates[i];
    final dateLabel = d == null
        ? records[i].id.split('_Session_')[0]
        : DateFormat('d MMM').format(d);
    if (i == 0 || weekOf[i] != weekOf[i - 1]) {
      classInWeek = 0;
    }
    classInWeek++;
    x.text(firstSessionCol + i, dateRow, dateLabel, dateStyle);
    x.text(firstSessionCol + i, serialRow, _ordinal(classInWeek), serialStyle);
  }

  // "Lab" label above each lab column; class columns stay empty.
  if (hasLab) {
    for (int i = 0; i < n; i++) {
      if (records[i].isLab) {
        x.text(firstSessionCol + i, labRow, 'Lab', labStyle);
      }
    }
  }

  headCell(totalClassesCol, 'Total Classes', totalHeadStyle);
  headCell(presentCol, 'Total Present', totalHeadStyle);
  headCell(pctCol, 'Percentage of Present', totalHeadStyle);
  if (showMarks) headCell(marksCol, 'Marks', totalHeadStyle);

  // ---- Student rows ----
  int rowIndex = firstStudentRow;
  for (final st in students) {
    final roll = st['roll'] ?? '';
    final name = st['name'] ?? '';
    final father = st['father'] ?? '';
    int present = 0;
    final alt = (rowIndex - firstStudentRow) % 2 == 1;
    x.text(0, rowIndex, rollOf(roll), alt ? cellStyleAlt : cellStyle);
    x.text(1, rowIndex, name, alt ? nameStyleAlt : nameStyle);
    if (showFather) {
      x.text(2, rowIndex, father, alt ? nameStyleAlt : nameStyle);
    }
    for (int i = 0; i < n; i++) {
      final isP = (records[i].status[roll] ?? 'P') == 'P';
      if (isP) present++;
      final cs = isP
          ? (alt ? goodStyleAlt : goodStyle)
          : (alt ? badStyleAlt : badStyle);
      if (useLetters) {
        x.text(firstSessionCol + i, rowIndex, isP ? 'P' : 'A', cs);
      } else {
        x.number(firstSessionCol + i, rowIndex, isP ? 1 : 0, cs);
      }
    }

    final xr = rowIndex + 1;
    final plain = alt ? cellStyleAlt : cellStyle;
    final pct = n == 0 ? 0.0 : (present / n) * 100;
    final pctRounded = (pct * 100).round() / 100;
    final marksCached = (pctRounded / 100 * info.marks * 100).round() / 100;

    if (n > 0) {
      final first = '${_excelColLetters(firstSessionCol)}$xr';
      final last = '${_excelColLetters(firstSessionCol + n - 1)}$xr';
      final tcRef = '${_excelColLetters(totalClassesCol)}$xr';
      final tpRef = '${_excelColLetters(presentCol)}$xr';
      final pcRef = '${_excelColLetters(pctCol)}$xr';
      x.formula(totalClassesCol, rowIndex,
          useLetters ? 'COUNTA($first:$last)' : 'COUNT($first:$last)', n, plain);
      x.formula(
          presentCol,
          rowIndex,
          useLetters ? 'COUNTIF($first:$last,"P")' : 'SUM($first:$last)',
          present,
          plain);
      x.formula(pctCol, rowIndex, 'IF($tcRef=0,0,ROUND($tpRef/$tcRef*100,2))',
          pctRounded,
          pct >= 75
              ? (alt ? goodStyleAlt : goodStyle)
              : (alt ? badStyleAlt : badStyle));
      if (showMarks) {
        x.formula(marksCol, rowIndex, 'ROUND($pcRef/100*$marksRef,2)',
            marksCached, plain);
      }
    } else {
      x.number(totalClassesCol, rowIndex, 0, plain);
      x.number(presentCol, rowIndex, 0, plain);
      x.number(pctCol, rowIndex, 0, alt ? badStyleAlt : badStyle);
      if (showMarks) {
        x.number(marksCol, rowIndex, 0, plain);
      }
    }
    x.rowHeights[rowIndex] = 20;
    rowIndex++;
  }

  // ---- Column widths ----
  for (int c = 0; c < wb; c++) {
    x.colWidths[c] = widthOf(c);
  }
  x.colWidths[totalClassesCol] = 12;
  x.colWidths[presentCol] = 12;
  x.colWidths[pctCol] = 12;
  if (showMarks) x.colWidths[marksCol] = 9;

  // ---- Header row heights (Week / Date / Class No. = 3 rows, 60 pt together) ----
  if (hasLab) x.rowHeights[labRow] = 16;
  x.rowHeights[weekRow] = 21;
  x.rowHeights[dateRow] = 21;
  x.rowHeights[serialRow] = 18;

  return x.build();
}
