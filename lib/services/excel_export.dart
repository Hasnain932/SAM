part of '../main.dart';

// Builds the attendance Excel file.

// What goes into the Excel file and how attendance is written.
class ExportOptions {
  final String scope; // 'all' (Class + Lab Class), kTypeClass or kTypeLab
  final bool useLetters; // true: P / A letters, false: 1 / 0 digits
  const ExportOptions(this.scope, this.useLetters);
}

// Sessions that belong in the file for the chosen scope.
List<DateRecord> filterRecordsByScope(List<DateRecord> recs, String scope) {
  if (scope == kTypeLab) return recs.where((r) => r.isLab).toList();
  if (scope == kTypeClass) return recs.where((r) => !r.isLab).toList();
  return List<DateRecord>.from(recs);
}

String scopeLabel(String scope) => scope == kTypeLab
    ? 'Lab Class'
    : scope == kTypeClass
        ? 'Class'
        : 'Class + Lab Class';

// Part of the file name for the scope ('' for combined).
String scopeFileTag(String scope) =>
    scope == kTypeLab ? 'Lab_' : (scope == kTypeClass ? 'Class_' : '');

// File name start: Subject_Section_A_Semester_3
String exportFileBase(SemRef sem, String semLabel, String subject) {
  String clean(String v) => v
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return [
    clean(subject),
    'Section_${clean(sem.section)}',
    clean(semLabel),
  ].where((e) => e.isNotEmpty).join('_');
}

// One dialog for both exports (overall and monthly): what to include
// (Class + Lab Class / Class only / Lab Class only) and the P/A format.
Future<ExportOptions?> askExportOptions(
    BuildContext context, List<DateRecord> recs) {
  final classCount = recs.where((r) => !r.isLab).length;
  final labCount = recs.length - classCount;
  var scope = 'all';
  var letters = true;

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
                choice('Class + Lab Class (combined)', n(recs.length),
                    scope == 'all', () => setS(() => scope = 'all')),
                choice('Class only', n(classCount), scope == kTypeClass,
                    classCount == 0 ? null : () => setS(() => scope = kTypeClass)),
                choice('Lab Class only', n(labCount), scope == kTypeLab,
                    labCount == 0 ? null : () => setS(() => scope = kTypeLab)),
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
              onPressed: () => Navigator.pop(ctx, ExportOptions(scope, letters)),
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
  final titleStyle = x.style(size: 28, font: 'FFFFFFFF', bg: navy, thick: true);
  final fillerStyle = x.style(border: false);
  final infoLabelStyle =
      x.style(size: 12, font: 'FFFFFFFF', bg: navy, thick: true);
  final infoValueStyle = x.style(size: 12, font: navy, bg: infoBg, thick: true);
  final idHeadStyle =
      x.style(size: 12, font: 'FFFFFFFF', bg: head, wrap: true, thick: true);
  final totalHeadStyle =
      x.style(size: 11, font: navy, bg: gold, wrap: true, thick: true);
  final presentHeadStyle = totalHeadStyle;
  final pctHeadStyle = totalHeadStyle;
  final marksHeadStyle = totalHeadStyle;
  // Small "Lab" label above lab session columns.
  final labStyle = x.style(size: 9, font: navy, bg: gold);

  // Normal cells (two alternating row backgrounds).
  final cellStyle = x.style(size: 11, bg: bandA);
  final cellStyleAlt = x.style(size: 11, bg: bandB);
  final nameStyle = x.style(size: 11, left: true, bg: bandA);
  final nameStyleAlt = x.style(size: 11, left: true, bg: bandB);
  final totalCellStyle = cellStyle;
  final totalCellStyleAlt = cellStyleAlt;
  final totalPresentStyle = cellStyle;
  final totalPresentStyleAlt = cellStyleAlt;
  final marksCellStyle = cellStyle;
  final marksCellStyleAlt = cellStyleAlt;

  // Present (P / 1) = green text, Absent (A / 0) = red text. Text colour
  // only, no coloured cell background. Colours are written straight into
  // each cell (no conditional formatting), so WPS / mobile viewers show them.
  final goodStyle = x.style(size: 11, font: green, bg: bandA);
  final goodStyleAlt = x.style(size: 11, font: green, bg: bandB);
  final badStyle = x.style(size: 11, font: red, bg: bandA);
  final badStyleAlt = x.style(size: 11, font: red, bg: bandB);

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
  const int firstSessionCol = 2;
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
  for (final st in students) {
    final roll = st['roll'] ?? '';
    final name = st['name'] ?? '';
    if (name.length > maxName) maxName = name.length;
    int present = 0;
    final alt = (rowIndex - firstStudentRow) % 2 == 1;
    x.text(0, rowIndex, rollOf(roll), alt ? cellStyleAlt : cellStyle);
    x.text(1, rowIndex, name, alt ? nameStyleAlt : nameStyle);
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

  // ---- Column widths: every session column the same size ----
  x.colWidths[0] = 8;
  x.colWidths[1] = (maxName * 1.1 + 4).clamp(22, 40).toDouble();
  for (int c = 2; c <= lastCol; c++) {
    x.colWidths[c] = 9; // all date / info columns equal
  }
  x.colWidths[totalClassesCol] = 9;
  x.colWidths[presentCol] = 9;
  x.colWidths[pctCol] = 12;
  x.colWidths[marksCol] = 9;

  // ---- Row heights ----
  x.rowHeights[0] = 42;
  for (int r = infoRow0; r < infoRow0 + 3; r++) {
    x.rowHeights[r] = 22;
  }
  x.rowHeights[weekRow] = 26;
  x.rowHeights[dateRow] = 22;
  x.rowHeights[serialRow] = 18;

  return x.build();
}
