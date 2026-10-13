part of '../main.dart';

// Overall stats of a subject.

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
  List<Map<String, String>> _students = [];
  List<DateRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final studentsF = loadSubjectStudents(widget.sem, widget.subjectName);
      final recordsF = loadDateRecords(widget.sem, widget.subjectName);
      _students = await studentsF;
      _records = await recordsF;
    } catch (e) {
      debugPrint('Stats load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.subjectName} - Stats')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const EmptyState(
                  icon: Icons.insights_outlined,
                  text: 'No attendance records found.')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 6, bottom: 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: Text(
                          '${_records.length} session${_records.length == 1 ? '' : 's'} recorded',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kMuted, fontSize: 13),
                        ),
                      ),
                      for (final st in _students)
                        buildStudentStatCard(st, _records),
                    ],
                  ),
                ),
    );
  }
}
