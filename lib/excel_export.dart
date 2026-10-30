part of 'main.dart';

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
  int freezeCols = 3; // Roll No, Name, Father Name stay while scrolling sideways

  // Print setup. buildAttendanceExcelBytes decides these automatically.
  bool portrait = false;
  bool onePage = true; // true: whole sheet fitted on one page
  int printScale = 100; // used only when onePage is false
  final List<int> colBreaks = []; // 0-based columns where a new page starts
  String printTitles = ''; // rows / columns repeated on every printed page

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
        '<sheetPr><pageSetUpPr fitToPage="${onePage ? 1 : 0}"/></sheetPr>'
        '<sheetViews><sheetView showGridLines="0" workbookViewId="0" tabSelected="1">'
        '<pane xSplit="$freezeCols" ySplit="$freezeRows" topLeftCell="${_excelColLetters(freezeCols)}${freezeRows + 1}" activePane="bottomRight" state="frozen"/>'
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
    // Print: A4, centered. Either the whole sheet on ONE page, or several
    // pages at a fixed readable scale (see the layout decision below).
    final orient = portrait ? 'portrait' : 'landscape';
    sb.write('<printOptions horizontalCentered="1"/>'
        '<pageMargins left="0.25" right="0.25" top="0.4" bottom="0.5" '
        'header="0.3" footer="0.3"/>');
    if (onePage) {
      sb.write('<pageSetup paperSize="9" orientation="$orient" '
          'fitToWidth="1" fitToHeight="1"/>');
    } else {
      sb.write('<pageSetup paperSize="9" scale="$printScale" '
          'pageOrder="overThenDown" orientation="$orient"/>');
    }
    sb.write('<headerFooter><oddFooter>&amp;CPage &amp;P of &amp;N</oddFooter></headerFooter>');
    if (colBreaks.isNotEmpty) {
      sb.write('<colBreaks count="${colBreaks.length}" '
          'manualBreakCount="${colBreaks.length}">'
          '${colBreaks.map((c) => '<brk id="$c" max="1048575" man="1"/>').join()}'
          '</colBreaks>');
    }
    sb.write('</worksheet>');

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
    final definedNames = printTitles.isEmpty
        ? ''
        : '<definedNames><definedName name="_xlnm.Print_Titles" '
            'localSheetId="0">$printTitles</definedName></definedNames>';
    final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
        '$definedNames'
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
}) {
  final records = List<DateRecord>.from(recs)
    ..sort((a, b) => a.id.compareTo(b.id));
  final x = _XlsxBuilder();

  // ---- Colour theme (Navy Gold) ----
  const navy = 'FF1F3864';
  const head = 'FF2F4F8F';
  const gold = 'FFC9A227';
  const infoBg = 'FFEAF0FA';
  const bandA = 'FFFFFFFF';
  const bandB = 'FFF3F6FB';
  const green = 'FF1B7F3B';
  const red = 'FFD92D20';
  final titleStyle = x.style(size: 20, font: 'FFFFFFFF', bg: navy, thick: true);
  final fillerStyle = x.style(border: false);
  final infoLabelStyle =
      x.style(size: 12, font: 'FFFFFFFF', bg: navy, thick: true);
  final infoValueStyle = x.style(size: 12, font: navy, bg: infoBg, thick: true);
  final idHeadStyle =
      x.style(size: 12, font: 'FFFFFFFF', bg: head, wrap: true, thick: true);
  final totalHeadStyle =
      x.style(size: 10, font: navy, bg: gold, wrap: true, thick: true);
  final presentHeadStyle = totalHeadStyle;
  final pctHeadStyle = totalHeadStyle;
  final marksHeadStyle = totalHeadStyle;
  // Small "Lab" label above lab session columns.
  final labStyle = x.style(size: 9, font: navy, bg: gold);

  // Normal cells (two alternating row backgrounds). Bold 12 pt so the
  // printed text stays easy to read.
  const int bodySize = 12;
  final cellStyle = x.style(size: bodySize, bg: bandA);
  final cellStyleAlt = x.style(size: bodySize, bg: bandB);
  final nameStyle =
      x.style(size: bodySize, left: true, bg: bandA, shrink: true);
  final nameStyleAlt =
      x.style(size: bodySize, left: true, bg: bandB, shrink: true);
  final totalCellStyle = cellStyle;
  final totalCellStyleAlt = cellStyleAlt;
  final totalPresentStyle = cellStyle;
  final totalPresentStyleAlt = cellStyleAlt;
  final marksCellStyle = cellStyle;
  final marksCellStyleAlt = cellStyleAlt;

  // Present (P / 1) = green text, Absent (A / 0) = red text. Text colour
  // only, no coloured cell background. Colours are written straight into
  // each cell (no conditional formatting), so WPS / mobile viewers show them.
  final goodStyle = x.style(size: bodySize, font: green, bg: bandA);
  final goodStyleAlt = x.style(size: bodySize, font: green, bg: bandB);
  final badStyle = x.style(size: bodySize, font: red, bg: bandA);
  final badStyleAlt = x.style(size: bodySize, font: red, bg: bandB);

  // Header styles for weeks / dates / class numbers.
  final weekHeadStyles = [
    x.style(size: 14, font: 'FFFFFFFF', bg: head, thick: true)
  ];
  final weekDateStyles = [
    x.style(size: 10, font: navy, bg: 'FFD9E2F3', wrap: true)
  ];
  final weekSerialStyles = [
    x.style(size: 9, font: navy, bg: 'FFE9EFF9', bold: false)
  ];

  // ---- Columns ----
  const int firstSessionCol = 3; // 0 Roll No, 1 Name, 2 Father Name
  final n = records.length;
  final totalClassesCol = firstSessionCol + n;
  final presentCol = totalClassesCol + 1;
  final pctCol = totalClassesCol + 2;
  final marksCol = totalClassesCol + 3;
  final lastCol = marksCol < 11 ? 11 : marksCol;

  // ---- Rows ----
  // If the file has lab sessions, one extra row sits above the header for the
  // small "Lab" labels. Files without lab sessions keep the old layout.
  final bool hasLab = records.any((r) => r.isLab);
  final int top = hasLab ? 1 : 0;
  const int infoRow0 = 1;
  const int labRow = 4;
  final int weekRow = 4 + top;
  final int dateRow = 5 + top;
  final int serialRow = 6 + top;
  final int firstStudentRow = 7 + top;
  x.freezeRows = firstStudentRow;

  // Row 0: title, merged across the whole width, big and centered.
  x.merge(0, 0, lastCol, 0, 'University of Swabi', titleStyle);

  void infoRow(int row, String l1, Object v1, String l2, String v2) {
    x.merge(0, row, 1, row, l1, infoLabelStyle);
    if (v1 is num) {
      x.merge(2, row, 4, row, null, infoValueStyle);
      x.number(2, row, v1, infoValueStyle);
    } else {
      x.merge(2, row, 4, row, v1.toString(), infoValueStyle);
    }
    x.merge(5, row, 6, row, l2, infoLabelStyle);
    x.merge(7, row, 11, row, v2, infoValueStyle);
    for (int c = 12; c <= lastCol; c++) {
      x.blank(c, row, fillerStyle);
    }
  }

  final num marksValue =
      info.marks == info.marks.roundToDouble() ? info.marks.round() : info.marks;
  infoRow(infoRow0, 'Program', info.program, 'Course', info.course);
  infoRow(infoRow0 + 1, 'Semester', info.semester, 'Section', info.section);
  infoRow(infoRow0 + 2, 'Marks', marksValue, 'Instructor', info.instructor);
  final marksRef = '\$C\$${infoRow0 + 3}';

  // ---- Header rows: Week / Date / Class No. ----
  x.merge(0, weekRow, 0, serialRow, 'Roll No', idHeadStyle);
  x.merge(1, weekRow, 1, serialRow, 'Name', idHeadStyle);
  x.merge(2, weekRow, 2, serialRow, 'Father Name', idHeadStyle);

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

  // "Week N" merged across that week's columns, centered and big.
  int i0 = 0;
  while (i0 < n) {
    int i1 = i0;
    while (i1 + 1 < n && weekOf[i1 + 1] == weekOf[i0]) {
      i1++;
    }
    x.merge(firstSessionCol + i0, weekRow, firstSessionCol + i1, weekRow,
        'Week ${weekOf[i0]}',
        weekHeadStyles[(weekOf[i0] - 1) % weekHeadStyles.length]);
    i0 = i1 + 1;
  }

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
    final wi = (weekOf[i] - 1) % weekDateStyles.length;
    x.text(firstSessionCol + i, dateRow, dateLabel, weekDateStyles[wi]);
    x.text(firstSessionCol + i, serialRow, _ordinal(classInWeek),
        weekSerialStyles[wi]);
  }

  // "Lab" label above each lab column; class columns stay empty.
  if (hasLab) {
    for (int i = 0; i < n; i++) {
      if (records[i].isLab) {
        x.text(firstSessionCol + i, labRow, 'Lab', labStyle);
      }
    }
    x.rowHeights[labRow] = 16;
  }

  x.merge(totalClassesCol, weekRow, totalClassesCol, serialRow,
      'Total Classes', totalHeadStyle);
  x.merge(presentCol, weekRow, presentCol, serialRow, 'Total Present',
      presentHeadStyle);
  x.merge(pctCol, weekRow, pctCol, serialRow, 'Percentage of Present',
      pctHeadStyle);
  x.merge(marksCol, weekRow, marksCol, serialRow, 'Marks', marksHeadStyle);

  // ---- Student rows ----
  int rowIndex = firstStudentRow;
  int maxName = 4;
  int maxFather = 11;
  for (final st in students) {
    final roll = st['roll'] ?? '';
    final name = st['name'] ?? '';
    final father = st['father'] ?? '';
    if (name.length > maxName) maxName = name.length;
    if (father.length > maxFather) maxFather = father.length;
    int present = 0;
    final alt = (rowIndex - firstStudentRow) % 2 == 1;
    x.text(0, rowIndex, rollOf(roll), alt ? cellStyleAlt : cellStyle);
    x.text(1, rowIndex, name, alt ? nameStyleAlt : nameStyle);
    x.text(2, rowIndex, father, alt ? nameStyleAlt : nameStyle);
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
          useLetters ? 'COUNTA($first:$last)' : 'COUNT($first:$last)', n,
          alt ? totalCellStyleAlt : totalCellStyle);
      x.formula(
          presentCol,
          rowIndex,
          useLetters ? 'COUNTIF($first:$last,"P")' : 'SUM($first:$last)',
          present,
          alt ? totalPresentStyleAlt : totalPresentStyle);
      x.formula(pctCol, rowIndex, 'IF($tcRef=0,0,ROUND($tpRef/$tcRef*100,2))',
          pctRounded,
          pct >= 75
              ? (alt ? goodStyleAlt : goodStyle)
              : (alt ? badStyleAlt : badStyle));
      x.formula(marksCol, rowIndex, 'ROUND($pcRef/100*$marksRef,2)',
          marksCached, alt ? marksCellStyleAlt : marksCellStyle);
    } else {
      x.number(totalClassesCol, rowIndex, 0,
          alt ? totalCellStyleAlt : totalCellStyle);
      x.number(presentCol, rowIndex, 0,
          alt ? totalPresentStyleAlt : totalPresentStyle);
      x.number(pctCol, rowIndex, 0, alt ? badStyleAlt : badStyle);
      x.number(marksCol, rowIndex, 0, alt ? marksCellStyleAlt : marksCellStyle);
    }
    x.rowHeights[rowIndex] = 20;
    rowIndex++;
  }

  // ---- Column widths: narrow session columns, so text can print bigger ----
  x.colWidths[0] = 8;
  x.colWidths[1] = (maxName * 1.2 + 3).clamp(22, 42).toDouble();
  for (int c = 2; c <= lastCol; c++) {
    x.colWidths[c] = 6.5; // all date / info columns equal
  }
  x.colWidths[2] = (maxFather * 1.2 + 3).clamp(16, 38).toDouble();
  x.colWidths[totalClassesCol] = 8;
  x.colWidths[presentCol] = 8;
  x.colWidths[pctCol] = 10;
  x.colWidths[marksCol] = 8;

  // ---- Row heights ----
  x.rowHeights[0] = 30;
  for (int r = infoRow0; r < infoRow0 + 3; r++) {
    x.rowHeights[r] = 22;
  }
  x.rowHeights[weekRow] = 26;
  x.rowHeights[dateRow] = 30; // room for "14\nSep" on two lines
  x.rowHeights[serialRow] = 18;

  // ---- Print layout: decided automatically ----
  // 1) Try the whole sheet on ONE A4 page, portrait and landscape, and keep the
  //    better one. 2) If the text would be smaller than kMinOnePageScale (too
  //    small to read), print on SEVERAL portrait pages instead: Roll No / Name /
  //    Father Name and the header rows repeat on every page, and pages break
  //    between weeks, so the text stays big and clear.
  const double kMinOnePageScale = 0.6;
  const double a4w = 595, a4h = 842; // A4 in points
  const double marginX = 36, marginY = 65; // left+right, top+bottom
  // Default font is Arial 11, whose digit is 8 px wide, so a column of width w
  // is w * 8 px wide (the width value already includes padding).
  double ptWidth(int c) => x.colWidths[c]! * 8 * 0.75;
  double sheetW = 0;
  for (int c = 0; c <= lastCol; c++) {
    sheetW += ptWidth(c);
  }
  double sheetH = 0;
  for (final h in x.rowHeights.values) {
    sheetH += h;
  }
  double smaller(double a, double b) => a < b ? a : b;
  final double scalePortrait =
      smaller((a4w - marginX) / sheetW, (a4h - marginY) / sheetH);
  final double scaleLandscape =
      smaller((a4h - marginX) / sheetW, (a4w - marginY) / sheetH);

  if (smaller(1.0, scalePortrait > scaleLandscape ? scalePortrait : scaleLandscape) >=
      kMinOnePageScale) {
    x.onePage = true;
    x.portrait = scalePortrait >= scaleLandscape;
  } else {
    x.onePage = false;
    x.portrait = true;
    // Scale so all student rows fit one page height (between 60% and 75%).
    double s = (a4h - marginY) / sheetH * 0.98;
    if (s > 0.75) s = 0.75;
    if (s < 0.6) s = 0.6;
    final int pct = (s * 100).floor();
    x.printScale = pct;

    final double availW = (a4w - marginX) / (pct / 100) * 0.95;
    final double fixedW = ptWidth(0) + ptWidth(1) + ptWidth(2);
    final double colW = ptWidth(firstSessionCol);
    final double totalsW = ptWidth(totalClassesCol) +
        ptWidth(presentCol) +
        ptWidth(pctCol) +
        ptWidth(marksCol);
    int perPage = ((availW - fixedW) / colW).floor();
    int perLast = ((availW - fixedW - totalsW) / colW).floor();
    if (perPage < 9) perPage = 9; // info block (Program, Course...) stays whole
    if (perLast < 1) perLast = 1;

    // Page breaks: session columns per page, breaking between weeks.
    int start = 0;
    while (n - start > perLast) {
      int end = n - start <= perPage
          ? start + (n - start + 1) ~/ 2 // balance the last two pages
          : start + perPage;
      final int lowest = start + ((end - start) * 2) ~/ 3;
      for (int e = end; e > lowest; e--) {
        if (e < n && weekOf[e] != weekOf[e - 1]) {
          end = e;
          break;
        }
      }
      x.colBreaks.add(firstSessionCol + end);
      start = end;
    }

    // Repeat Roll No / Name / Father Name and the header rows on every page.
    x.printTitles =
        'Sheet1!\$A:\$C,Sheet1!\$${labRow + 1}:\$${serialRow + 1}';

    // The title bar only spans the first page, so its text is not cut.
    final int titleEnd =
        x.colBreaks.isEmpty ? lastCol : x.colBreaks.first - 1;
    x.merges.remove('A1:${_excelColLetters(lastCol)}1');
    x.merge(0, 0, titleEnd, 0, 'University of Swabi', titleStyle);
  }

  return x.build();
}
