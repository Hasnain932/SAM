part of '../main.dart';

// Admin: master student list of a semester.

// Manage students screen (admin: master student list of this semester)
class ManageStudentsScreen extends StatelessWidget {
  final SemRef sem;
  final String semLabel;
  const ManageStudentsScreen({super.key, required this.sem, required this.semLabel});

  void _showStudentDialog(BuildContext context,
      {String? existingRoll, String? existingName}) {
    final rollController =
        TextEditingController(text: rollOf(existingRoll ?? ''));
    final nameController = TextEditingController(text: existingName ?? '');
    bool isEditing = existingRoll != null;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Edit Student' : 'Add Student'),
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
            onPressed: () async {
              final roll = rollController.text.trim();
              final name = nameController.text.trim();
              if (roll.isEmpty || name.isEmpty) return;

              // Roll number changed: move the student and all attendance to the new roll.
              if (existingRoll != null && roll != rollOf(existingRoll)) {
                Navigator.pop(dialogContext);
                await _changeRoll(context, existingRoll, roll, name);
                return;
              }

              // Edit: same student (existingRoll is its key). Add: if the roll exists, a new
              // unique key is created so the old student isn't overwritten.
              String key = existingRoll ?? roll;
              if (!isEditing) {
                final existing = await loadSemesterStudents(sem);
                key = uniqueStudentKey(roll, existing.map((s) => s['roll']!));
              }
              unawaited(sem.students
                  .doc(key)
                  .set({'roll': key, 'name': name}).catchError((_) {}));
              unawaited(LocalDb.upsertStudent(sem, key, name));

              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeRoll(
      BuildContext context, String oldKey, String newRoll, String name) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    String? err;
    try {
      await changeStudentRoll(sem, oldKey, newRoll, name);
    } on RenameException catch (e) {
      err = e.message;
    } catch (_) {
      err = 'Could not change the roll number. Please check your internet and try again.';
    }
    if (!context.mounted) return;
    Navigator.pop(context); // close the progress dialog
    showSnack(context, err ?? 'Roll number changed to $newRoll');
  }

  Future<void> _showCopyDialog(BuildContext context) async {
    final labels = await loadSemesterLabels(sem.deptId, sem.section);
    if (!context.mounted) return;
    String? target;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Copy students to…'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'All students of $semLabel ${sem.section} will be copied. '
                  'They stay in this semester too, and nothing in the other '
                  'semester is overwritten.',
                  style: const TextStyle(color: kMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                for (final id in kSemesterIds)
                  if (id != sem.semester)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(labels[id] ?? defaultSemesterLabel(id)),
                      trailing: target == id
                          ? const Icon(Icons.check_circle, color: kAccent)
                          : const Icon(Icons.circle_outlined, color: kMuted),
                      onTap: () => setLocal(() => target = id),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  target == null ? null : () => Navigator.pop(dialogContext, target),
              child: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final count = await copyStudentsToSemester(
        sem, SemRef(sem.deptId, sem.section, chosen));
    if (!context.mounted) return;
    final destLabel = labels[chosen] ?? defaultSemesterLabel(chosen);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count == 0
          ? 'No students to copy.'
          : '$count student${count == 1 ? '' : 's'} copied to $destLabel'),
    ));
  }

  Future<void> _importStudents(BuildContext context) async {
    final names = await pickStudentNamesFromFile(context);
    if (names == null || !context.mounted) return;
    final existing = await loadSemesterStudents(sem);
    if (!context.mounted) return;
    final taken = existing.map((s) => s['roll']!).toSet();
    final start = await confirmStudentImport(
        context, names, '$semLabel ${sem.section}',
        existingRolls: taken.map(rollOf).toSet());
    if (start == null) return;
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    for (var i = 0; i < names.length; i++) {
      // If the roll exists, a new unique key is created; nothing is overwritten.
      final key = uniqueStudentKey((start + i).toString(), taken);
      taken.add(key);
      batch.set(sem.students.doc(key), {'roll': key, 'name': names[i]});
      unawaited(LocalDb.upsertStudent(sem, key, names[i]));
      if (++ops >= 400) {
        unawaited(batch.commit().catchError((_) {}));
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    if (ops > 0) unawaited(batch.commit().catchError((_) {}));
    if (!context.mounted) return;
    _importSnack(context,
        '${names.length} student${names.length == 1 ? '' : 's'} imported (roll $start to ${start + names.length - 1})');
  }

  void _confirmDeleteStudent(BuildContext context, String roll, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student?'),
        content: Text('Delete $name (Roll ${rollOf(roll)})? This will remove them from all subjects of this semester.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              unawaited(sem.students.doc(roll).delete().catchError((_) {}));
              unawaited(LocalDb.deleteStudent(sem, roll));
            },
            child: const Text('Delete', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Students • $semLabel ${sem.section}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Import students (Excel / CSV)',
            onPressed: () => _importStudents(context),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy students to another semester',
            onPressed: () => _showCopyDialog(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showStudentDialog(context),
        backgroundColor: kButton,
        foregroundColor: kOnAccent,
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: liveQuery(sem.students),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const EmptyState(
                icon: Icons.groups_outlined,
                text: 'No students yet. Tap + to add.');
          }

          final docs = snapshot.data!.docs.toList();
          docs.sort((a, b) => compareStudentKeys(
              (a.data()['roll'] ?? a.id).toString(),
              (b.data()['roll'] ?? b.id).toString()));

          return ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 90),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final roll = (data['roll'] ?? docs[index].id).toString();
              final name = (data['name'] ?? '').toString();

              return AppCard(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    RollBadge(roll: roll),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: kAccent),
                      onPressed: () => _showStudentDialog(context,
                          existingRoll: roll, existingName: name),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: kAbsent),
                      onPressed: () => _confirmDeleteStudent(context, roll, name),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class RollBadge extends StatelessWidget {
  final String roll;
  const RollBadge({super.key, required this.roll});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 40),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(rollOf(roll),
          style: const TextStyle(
              color: kAccent, fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }
}
