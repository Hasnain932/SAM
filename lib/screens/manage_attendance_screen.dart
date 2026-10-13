part of '../main.dart';

// Edit / delete old attendance records.

// Manage attendance screen (edit / delete old records)
// Admin, or a teacher with Edit, Delete and/or Class/Lab permission (or master
// switch ON). Each button follows its own permission.
class ManageAttendanceScreen extends StatelessWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  const ManageAttendanceScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
  });

  void _confirmDelete(BuildContext context, String docId, String label) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Record?'),
        content: Text('Delete the attendance record for $label? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              unawaited(sem.dates(subjectName).doc(docId).delete().catchError((_) {}));
              unawaited(LocalDb.deleteAttendance(sem, subjectName, docId));
              if (context.mounted) showSnack(context, 'Deleted record for $label');
            },
            child: const Text('Delete', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
  }

  // Moves one session between Class and Lab Class (fixes a wrong choice).
  void _confirmChangeType(
      BuildContext context, String docId, String label, String newType) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change session type?'),
        content: Text('Change $label to ${typeLabel(newType)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Not awaited: this never completes while offline.
              unawaited(sem
                  .dates(subjectName)
                  .doc(docId)
                  .update({'_type': newType}).catchError((_) {}));
              unawaited(LocalDb.setSessionType(sem, subjectName, docId, newType));
              if (context.mounted) {
                showSnack(context, '$label is now ${typeLabel(newType)}');
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: permissionsRef().snapshots(),
      builder: (context, permSnap) {
        final perms = TeacherPerms.from(permSnap.data?.data());
        final full = AppSession.isAdmin || perms.master;
        return _buildRecords(context, full || perms.edit, full || perms.delete,
            full || perms.changeType);
      },
    );
  }

  Widget _buildRecords(BuildContext context, bool canEdit, bool canDelete,
      bool canChangeType) {
    return Scaffold(
      appBar: AppBar(title: Text('$subjectName - Records')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: liveQuery(sem.dates(subjectName)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return EmptyState(
              icon: Icons.event_busy,
              text: 'No attendance records found.',
              actionLabel: 'Mark attendance',
              // This screen is opened from the marking screen, so go back to it.
              onAction: () => Navigator.pop(context),
            );
          }

          final docs = snapshot.data!.docs.toList();
          docs.sort((a, b) => b.id.compareTo(a.id));

          return ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 24),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final docId = doc.id;

              DateTime? parsedDate;
              int? parsedSession;
              String label = docId;
              String dateText = docId; // shown on the card (date only)
              try {
                List<String> parts = docId.split('_Session_');
                parsedDate = DateFormat('yyyy-MM-dd').parse(parts[0]);
                parsedSession = int.parse(parts[1]);
                dateText = DateFormat('dd MMM yyyy').format(parsedDate);
                // Full label is still used in dialogs and messages.
                label = "$dateText - Session $parsedSession";
              } catch (e) {
                label = docId;
                dateText = docId;
              }

              final parsed = parseAttendance(doc.data());
              int presentCount = parsed.status.values.where((v) => v == 'P').length;
              int absentCount = parsed.status.values.where((v) => v == 'A').length;
              final time = fmtHhmm(parsed.meta['_time']);
              final by = parsed.meta['_marked_by_name'] ?? '';
              final isLab = parsed.meta['_type'] == kTypeLab;

              return AppCard(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                child: Row(
                  children: [
                    const IconBadge(icon: Icons.event_note, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(dateText,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                              // Session number badge, next to the date.
                              if (parsedSession != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'S$parsedSession',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              // Session type chip: quick visual cue for Class vs Lab.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isLab ? kAccent : kPresent)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: (isLab ? kAccent : kPresent)
                                          .withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  typeLabel(isLab ? kTypeLab : kTypeClass),
                                  style: TextStyle(
                                      color: isLab ? kAccent : kPresent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Present: $presentCount | Absent: $absentCount'
                            '${time.isEmpty ? '' : ' | $time'}'
                            '${by.isEmpty ? '' : ' | $by'}',
                            style: const TextStyle(color: kMuted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (canChangeType)
                    IconButton(
                      icon: const Icon(Icons.swap_horiz, color: kAccent),
                      tooltip:
                          isLab ? 'Change to Class' : 'Change to Lab Class',
                      onPressed: () => _confirmChangeType(context, docId, label,
                          isLab ? kTypeClass : kTypeLab),
                    ),
                    if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: kAccent),
                      tooltip: 'Edit',
                      onPressed: (parsedDate == null || parsedSession == null)
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SubjectAttendanceScreen(
                                    sem: sem,
                                    semLabel: semLabel,
                                    subjectName: subjectName,
                                    initialDate: parsedDate,
                                    initialSession: parsedSession,
                                  ),
                                ),
                              );
                            },
                    ),
                    if (canDelete)
                    // Red tint container makes the destructive action stand
                    // out from Edit / Change-type, which share a neutral accent.
                    Container(
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        color: kAbsent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kAbsent.withValues(alpha: 0.35)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: kAbsent),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(context, docId, label),
                      ),
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
