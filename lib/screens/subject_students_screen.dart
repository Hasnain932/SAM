part of '../main.dart';

// Students of one subject.

// Subject students (add / "remove" for this subject only)
// Soft remove: the student stays in the admin's master list and is only hidden here.
class SubjectStudentsScreen extends StatefulWidget {
  final SemRef sem;
  final String subjectName;
  const SubjectStudentsScreen(
      {super.key, required this.sem, required this.subjectName});

  @override
  State<SubjectStudentsScreen> createState() => _SubjectStudentsScreenState();
}

class _SubjectStudentsScreenState extends State<SubjectStudentsScreen> {
  bool _loading = true;
  Map<String, String> _master = {};
  // roll -> {'name': ..., 'kind': 'extra' | 'hidden'}
  Map<String, Map<String, String>> _overrides = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final masterF = loadSemesterStudents(widget.sem);
      final ovF = loadOverrides(widget.sem, widget.subjectName);
      final master = await masterF;
      _overrides = await ovF;
      _master = {for (final s in master) s['roll']!: s['name']!};
    } catch (e) {
      debugPrint('Subject students load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, String> get _effective {
    final m = Map<String, String>.from(_master);
    _overrides.forEach((roll, o) {
      if (o['kind'] == 'hidden') {
        m.remove(roll);
      } else if (o['kind'] == 'extra') {
        m[roll] = o['name'] ?? '';
      }
    });
    return m;
  }

  void _addStudent() {
    final rollController = TextEditingController();
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add student to this subject'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rollController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Roll Number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Student Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final typedRoll = rollController.text.trim();
              final name = nameController.text.trim();
              if (typedRoll.isEmpty || name.isEmpty) return;
              // If the roll already exists (master / extra / hidden), create a unique key.
              final roll = uniqueStudentKey(
                  typedRoll, [..._master.keys, ..._overrides.keys]);
              final sem = widget.sem;
              final sub = widget.subjectName;
              unawaited(sem.overrides(sub).doc(roll).set({
                'roll': roll,
                'name': name,
                'kind': 'extra',
              }).catchError((_) {}));
              unawaited(LocalDb.upsertOverride(sem, sub, roll, name, 'extra'));
              setState(() => _overrides[roll] = {'name': name, 'kind': 'extra'});
              Navigator.pop(dialogContext);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _importStudents() async {
    final names = await pickStudentNamesFromFile(context);
    if (names == null || !mounted) return;
    final taken = {..._master.keys, ..._overrides.keys};
    final start = await confirmStudentImport(
        context, names, '${widget.subjectName} (this subject)',
        existingRolls: taken.map(rollOf).toSet());
    if (start == null || !mounted) return;

    final sem = widget.sem;
    final sub = widget.subjectName;
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    final added = <String, Map<String, String>>{};
    for (var i = 0; i < names.length; i++) {
      final key = uniqueStudentKey((start + i).toString(), taken);
      taken.add(key);
      batch.set(sem.overrides(sub).doc(key),
          {'roll': key, 'name': names[i], 'kind': 'extra'});
      unawaited(LocalDb.upsertOverride(sem, sub, key, names[i], 'extra'));
      added[key] = {'name': names[i], 'kind': 'extra'};
      if (++ops >= 400) {
        unawaited(batch.commit().catchError((_) {}));
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    if (ops > 0) unawaited(batch.commit().catchError((_) {}));
    if (!mounted) return;
    setState(() => _overrides.addAll(added));
    _importSnack(context,
        '${names.length} student${names.length == 1 ? '' : 's'} imported (roll $start to ${start + names.length - 1})');
  }

  void _removeStudent(String roll, String name) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from this subject?'),
        content: Text(
            "$name (Roll ${rollOf(roll)}) will only be removed from this subject's list. They will remain in the admin's master list, and existing attendance history stays safe."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final sem = widget.sem;
              final sub = widget.subjectName;
              if (_master.containsKey(roll)) {
                // Student from the master list: add a "hidden" marker
                unawaited(sem.overrides(sub).doc(roll).set({
                  'roll': roll,
                  'name': name,
                  'kind': 'hidden',
                }).catchError((_) {}));
                unawaited(LocalDb.upsertOverride(sem, sub, roll, name, 'hidden'));
                setState(() => _overrides[roll] = {'name': name, 'kind': 'hidden'});
              } else {
                // Student added only to this subject: remove the override
                unawaited(sem.overrides(sub).doc(roll).delete().catchError((_) {}));
                unawaited(LocalDb.deleteOverride(sem, sub, roll));
                setState(() => _overrides.remove(roll));
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Remove', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _sortedStudents(_effective);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subjectName} • Students'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Import students (Excel / CSV)',
            onPressed: _importStudents,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addStudent,
        backgroundColor: kButton,
        foregroundColor: kOnAccent,
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const InfoBanner(
                  text:
                      "This list is specific to this subject. Removing a student here does not delete them from the admin's master list.",
                ),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyState(
                          icon: Icons.groups_outlined,
                          text: 'No students in this subject.')
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 6, bottom: 90),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final s = list[i];
                            return AppCard(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                              child: Row(
                                children: [
                                  RollBadge(roll: s['roll']!),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(s['name']!,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.person_remove_outlined,
                                        color: kAbsent),
                                    tooltip: 'Remove from this subject',
                                    onPressed: () =>
                                        _removeStudent(s['roll']!, s['name']!),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
