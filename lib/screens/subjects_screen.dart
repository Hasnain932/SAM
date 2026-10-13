part of '../main.dart';

// List of subjects.

// Subjects screen (one department, section and semester)
// Admin: add / delete / open. Teacher: claim / unclaim / open (own subjects only).
class SubjectsScreen extends StatelessWidget {
  final String deptName;
  final SemRef sem;
  final String semLabel;
  const SubjectsScreen(
      {super.key,
      required this.deptName,
      required this.sem,
      required this.semLabel});

  void _confirmDeleteSubject(BuildContext context, String subjectName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Subject?'),
        content: Text(
            "Delete '$subjectName'? All of its attendance will also be permanently deleted."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await deleteSubjectEverywhere(sem, subjectName);
              if (context.mounted) {
                showSnack(context, "Deleted subject '$subjectName'");
              }
            },
            child: const Text('Delete', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameSubjectDialog(
      BuildContext context, String subjectName) async {
    final done = await showRenameDialog(
      context,
      title: 'Rename Subject',
      label: 'Subject Name',
      initial: subjectName,
      caps: TextCapitalization.characters,
      note:
          'All attendance, student changes and the teacher claim of this subject move to the new name. Internet is required.',
      onSave: (v) => renameSubjectEverywhere(sem, subjectName, v),
    );
    if (done && context.mounted) showSnack(context, 'Subject renamed');
  }

  void _showAddSubjectDialog(BuildContext context) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add New Subject'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Subject Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim().toUpperCase();
              if (name.isEmpty || name.contains('/')) return;
              // merge, so adding the same name again does not erase the claim
              unawaited(sem.subjectDoc(name).set(
                  {'name': name}, SetOptions(merge: true)).catchError((_) {}));
              unawaited(LocalDb.upsertSubject(sem, name));
              Navigator.pop(dialogContext);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _openSubject(BuildContext context, String subjectName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubjectAttendanceScreen(
          sem: sem,
          semLabel: semLabel,
          subjectName: subjectName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.isAdmin;
    final myId = AppSession.teacherId;

    return Scaffold(
      appBar: AppBar(
        title: Text('$semLabel • ${sem.section}'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.groups_outlined),
              tooltip: 'Manage Students',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManageStudentsScreen(sem: sem, semLabel: semLabel),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => _showAddSubjectDialog(context),
              backgroundColor: kButton,
              foregroundColor: kOnAccent,
              child: const Icon(Icons.add),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: liveQuery(sem.subjects.orderBy('name')),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return EmptyState(
              icon: Icons.menu_book_outlined,
              text: isAdmin
                  ? 'No subjects yet. Tap + to add.'
                  : 'No subjects here yet.',
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 90),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final subjectName = docs[index].id;
              final data = docs[index].data();
              final claimedBy = (data['claimed_by'] ?? '').toString();
              final claimedByName = (data['claimed_by_name'] ?? '').toString();
              final isMine = !isAdmin && claimedBy == myId && claimedBy.isNotEmpty;
              final takenByOther = claimedBy.isNotEmpty && !isMine;

              String? subtitle;
              if (takenByOther) {
                subtitle = 'Taken by ${claimedByName.isEmpty ? 'a teacher' : claimedByName}';
              } else if (isMine) {
                subtitle = 'Yours';
              }

              return AppCard(
                onTap: () {
                  if (isAdmin || isMine) {
                    _openSubject(context, subjectName);
                  } else if (takenByOther) {
                    showSnack(context, 'Taken by $claimedByName');
                  } else {
                    claimSubject(context, sem, subjectName);
                  }
                },
                child: Row(
                  children: [
                    IconBadge(
                      icon: Icons.menu_book_outlined,
                      color: takenByOther ? kMuted : kAccent,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subjectName,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isMine ? kPresent : kMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isAdmin) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: kAccent),
                        tooltip: 'Rename subject',
                        onPressed: () =>
                            _showRenameSubjectDialog(context, subjectName),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: kAbsent),
                        tooltip: 'Delete subject',
                        onPressed: () =>
                            _confirmDeleteSubject(context, subjectName),
                      ),
                    ] else if (isMine)
                      IconButton(
                        icon: const Icon(Icons.logout, color: kMuted),
                        tooltip: 'Leave this subject',
                        onPressed: () => unclaimSubject(context, sem, subjectName),
                      )
                    else if (!takenByOther)
                      const Icon(Icons.add_circle_outline, color: kAccent),
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
