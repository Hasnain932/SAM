part of '../../main.dart';

// Decides which screen to show at start.

// Root gate: shows the right screen based on the login status
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppSession.tick,
      builder: (context, _, _) {
        return StreamBuilder<User?>(
          // initialData: the saved login is known instantly, so there is no spinner offline.
          initialData: FirebaseAuth.instance.currentUser,
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            final user = snapshot.data ?? FirebaseAuth.instance.currentUser;
            if (snapshot.connectionState == ConnectionState.waiting &&
                user == null &&
                AppSession.kind.isEmpty) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (user != null && !user.isAnonymous) {
              AppSession.isAdmin = true;
              return const DepartmentsScreen(key: ValueKey('admin-root'));
            }
            if (AppSession.kind == 'hidden') {
              AppSession.isAdmin = true;
              return const DepartmentsScreen(key: ValueKey('admin-root'));
            }
            if (AppSession.kind == 'teacher') {
              AppSession.isAdmin = false;
              // Teacher home = only the subjects this teacher has claimed.
              return TeacherHomeScreen(
                  key: ValueKey('teacher-${AppSession.teacherId}'));
            }
            AppSession.isAdmin = false;
            return const WelcomeScreen();
          },
        );
      },
    );
  }
}
