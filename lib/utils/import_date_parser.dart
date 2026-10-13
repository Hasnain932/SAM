part of '../main.dart';

// Reads dates and P / A values from cell text.

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
      } catch (_) {}
      if (dt == null) {
        try {
          dt = DateTime(inner.year as int, inner.month as int, inner.day as int);
        } catch (_) {}
      }
      if (dt != null) return DateFormat('yyyy-MM-dd').format(dt);
    }
    if (typeName.contains('Double')) {
      final d = inner.value as double;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
  } catch (_) {}
  return _excelCellText(data);
}
