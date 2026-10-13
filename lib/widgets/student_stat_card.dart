part of '../main.dart';

// Student status card used by Stats and Monthly screens.

// Student status card (shared by Subject Stats and Monthly Attendance).
// Compact and centered; text sits in a Column / Expanded so nothing overflows.
class StatEntry {
  final String label;
  final bool present;
  const StatEntry(this.label, this.present);
}

// '2026-10-01_Session_2' -> '01 Oct · S2'
String prettySession(String id) {
  try {
    final parts = id.split('_Session_');
    final d = DateFormat('yyyy-MM-dd').parse(parts[0]);
    return '${DateFormat('dd MMM').format(d)} · S${parts[1]}';
  } catch (_) {
    return id;
  }
}

class StudentStatCard extends StatefulWidget {
  final String roll;
  final String name;
  final int present;
  final int absent;
  final int total;
  final List<StatEntry> entries;
  const StudentStatCard({
    super.key,
    required this.roll,
    required this.name,
    required this.present,
    required this.absent,
    required this.total,
    required this.entries,
  });

  @override
  State<StudentStatCard> createState() => _StudentStatCardState();
}

class _StudentStatCardState extends State<StudentStatCard> {
  bool _open = false;

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 1),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted, fontSize: 11.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final pct = w.total > 0 ? (w.present / w.total) * 100 : 0.0;
    final good = pct >= 75;
    final color = good ? kPresent : kAbsent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: kGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGlassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: w.entries.isEmpty ? null : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  w.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: good ? null : kAbsent,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Roll No. ${rollOf(w.roll)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 5,
                    backgroundColor: kOutline,
                    color: color,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _stat('${w.present}', 'Present', kPresent),
                    Container(width: 1, height: 26, color: kOutline),
                    _stat('${w.absent}', 'Absent', kAbsent),
                    Container(width: 1, height: 26, color: kOutline),
                    _stat('${w.total}', 'Sessions', Colors.white70),
                  ],
                ),
                if (w.entries.isNotEmpty)
                  Icon(
                    _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: kMuted,
                    size: 20,
                  ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in w.entries)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (e.present ? kPresent : kAbsent)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${e.label} · ${e.present ? 'P' : 'A'}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: e.present ? kPresent : kAbsent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

StudentStatCard buildStudentStatCard(
    Map<String, String> student, List<DateRecord> records,
    {Key? key}) {
  final roll = student['roll']!;
  int present = 0;
  int absent = 0;
  final entries = <StatEntry>[];
  for (final r in records) {
    final st = r.status[roll];
    if (st == 'P') {
      present++;
      entries.add(StatEntry(prettySession(r.id), true));
    } else if (st == 'A') {
      absent++;
      entries.add(StatEntry(prettySession(r.id), false));
    }
  }
  return StudentStatCard(
    key: key ?? ValueKey(roll),
    roll: roll,
    name: student['name'] ?? '',
    present: present,
    absent: absent,
    total: records.length,
    entries: entries,
  );
}
