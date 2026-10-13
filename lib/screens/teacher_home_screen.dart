part of '../main.dart';

// Teacher home: only the subjects they claimed.

// Teacher home: only the subjects this teacher has claimed.
// The full department list is behind the "Claim Subject" icon.
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    unawaited(syncLocalDbIfStale());
    unawaited(prefetchAllData());
    unawaited(_isOnline().then((on) => _wasOffline = !on));
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      resetNetCache();
      final isOffline = results.every((r) => r == ConnectivityResult.none);
      if (_wasOffline && !isOffline) {
        unawaited(prefetchAllData());
        unawaited(syncLocalDbIfStale());
      }
      _wasOffline = isOffline;
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _open(BuildContext context, SemRef sem, String subject) async {
    final snap = await safeGetDocOrNull(sem.subjectDoc(subject));
    final cb = (snap?.data()?['claimed_by'] ?? '').toString();
    // Remove the entry only if the server confirms the subject is gone or reassigned.
    // Offline or unreadable: just open it and never remove a claim.
    final lost = snap != null &&
        !snap.metadata.isFromCache &&
        (!snap.exists || cb != AppSession.teacherId);
    if (lost) {
      unawaited(teacherClaimsRef(AppSession.teacherId)
          .doc(sem.claimKey(subject))
          .delete()
          .catchError((_) {}));
      unawaited(LocalDb.deleteClaim(AppSession.teacherId, sem, subject));
      if (context.mounted) {
        showSnack(context, 'This subject is no longer assigned to you.');
      }
      return;
    }
    final label = (await safeGetDocOrNull(sem.doc))?.data()?['label']?.toString();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubjectAttendanceScreen(
          sem: sem,
          semLabel: (label == null || label.isEmpty)
              ? defaultSemesterLabel(sem.semester)
              : label,
          subjectName: subject,
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Map<String, String>> raw) {
    if (raw.isEmpty) {
      return const EmptyState(
        icon: Icons.bookmark_border,
        text:
            'You have not claimed any subject yet.\nTap the bookmark icon (top right) to claim one.',
      );
    }
    final items = raw.toList()
      ..sort((a, b) => (a['subject'] ?? '').compareTo(b['subject'] ?? ''));

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final c = items[i];
        final dept = c['dept'] ?? '';
        final section = c['section'] ?? '';
        final semId = c['semester'] ?? '';
        final subject = c['subject'] ?? '';
        final sem = SemRef(dept, section, semId);

        return AppCard(
          onTap: () => _open(context, sem, subject),
          child: Row(
            children: [
              const IconBadge(icon: Icons.menu_book_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(dept,
                            style:
                                const TextStyle(color: kMuted, fontSize: 12.5)),
                        const Text('/',
                            style: TextStyle(color: kMuted, fontSize: 12.5)),
                        Text('Section $section',
                            style:
                                const TextStyle(color: kMuted, fontSize: 12.5)),
                        const Text('/',
                            style: TextStyle(color: kMuted, fontSize: 12.5)),
                        SemLabelText(
                          sem: sem,
                          style: const TextStyle(color: kMuted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: kMuted),
                tooltip: 'Leave this subject',
                onPressed: () => unclaimSubject(context, sem, subject),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hello, ${AppSession.teacherName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Claim Subject',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DepartmentsScreen(claimMode: true)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => confirmAndLogout(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: liveQuery(teacherClaimsRef(AppSession.teacherId)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final snap = snapshot.data;
          final items = <Map<String, String>>[
            for (final d
                in snap?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              {
                'dept': (d.data()['dept'] ?? '').toString(),
                'section': (d.data()['section'] ?? '').toString(),
                'semester': (d.data()['semester'] ?? '').toString(),
                'subject': (d.data()['subject'] ?? '').toString(),
              }
          ];
          // Nothing in the Firestore cache? Use the SQLite copy of the claims.
          if (items.isEmpty && (snap == null || snap.metadata.isFromCache)) {
            return FutureBuilder<List<Map<String, String>>>(
              future: LocalDb.claimsOf(AppSession.teacherId),
              builder: (context, f) {
                if (!f.hasData) return const SizedBox.shrink();
                return _buildList(context, f.data!);
              },
            );
          }
          return _buildList(context, items);
        },
      ),
    );
  }
}
