part of '../main.dart';

// Keeps track of who is logged in.

// Session: who is logged in (admin or teacher)
class AppSession {
  // kind: '' (none / Firebase admin), 'teacher', or 'hidden' (second admin)
  static String kind = '';
  static String teacherId = '';
  static String teacherName = '';
  static bool isAdmin = false; // set by RootGate
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static bool get isTeacher => !isAdmin;
  static String get userId => isAdmin ? 'admin' : teacherId;
  static String get userName => isAdmin ? 'Admin' : teacherName;

  static Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      kind = p.getString('session_kind') ?? '';
      teacherId = p.getString('session_teacher_id') ?? '';
      teacherName = p.getString('session_teacher_name') ?? '';
    } catch (_) {}
  }

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('session_kind', kind);
    await p.setString('session_teacher_id', teacherId);
    await p.setString('session_teacher_name', teacherName);
  }

  static Future<void> loginTeacher(String id, String name) async {
    kind = 'teacher';
    teacherId = id;
    teacherName = name;
    await _save();
    tick.value++;
    unawaited(_anon());
  }

  static Future<void> loginHiddenAdmin() async {
    kind = 'hidden';
    teacherId = '';
    teacherName = '';
    await _save();
    tick.value++;
    unawaited(_anon());
  }

  // Clear the old session when logging in as a Firebase admin.
  static Future<void> clearForFirebaseAdmin() async {
    kind = '';
    teacherId = '';
    teacherName = '';
    try {
      await _save();
    } catch (_) {}
  }

  // Best effort: anonymous sign-in lets teachers and the second admin pass
  // Firestore rules that need request.auth != null.
  static Future<void> _anon() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(const Duration(seconds: 6));
      }
    } catch (_) {}
  }

  static Future<void> logout() async {
    kind = '';
    teacherId = '';
    teacherName = '';
    isAdmin = false;
    try {
      await _save();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    tick.value++;
  }
}

// Ask for confirmation before logging out while offline.
Future<void> confirmAndLogout(BuildContext context) async {
  if (!await _isOnline()) {
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No internet'),
        content: const Text(
            'You are offline. If you log out now, you will not be able to log back in until internet is restored. Log out anyway?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
  }
  await AppSession.logout();
}
