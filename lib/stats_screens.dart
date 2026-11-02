part of 'main.dart';

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
  final String father;
  final int present;
  final int absent;
  final int total;
  final List<StatEntry> entries;
  const StudentStatCard({
    super.key,
    required this.roll,
    required this.name,
    this.father = '',
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
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
      // Glass card (same look as the Records / list cards): soft translucent
      // fill + thin border, no strong gradient and no glow.
      decoration: BoxDecoration(
        color: good ? kGlass : kAbsent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: good ? kGlassBorder : kAbsent.withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
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
                    color: good ? Colors.white : const Color(0xFFFFB3C0),
                  ),
                ),
                if (w.father.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('F/N ${w.father.trim()}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kMuted, fontSize: 12.5)),
                ],
                const SizedBox(height: 2),
                Text('Roll No. ${rollOf(w.roll)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: good ? kBlueGrad : kRedGrad,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                    backgroundColor: const Color(0x33FFFFFF),
                    color: color,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _stat('${w.present}', 'Present', kPresent),
                    _stat('${w.absent}', 'Absent', kAbsent),
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
  final roll = (student['roll'] ?? '');
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
    father: student['father'] ?? '',
    present: present,
    absent: absent,
    total: records.length,
    entries: entries,
  );
}

// ===========================================================================
// Panel design (used by Subject Stats and Records): one big dark rounded
// panel, lighter rounded cards inside it, cyan / pink / violet accents.
// ===========================================================================
const Color _kPanelField = Color(0xFF1B2262);

// Circular progress ring with rounded ends (starts at the top).
class _PanelRingPainter extends CustomPainter {
  final double value; // 0..1
  final Color color;
  final Color track;
  final double stroke;
  const _PanelRingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track);
    final v = value.clamp(0.0, 1.0).toDouble();
    if (v <= 0) return;
    canvas.drawArc(
        rect,
        -_kPi / 2,
        2 * _kPi * v,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_PanelRingPainter o) =>
      o.value != value ||
      o.color != color ||
      o.track != track ||
      o.stroke != stroke;
}

// Ring with a percentage in the middle.
class _PanelRing extends StatelessWidget {
  final double pct; // 0..100
  final Color color;
  final double size;
  final double stroke;
  final double fontSize;
  const _PanelRing({
    required this.pct,
    required this.color,
    required this.size,
    required this.stroke,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PanelRingPainter(
          value: pct / 100,
          color: color,
          track: color.withValues(alpha: 0.22),
          stroke: stroke,
        ),
        child: Center(
          child: Text('${pct.round()}%',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// One student's numbers for the Subject Stats screen.
class _StatRow {
  final String roll;
  final String name;
  final String father;
  final int present;
  final int absent;
  final int total;
  final List<StatEntry> entries;
  const _StatRow({
    required this.roll,
    required this.name,
    required this.father,
    required this.present,
    required this.absent,
    required this.total,
    required this.entries,
  });

  double get pct => total > 0 ? (present / total) * 100 : 0.0;
  bool get safe => pct >= 75;
  bool get perfect => total > 0 && present == total;
}

_StatRow _buildStatRow(Map<String, String> student, List<DateRecord> records) {
  final roll = student['roll'] ?? '';
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
  return _StatRow(
    roll: roll,
    name: student['name'] ?? '',
    father: student['father'] ?? '',
    present: present,
    absent: absent,
    total: records.length,
    entries: entries,
  );
}

// Student card of the Subject Stats screen.
class _SubjectStatTile extends StatefulWidget {
  final _StatRow row;
  const _SubjectStatTile({super.key, required this.row});

  @override
  State<_SubjectStatTile> createState() => _SubjectStatTileState();
}

class _SubjectStatTileState extends State<_SubjectStatTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final good = r.safe;
    final color = good ? kAccent : kAbsent;

    // Classes the student can still miss (safe) or must attend (low) to stay
    // at / get back to 75%.
    String note;
    if (r.total == 0) {
      note = 'No classes yet';
    } else if (good) {
      final x = (4 * r.present - 3 * r.total) ~/ 3;
      note = x <= 0
          ? 'Cannot miss any more classes'
          : 'Can miss $x more ${x == 1 ? 'class' : 'classes'}';
    } else {
      final y = 3 * r.total - 4 * r.present;
      note = 'Attend next $y ${y == 1 ? 'class' : 'classes'} to reach 75%';
    }

    final father = r.father.trim();
    final sub = 'Roll ${rollOf(r.roll)}${father.isEmpty ? '' : ' · F/N $father'}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: good ? const Color(0xFF16215F) : kAbsent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: good ? kGlassBorder : kAbsent.withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: r.entries.isEmpty ? null : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _PanelRing(
                        pct: r.pct,
                        color: color,
                        size: 42,
                        stroke: 4,
                        fontSize: 10.5),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 1),
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: kMuted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${r.present} P',
                            style: const TextStyle(
                                color: kAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        Text('${r.absent} A',
                            style: const TextStyle(
                                color: kAbsent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: color,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (r.entries.isNotEmpty)
                      Icon(
                        _open
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: kMuted,
                        size: 22,
                      ),
                  ],
                ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final e in r.entries)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: (e.present ? kAccent : kAbsent)
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${e.label} · ${e.present ? 'P' : 'A'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: e.present ? kAccent : kAbsent,
                                ),
                              ),
                            ),
                        ],
                      ),
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

