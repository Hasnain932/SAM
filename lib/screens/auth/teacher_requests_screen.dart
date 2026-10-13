part of '../../main.dart';

// Admin approves or denies teacher sign-ups.

// ---------------------------------------------------------------------------
// Teacher approval
// Status at teachers/{id}.status: 'pending' | 'approved' | 'denied'.
// No status (older accounts) counts as approved.
// ---------------------------------------------------------------------------
String teacherStatusOf(Map<String, dynamic> data) {
  final s = (data['status'] ?? 'approved').toString();
  return (s == 'pending' || s == 'denied') ? s : 'approved';
}

// Admin icon in the Departments app bar, with a badge for pending requests.
class TeacherRequestsButton extends StatelessWidget {
  const TeacherRequestsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('teachers').snapshots(),
      builder: (context, snap) {
        final pending = snap.data?.docs
                .where((d) => teacherStatusOf(d.data()) == 'pending')
                .length ??
            0;
        return HeaderTile(
          icon: Icons.how_to_reg_outlined,
          tooltip: 'Teacher requests',
          dot: pending > 0,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TeacherRequestsScreen()),
          ),
        );
      },
    );
  }
}

class TeacherRequestsScreen extends StatelessWidget {
  const TeacherRequestsScreen({super.key});

  void _setStatus(BuildContext context, String id, String status) {
    // Not awaited: set() never completes offline. The list updates from the local cache.
    unawaited(FirebaseFirestore.instance
        .collection('teachers')
        .doc(id)
        .set({'status': status}, SetOptions(merge: true)).catchError((_) {
      if (context.mounted) {
        showSnack(context, 'Could not update the teacher.', color: kAbsent);
      }
    }));
  }

  Widget _list(BuildContext context,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String status) {
    final items = docs.where((d) => teacherStatusOf(d.data()) == status).toList()
      ..sort((a, b) => (a.data()['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b.data()['name'] ?? '').toString().toLowerCase()));
    if (items.isEmpty) {
      return EmptyState(
          icon: Icons.person_off_outlined, text: 'No $status teachers.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final d = items[i];
        final data = d.data();
        final name = (data['name'] ?? d.id).toString();
        final username = (data['username'] ?? d.id).toString();
        return AppCard(
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('@$username',
                        style: const TextStyle(color: kMuted, fontSize: 13)),
                  ],
                ),
              ),
              if (status != 'denied')
                TextButton(
                  onPressed: () => _setStatus(context, d.id, 'denied'),
                  style: TextButton.styleFrom(foregroundColor: kAbsent),
                  child: const Text('Deny'),
                ),
              if (status != 'approved')
                ElevatedButton(
                  onPressed: () => _setStatus(context, d.id, 'approved'),
                  child: const Text('Approve'),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Teacher requests'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Denied'),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('teachers').snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const EmptyState(
                  icon: Icons.cloud_off_outlined,
                  text: 'Could not load teachers.');
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            return TabBarView(
              children: [
                _list(context, docs, 'pending'),
                _list(context, docs, 'approved'),
                _list(context, docs, 'denied'),
              ],
            );
          },
        ),
      ),
    );
  }
}
