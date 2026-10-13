part of '../main.dart';

// Data shapes for importing old attendance.

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
  ImportRow(this.name, this.roll, this.status);
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