// Subject stats screen (overall, for admin and teacher)
class SubjectStatsScreen extends StatefulWidget {
  final SemRef sem;
  final String subjectName;
  const SubjectStatsScreen({super.key, required this.sem, required this.subjectName});

  @override
  State<SubjectStatsScreen> createState() => _SubjectStatsScreenState();
}

class _SubjectStatsScreenState extends State<SubjectStatsScreen> {
  bool _loading = true;
  List<_StatRow> _rows = [];
  int _sessions = 0;
  String _query = '';
  String _filter = 'all'; // all | low | safe
  String _sort = 'roll'; // roll | low | high
  String _phase = 'all'; // all | kPhaseMid | kPhaseFinal
  List<Map<String, String>> _students = [];
  List<DateRecord> _allRecords = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Rebuilds the rows from the records of the selected phase only.
  void _applyPhase() {
    final recs = _allRecords.where((r) {
      if (_phase == kPhaseMid) return r.isMid;
      if (_phase == kPhaseFinal) return r.isFinal;
      return true;
    }).toList();
    _sessions = recs.length;
    _rows = [for (final s in _students) _buildStatRow(s, recs)];
  }

  Future<void> _load() async {
    try {
      final studentsF = loadSubjectStudents(widget.sem, widget.subjectName);
      final recordsF = loadDateRecords(widget.sem, widget.subjectName);
      final students = await studentsF;
      final records = await recordsF;
      _students = students;
      _allRecords = records;
      _applyPhase();
    } catch (e) {
      debugPrint('Stats load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _summaryCard() {
    final n = _rows.length;
    final safe = _rows.where((r) => r.safe).length;
    final low = n - safe;
    final perfect = _rows.where((r) => r.perfect).length;
    final safeOnly = safe - perfect;
    final avg =
        n == 0 ? 0.0 : _rows.fold<double>(0, (s, r) => s + r.pct) / n;

    Widget legend(Color c, String label, int count, Color countColor) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5)),
            ),
            Text('$count',
                style: TextStyle(
                    color: countColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final segs = <MapEntry<int, Color>>[
      MapEntry(perfect, kViolet),
      MapEntry(safeOnly, kAccent),
      MapEntry(low, kAbsent),
    ].where((e) => e.key > 0).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF16215F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kGlassBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CustomPaint(
                  painter: _PanelRingPainter(
                    value: avg / 100,
                    color: kAccent,
                    track: const Color(0xFF3A3A8C),
                    stroke: 8,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${avg.round()}%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                height: 1.1)),
                        const Text('Class avg',
                            style: TextStyle(color: kMuted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    legend(kAccent, 'Safe (75%+)', safe, kAccent),
                    legend(kAbsent, 'Low (below 75%)', low, kAbsent),
                    legend(kViolet, 'Perfect 100%', perfect, kViolet),
                  ],
                ),
              ),
            ],
          ),
          if (segs.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  for (var i = 0; i < segs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      flex: segs[i].key,
                      child: Container(height: 7, color: segs[i].value),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchRow() {
    const noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide(color: kGlassBorder),
    );
    PopupMenuEntry<String> sortItem(String v, String text) => PopupMenuItem<String>(
          value: v,
          child: Row(
            children: [
              Icon(_sort == v ? Icons.check : null, size: 18, color: kAccent),
              const SizedBox(width: 8),
              Text(text),
            ],
          ),
        );
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: const InputDecoration(
                hintText: 'Search student',
                hintStyle: TextStyle(color: Color(0x80FFFFFF), fontSize: 14.5),
                prefixIcon: Icon(Icons.search, color: kMuted),
                filled: true,
                fillColor: _kPanelField,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                border: noBorder,
                enabledBorder: noBorder,
                focusedBorder: noBorder,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Sort',
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            sortItem('roll', 'Roll number'),
            sortItem('low', 'Lowest attendance first'),
            sortItem('high', 'Highest attendance first'),
          ],
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kPanelField,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kGlassBorder),
            ),
            child: const Icon(Icons.swap_vert_rounded, color: kAccent, size: 21),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    var list = _rows.where((r) {
      if (_filter == 'low' && r.safe) return false;
      if (_filter == 'safe' && !r.safe) return false;
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          r.roll.toLowerCase().contains(q) ||
          rollOf(r.roll).toLowerCase().contains(q);
    }).toList();
    if (_sort == 'low') {
      list.sort((a, b) => a.pct.compareTo(b.pct));
    } else if (_sort == 'high') {
      list.sort((a, b) => b.pct.compareTo(a.pct));
    }

    Widget statPill(String label, String key) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GradPill(
            label: label,
            filled: _filter == key,
            height: 34,
            fontSize: 13.5,
            gradient: kBlueGrad,
            onTap: () => setState(() => _filter = key),
          ),
        );

    Widget phasePill(String label, String key) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GradPill(
            label: label,
            filled: _phase == key,
            height: 34,
            fontSize: 13.5,
            gradient: kBlueGrad,
            onTap: () => setState(() {
              _phase = key;
              _applyPhase();
            }),
          ),
        );

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_allRecords.isEmpty) {
      body = const EmptyState(
          icon: Icons.insights_outlined, text: 'No attendance records found.');
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: Builder(builder: (context) {
        final head = <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _summaryCard(),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _searchRow(),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  phasePill('Overall', 'all'),
                  phasePill('Mid', kPhaseMid),
                  phasePill('Final', kPhaseFinal),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  statPill('All', 'all'),
                  statPill('Low', 'low'),
                  statPill('Safe', 'safe'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (_sessions == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('No sessions in this phase.',
                      style: TextStyle(color: kMuted, fontSize: 15)),
                ),
              )
            else if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('No student matches.',
                      style: TextStyle(color: kMuted, fontSize: 15)),
                ),
              )
        ];
        // Builder: student tiles are built only when they scroll into view.
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
          itemCount: head.length + list.length,
          itemBuilder: (context, i) {
            if (i < head.length) return head[i];
            final r = list[i - head.length];
            return _SubjectStatTile(key: ValueKey(r.roll), row: r);
          },
        );
        }),
      );
    }

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Column(
          children: [
            HeaderCard(
              title: widget.subjectName,
              subtitle: 'Subject stats',
              actions: [
                if (_allRecords.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kAccent.withValues(alpha: 0.28)),
                    ),
                    child: Text(
                        '$_sessions session${_sessions == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: kAccent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

// Monthly attendance (admin and teacher): pick a month to see only that month's
// records. Read from local SQLite (works offline), refreshed first when online.
// ---- In-app attendance sheet viewer ----
// Shows the same table as the Excel file (Roll, Name, dates, totals), inside the
// app. Data comes from the same loaders as the export, so it also works offline
// (Firestore cache, then SQLite). If [month] is given, only that month is shown.
class AttendanceSheetScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  final DateTime? month;
  const AttendanceSheetScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
    this.month,
  });

  @override
  State<AttendanceSheetScreen> createState() => _AttendanceSheetScreenState();
}

class _AttendanceSheetScreenState extends State<AttendanceSheetScreen> {
  static const double _rowH = 40;
  static const double _headH = 64;
  // Only Roll + Name stay pinned on the left, so more session columns fit on
  // a phone. The Father column scrolls sideways with the table.
  static const double _rollW = 36;
  double _nameW = 110; // set from the screen width in build()
  static const double _fatherW = 110;
  static const double _cellW = 52;
  static const double _sumW = 56;

  bool _loading = true;
  bool _offline = false;
  List<Map<String, String>> _students = [];
  List<DateRecord> _all = [];
  String _scope = 'all'; // 'all', kTypeClass or kTypeLab
  String _phase = 'all'; // 'all' (Overall), kPhaseMid or kPhaseFinal
  bool _letters = true; // true: P / A, false: 1 / 0

  final ScrollController _headH1 = ScrollController();
  final ScrollController _bodyH = ScrollController();
  final ScrollController _leftV = ScrollController();
  final ScrollController _rightV = ScrollController();
  bool _syncingH = false;
  bool _syncingV = false;

  @override
  void initState() {
    super.initState();
    // Keep header and body in step when scrolling sideways.
    _bodyH.addListener(() {
      if (_syncingH || !_headH1.hasClients) return;
      _syncingH = true;
      _headH1.jumpTo(_bodyH.offset.clamp(0.0, _headH1.position.maxScrollExtent));
      _syncingH = false;
    });
    _headH1.addListener(() {
      if (_syncingH || !_bodyH.hasClients) return;
      _syncingH = true;
      _bodyH.jumpTo(_headH1.offset.clamp(0.0, _bodyH.position.maxScrollExtent));
      _syncingH = false;
    });
    // Keep the name column and the table in step when scrolling up and down.
    _rightV.addListener(() {
      if (_syncingV || !_leftV.hasClients) return;
      _syncingV = true;
      _leftV.jumpTo(_rightV.offset.clamp(0.0, _leftV.position.maxScrollExtent));
      _syncingV = false;
    });
    _leftV.addListener(() {
      if (_syncingV || !_rightV.hasClients) return;
      _syncingV = true;
      _rightV.jumpTo(_leftV.offset.clamp(0.0, _rightV.position.maxScrollExtent));
      _syncingV = false;
    });
    _load();
  }

  @override
  void dispose() {
    _headH1.dispose();
    _bodyH.dispose();
    _leftV.dispose();
    _rightV.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        loadSubjectStudents(widget.sem, widget.subjectName),
        loadDateRecords(widget.sem, widget.subjectName),
      ]);
      var offline = false;
      try {
        final c = await Connectivity().checkConnectivity();
        offline = c.every((e) => e == ConnectivityResult.none);
      } catch (e) {
        debugPrint('stats_screens.dart:1020: $e');
      }
      if (!mounted) return;
      setState(() {
        _students = r[0] as List<Map<String, String>>;
        _all = r[1] as List<DateRecord>;
        _offline = offline;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Sheet view load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, 'Could not load attendance: $e', color: kAbsent);
    }
  }

  List<DateRecord> get _records {
    var list = filterRecordsByScope(_all, _scope, phase: _phase);
    final m = widget.month;
    if (m != null) {
      final key = DateFormat('yyyy-MM').format(m);
      list = list.where((r) => r.id.startsWith(key)).toList();
    }
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  Widget _cell(String text, double w,
      {Color? color,
      FontWeight? weight,
      double size = 13,
      Color? bg,
      Alignment align = Alignment.center,
      double h = _rowH,
      EdgeInsets pad = EdgeInsets.zero}) {
    return Container(
      width: w,
      height: h,
      alignment: align,
      padding: pad,
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
          right: BorderSide(color: kOutline, width: 0.5),
          bottom: BorderSide(color: kOutline, width: 0.5),
        ),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: align == Alignment.centerLeft ? TextAlign.left : TextAlign.center,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GradPill(
        label: label,
        filled: selected,
        onTap: onTap,
        fontSize: 12.5,
      ),
    );
  }

  Widget _filters() {
    final classCount = _all.where((r) => !r.isLab).length;
    final labCount = _all.length - classCount;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          _chip('All', _scope == 'all', () => setState(() => _scope = 'all')),
          if (labCount > 0 && classCount > 0) ...[
            _chip('Class', _scope == kTypeClass,
                () => setState(() => _scope = kTypeClass)),
            _chip('Lab', _scope == kTypeLab,
                () => setState(() => _scope = kTypeLab)),
          ],
          const SizedBox(width: 8),
          _chip('Overall', _phase == 'all', () => setState(() => _phase = 'all')),
          _chip('Mid', _phase == kPhaseMid,
              () => setState(() => _phase = kPhaseMid)),
          _chip('Final', _phase == kPhaseFinal,
              () => setState(() => _phase = kPhaseFinal)),
          const SizedBox(width: 8),
          _chip('P / A', _letters, () => setState(() => _letters = true)),
          _chip('1 / 0', !_letters, () => setState(() => _letters = false)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthText =
        widget.month == null ? '' : ' - ${DateFormat('MMM yyyy').format(widget.month!)}';
    _nameW = (MediaQuery.of(context).size.width * 0.30).clamp(96.0, 150.0);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.subjectName}$monthText')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? const EmptyState(
                  icon: Icons.groups_outlined,
                  text: 'No students in this subject.')
              : _records.isEmpty
                  ? Column(
                      children: [
                        _filters(),
                        const Expanded(
                          child: EmptyState(
                              icon: Icons.event_busy,
                              text: 'No attendance recorded yet.'),
                        ),
                      ],
                    )
                  : _buildSheet(),
    );
  }

  Widget _buildSheet() {
    final recs = _records;
    final n = recs.length;

    // Week numbers, same rule as the Excel file (weeks start on Monday).
    DateTime mondayOf(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      return day.subtract(Duration(days: day.weekday - DateTime.monday));
    }

    final dates = [
      for (final r in recs) DateTime.tryParse(r.id.split('_Session_')[0])
    ];
    // Week numbers count from the first session of the whole subject.
    final allDates = [
      for (final r in _all) DateTime.tryParse(r.id.split('_Session_')[0])
    ].whereType<DateTime>().toList();
    DateTime? firstMonday;
    for (final d in allDates) {
      final m = mondayOf(d);
      if (firstMonday == null || m.isBefore(firstMonday)) firstMonday = m;
    }
    final weekOf = List<int>.filled(n, 1);
    for (int i = 0; i < n; i++) {
      final d = dates[i];
      if (d != null && firstMonday != null) {
        final md = mondayOf(d);
        weekOf[i] = DateTime.utc(md.year, md.month, md.day)
                    .difference(DateTime.utc(
                        firstMonday.year, firstMonday.month, firstMonday.day))
                    .inDays ~/
                7 +
            1;
      } else if (i > 0) {
        weekOf[i] = weekOf[i - 1];
      }
    }

    // ---- Header (pinned) ----
    final headBg = kAccent.withValues(alpha: 0.16);
    final headCells = <Widget>[];
    for (int i = 0; i < n; i++) {
      final d = dates[i];
      final label = d == null
          ? recs[i].id.split('_Session_')[0]
          : DateFormat('d MMM').format(d);
      headCells.add(Container(
        width: _cellW,
        height: _headH,
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: kOutline, width: 0.5),
            bottom: BorderSide(color: kOutline, width: 0.5),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Wk ${weekOf[i]}',
                style: const TextStyle(fontSize: 10.5, color: kMuted)),
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(recs[i].isLab ? 'Lab' : 'Class',
                style: TextStyle(
                    fontSize: 10.5,
                    color: recs[i].isLab ? kAccent2 : kMuted)),
          ],
        ),
      ));
    }
    headCells.insert(
        0,
        _cell('Father Name', _fatherW,
            weight: FontWeight.w700, size: 12, h: _headH, bg: headBg));
    headCells.addAll([
      _cell('Total', _sumW,
          weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
      _cell('Present', _sumW,
          weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
      _cell('%', _sumW,
          weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
    ]);

    // ---- Body rows ----
    final leftRows = <Widget>[];
    final rightRows = <Widget>[];
    for (int s = 0; s < _students.length; s++) {
      final st = _students[s];
      final roll = st['roll'] ?? '';
      final name = st['name'] ?? '';
      final father = (st['father'] ?? '').trim();
      final band = s.isOdd ? kGlass : null;
      int present = 0;
      final cells = <Widget>[];
      for (int i = 0; i < n; i++) {
        final isP = (recs[i].status[roll] ?? 'P') == 'P';
        if (isP) present++;
        cells.add(_cell(
          _letters ? (isP ? 'P' : 'A') : (isP ? '1' : '0'),
          _cellW,
          color: isP ? kPresent : kAbsent,
          weight: FontWeight.w600,
          bg: band,
        ));
      }
      final pct = n == 0 ? 0.0 : present / n * 100;
      cells.insert(
          0,
          _cell(father, _fatherW,
              bg: band,
              color: kMuted,
              size: 12,
              align: Alignment.centerLeft,
              pad: const EdgeInsets.symmetric(horizontal: 8)));
      cells.addAll([
        _cell('$n', _sumW, bg: band),
        _cell('$present', _sumW, bg: band),
        _cell(pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1), _sumW,
            color: pct >= 75 ? kPresent : kAbsent,
            weight: FontWeight.w700,
            bg: band),
      ]);
      leftRows.add(Row(children: [
        _cell(rollOf(roll), _rollW, bg: band, color: kMuted),
        _cell(name, _nameW,
            bg: band,
            size: 12.5,
            align: Alignment.centerLeft,
            pad: const EdgeInsets.symmetric(horizontal: 6)),
      ]));
      rightRows.add(Row(children: cells));
    }

    final rightWidth = _fatherW + _cellW * n + _sumW * 3;

    return Column(
      children: [
        if (_offline)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Offline - showing saved data',
                style: TextStyle(color: kMuted, fontSize: 12)),
          ),
        _filters(),
        // Pinned header row
        Row(
          children: [
            _cell('Roll', _rollW,
                weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
            _cell('Name', _nameW,
                weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
            Expanded(
              child: SingleChildScrollView(
                controller: _headH1,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: rightWidth,
                  child: Row(children: headCells),
                ),
              ),
            ),
          ],
        ),
        // Body: names stay on the left while the table scrolls sideways
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _rollW + _nameW,
                child: SingleChildScrollView(
                  controller: _leftV,
                  child: Column(children: leftRows),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _bodyH,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: rightWidth,
                    child: SingleChildScrollView(
                      controller: _rightV,
                      child: Column(children: rightRows),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MonthlyAttendanceScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  const MonthlyAttendanceScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
  });

  @override
  State<MonthlyAttendanceScreen> createState() =>
      _MonthlyAttendanceScreenState();
}

class _MonthlyAttendanceScreenState extends State<MonthlyAttendanceScreen> {
  late DateTime _month; // always the 1st of the month
  bool _loading = true;
  bool _syncing = false;
  List<Map<String, String>> _students = [];
  List<DateRecord> _records = [];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _init();
  }

  Future<void> _init() async {
    try {
      _students = await loadSubjectStudents(widget.sem, widget.subjectName);
    } catch (e) {
      debugPrint('Monthly students load error: $e');
    }
    await _loadMonth();
    unawaited(_refreshFromServer());
  }

  Future<void> _loadMonth({bool spinner = true}) async {
    final month = _month;
    if (spinner && mounted) setState(() => _loading = true);
    final prefix = DateFormat('yyyy-MM').format(month);
    final recs = await LocalDb.dateRecords(widget.sem, widget.subjectName,
        monthPrefix: prefix);
    if (!mounted || month != _month) return;
    setState(() {
      _records = recs;
      _loading = false;
    });
  }

  // Online: pull this subject's latest records into SQLite, then redraw.
  Future<void> _refreshFromServer() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    final ok = await LocalDb.refreshSubjectAttendance(
        widget.sem, widget.subjectName);
    if (ok) await _loadMonth(spinner: false);
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _setMonth(DateTime m) async {
    _month = DateTime(m.year, m.month);
    await _loadMonth();
  }

  Future<void> _pickMonth() async {
    int month = _month.month;
    int year = _month.year.clamp(2020, 2030).toInt();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Select month'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: month,
                items: [
                  for (int m = 1; m <= 12; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(DateFormat('MMMM').format(DateTime(2000, m))),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => month = v);
                },
              ),
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: year,
                items: [
                  for (int y = 2020; y <= 2030; y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => year = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, DateTime(year, month)),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) await _setMonth(picked);
  }

  // ---- Excel export of the selected month (admin and teacher, every subject) ----
  bool _exporting = false;

  Future<void> _exportExcel() async {
    if (_exporting || _records.isEmpty || _students.isEmpty) return;
    final opt = await askExportOptions(context, _records);
    if (opt == null || !mounted) return;
    final recs = filterRecordsByScope(_records, opt.scope, phase: opt.phase)
      ..sort((a, b) => a.id.compareTo(b.id));
    if (recs.isEmpty) {
      showSnack(context, 'No ${optionsLabel(opt)} sessions in this month.',
          color: kAbsent);
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = buildAttendanceExcelBytes(
        info: await loadExcelInfo(widget.sem, widget.subjectName),
        recs: recs,
        students: _students,
        useLetters: opt.useLetters,
        // Monthly file: no Father Name and no Marks column, so it prints bigger
        showFather: false,
        showMarks: false,
      );
      if (bytes == null) throw Exception('Excel file could not be created');

      // File name: Subject_Section_A_Semester_3_2026-10_[Class_|Lab_]Monthly_Report.xlsx
      final base =
          exportFileBase(widget.sem, widget.semLabel, widget.subjectName);
      final monthKey = DateFormat('yyyy-MM').format(_month);
      final fileName =
          '${base}_${monthKey}_${phaseFileTag(opt.phase)}${scopeFileTag(opt.scope)}Monthly_Report.xlsx';
      if (!mounted) return;
      if (kIsWeb) {
        await webShareOrDownload(context, bytes, fileName,
            text:
                '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} - ${DateFormat('MMMM yyyy').format(_month)} Attendance');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$fileName';
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        text:
            '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} - ${DateFormat('MMMM yyyy').format(_month)} Attendance',
      ));
    } catch (e) {
      debugPrint('Monthly Excel export error: $e');
      if (mounted) {
        showSnack(context, 'Could not create Excel file: $e', color: kAbsent);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildList() {
    if (_students.isEmpty) {
      return const EmptyState(
          icon: Icons.groups_outlined, text: 'No students in this subject.');
    }
    double sum = 0;
    for (final s in _students) {
      final roll = (s['roll'] ?? '');
      final p = _records.where((r) => r.status[roll] == 'P').length;
      if (_records.isNotEmpty) sum += (p / _records.length) * 100;
    }
    final avg = sum / _students.length;
    final monthKey = DateFormat('yyyy-MM').format(_month);

    // Builder: a student card is built only when it scrolls into view.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _students.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              '${_records.length} session${_records.length == 1 ? '' : 's'} • average ${avg.toStringAsFixed(1)}%',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted, fontSize: 13),
            ),
          );
        }
        final s = _students[i - 1];
        return buildStudentStatCard(s, _records,
            key: ValueKey('$monthKey-${s['roll']}'));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_month);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subjectName} - Monthly'),
        actions: [
          IconButton(
            tooltip: 'View month as sheet',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: _records.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceSheetScreen(
                          sem: widget.sem,
                          semLabel: widget.semLabel,
                          subjectName: widget.subjectName,
                          month: _month,
                        )
                      ),
                    ),
          ),
          IconButton(
            tooltip: 'Download month as Excel',
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            onPressed: (_records.isEmpty || _exporting) ? null : _exportExcel,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                  onPressed: () =>
                      _setMonth(DateTime(_month.year, _month.month - 1)),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickMonth,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(monthLabel,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, color: kAccent),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                  onPressed: () =>
                      _setMonth(DateTime(_month.year, _month.month + 1)),
                ),
              ],
            ),
          ),
          if (_syncing)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? EmptyState(
                        icon: Icons.event_busy,
                        text: 'No attendance recorded in $monthLabel.')
                    : _buildList(),
          ),
        ],
      ),
    );
  }
}
