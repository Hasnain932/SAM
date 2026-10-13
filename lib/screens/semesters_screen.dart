part of '../main.dart';

// Pick a semester.

// Semesters screen: Section -> Semester (default 1 to 8, names can be edited)
class SemestersScreen extends StatelessWidget {
  final String deptId;
  final String deptName;
  final String section;
  const SemestersScreen(
      {super.key,
      required this.deptId,
      required this.deptName,
      required this.section});

  void _editLabelDialog(BuildContext context, SemRef sem, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename semester'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Semester name'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only the name changes — students, subjects and attendance remain under this semester.',
              style: TextStyle(color: kMuted, fontSize: 12),
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
              unawaited(sem.doc
                  .set({'label': FieldValue.delete()}, SetOptions(merge: true))
                  .catchError((_) {}));
              unawaited(LocalDb.deleteSemesterLabel(sem));
              Navigator.pop(dialogContext);
            },
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () {
              final label = controller.text.trim();
              if (label.isEmpty) return;
              unawaited(sem.doc
                  .set({'label': label}, SetOptions(merge: true))
                  .catchError((_) {}));
              unawaited(LocalDb.upsertSemesterLabel(sem, label));
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelsStream = liveQuery(FirebaseFirestore.instance
        .collection('departments')
        .doc(deptId)
        .collection('sections')
        .doc(section)
        .collection('semesters'));

    return Scaffold(
      appBar: AppBar(title: Text('$deptName • Section $section')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: labelsStream,
        builder: (context, snapshot) {
          final labels = <String, String>{};
          for (final d in snapshot.data?.docs ?? []) {
            final l = (d.data()['label'] ?? '').toString();
            if (l.isNotEmpty) labels[d.id] = l;
          }

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Choose a semester',
                    style: TextStyle(color: kMuted, fontSize: 14)),
              ),
              for (final sid in kSemesterIds)
                Builder(builder: (context) {
                  final sem = SemRef(deptId, section, sid);
                  final label = labels[sid] ?? defaultSemesterLabel(sid);
                  return AppCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubjectsScreen(
                          deptName: deptName,
                          sem: sem,
                          semLabel: label,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const IconBadge(icon: Icons.event_note_outlined),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(label,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        if (AppSession.isAdmin)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: kMuted),
                            tooltip: 'Rename semester',
                            onPressed: () => _editLabelDialog(context, sem, label),
                          )
                        else
                          const Icon(Icons.chevron_right, color: kMuted),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
