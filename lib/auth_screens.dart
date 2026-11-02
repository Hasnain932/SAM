part of 'main.dart';

// Session: who is logged in (admin or teacher)
class AppSession {
  // kind: '' (none / Firebase admin), 'teacher', 'hidden' (second admin) or 'student'
  static String kind = '';
  // Logged-in student (kind == 'student'): u, dept, section, semester, roll, name
  static Map<String, String> student = {};
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
      final sj = p.getString('session_student') ?? '';
      if (sj.isNotEmpty) {
        final m = jsonDecode(sj) as Map;
        student = m.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      if (kind == 'student' && student.isEmpty) kind = '';
    } catch (e) {
      debugPrint('auth_screens.dart:30: $e');
    }
  }

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('session_kind', kind);
    await p.setString('session_teacher_id', teacherId);
    await p.setString('session_teacher_name', teacherName);
    await p.setString('session_student', student.isEmpty ? '' : jsonEncode(student));
  }

  static Future<void> loginTeacher(String id, String name) async {
    kind = 'teacher';
    student = {};
    teacherId = id;
    teacherName = name;
    await _save();
    await _waitAnon();
    tick.value++;
    unawaited(_anon());
  }

  // Asks the server again whether this teacher is still approved. If the
  // account was rejected or deleted, the saved session is ended. Offline or
  // on any error nothing happens, so teachers can still work without internet.
  static Future<void> recheckTeacher() async {
    if (kind != 'teacher' || teacherId.isEmpty) return;
    try {
      if (!await _isOnline()) return;
      if (!await ensureSignedIn()) return;
      final snap = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(teacherId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      if (!snap.exists || teacherStatusOf(snap.data() ?? {}) != 'approved') {
        debugPrint('teacher $teacherId is no longer approved: logging out');
        await logout();
      }
    } catch (e) {
      debugPrint('recheckTeacher failed: $e');
    }
  }

  static Future<void> loginHiddenAdmin() async {
    kind = 'hidden';
    student = {};
    teacherId = '';
    teacherName = '';
    await _save();
    await _waitAnon();
    tick.value++;
    unawaited(_anon());
  }

  // Wait (max 4 s, online only) for the anonymous sign-in before the first
  // screen opens, so the first Firestore reads already have request.auth.
  // Offline or slow: skip; liveQuery retries as a backup.
  static Future<void> _waitAnon() async {
    try {
      if (FirebaseAuth.instance.currentUser != null) return;
      final r = await Connectivity().checkConnectivity();
      if (r.every((x) => x == ConnectivityResult.none)) return;
      await _anon().timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('auth_screens.dart:72: $e');
    }
  }

  // Clear the old session when logging in as a Firebase admin.
  static Future<void> clearForFirebaseAdmin() async {
    kind = '';
    student = {};
    teacherId = '';
    teacherName = '';
    try {
      await _save();
    } catch (e) {
      debugPrint('auth_screens.dart:83: $e');
    }
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
    } catch (e) {
      debugPrint('auth_screens.dart:95: $e');
    }
  }

  // Last sign-in failure code (for a clear message instead of a vague one).
  static String lastAuthError = '';

  // Makes sure a Firebase user exists (anonymous is fine) before a read/write
  // that needs request.auth != null. Never throws; returns false if there is no
  // user. Offline it returns at once (no waiting), and after a failure it does
  // not retry for 20 s, so screens never hang on a broken sign-in.
  static Future<bool>? _signingIn;
  static DateTime _authFailAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<bool> ensureSignedIn() {
    if (FirebaseAuth.instance.currentUser != null) return Future.value(true);
    return _signingIn ??= _doSignIn().whenComplete(() => _signingIn = null);
  }

  static Future<bool> _doSignIn() async {
    try {
      if (DateTime.now().difference(_authFailAt) < const Duration(seconds: 20)) {
        return false;
      }
      if (!await _isOnline()) return false;
      await FirebaseAuth.instance
          .signInAnonymously()
          .timeout(const Duration(seconds: 8));
      return FirebaseAuth.instance.currentUser != null;
    } catch (e) {
      _authFailAt = DateTime.now();
      lastAuthError = e is FirebaseException ? e.code : e.runtimeType.toString();
      debugPrint('ensureSignedIn failed: $e');
      return false;
    }
  }

  static Future<void> loginStudent(Map<String, String> info) async {
    kind = 'student';
    student = info;
    teacherId = '';
    teacherName = '';
    await _save();
    tick.value++;
  }

  // Updates the saved student details (e.g. after the admin moved the login to
  // the next semester) without rebuilding the whole app.
  static Future<void> updateStudent(Map<String, String> info) async {
    student = info;
    await _save();
  }

  static Future<void> logout() async {
    kind = '';
    student = {};
    teacherId = '';
    teacherName = '';
    isAdmin = false;
    try {
      await _save();
    } catch (e) {
      debugPrint('auth_screens.dart:155: $e');
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('auth_screens.dart:158: $e');
    }
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
            if (AppSession.kind == 'student') {
              AppSession.isAdmin = false;
              return StudentHomeScreen(
                  key: ValueKey('student-${AppSession.student['u']}'));
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
// Welcome screen (Admin Login / Teacher Login)
// Brand on top, sign-in sheet at the bottom.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGlassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kAccent),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _glass(Widget child,
      {EdgeInsets padding = const EdgeInsets.all(12), double radius = 20}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: kGlassBorder),
      ),
      child: child,
    );
  }

  Widget _studentRow(String name, Color c1, Color c2) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c1, c2],
              ),
              boxShadow: [
                BoxShadow(
                  color: c2.withValues(alpha: 0.16),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: kAccent.withValues(alpha: 0.07),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Text('P',
                style: TextStyle(
                    color: kAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _bar(double h, Color top, Color bottom) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Container(
            height: h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom],
              ),
              borderRadius: BorderRadius.circular(5),
              boxShadow: [
                BoxShadow(
                  color: bottom.withValues(alpha: 0.45),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _hero() {
    const cap = TextStyle(
        color: kMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Floaty(
            dy: 3,
            child: _glass(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('QUICK MARKING', style: cap),
                      Text('3/3',
                          style: TextStyle(
                              color: kAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _studentRow('Hasnain', const Color(0xFF7DD3FC),
                      const Color(0xFF0EA5E9)),
                  _studentRow('Awais', const Color(0xFFA5B4FC),
                      const Color(0xFF6366F1)),
                  _studentRow('Fahad', const Color(0xFF5EEAD4),
                      const Color(0xFF0D9488)),
                ],
              ),
              radius: 24,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Floaty(
                dy: 3,
                phase: 0.4,
                child: _glass(
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                              colors: [kViolet, kAccent2]),
                          boxShadow: [
                            BoxShadow(
                              color: kViolet.withValues(alpha: 0.16),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Marked',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            Text('Present',
                                style: TextStyle(
                                    color: kAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  radius: 18,
                ),
              ),
              const SizedBox(height: 12),
              Floaty(
                dy: 3,
                phase: 0.75,
                child: _glass(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('THIS WEEK', style: cap),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 56,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _bar(22, const Color(0xFF38BDF8),
                                const Color(0xFF0284C7)),
                            _bar(36, const Color(0xFF818CF8),
                                const Color(0xFF4F46E5)),
                            _bar(30, const Color(0xFF5EEAD4),
                                const Color(0xFF0D9488)),
                            _bar(54, const Color(0xFF3B82F6),
                                const Color(0xFF1D4ED8)),
                            _bar(46, const Color(0xFF22D3EE),
                                const Color(0xFF0891B2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  radius: 18,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    void openAdmin() => Navigator.push(
          context,
          _fadeRoute((_) => const AdminLoginScreen()),
        );
    void openTeacher() => Navigator.push(
          context,
          _fadeRoute((_) => const TeacherAuthScreen()),
        );
    void openStudent() => Navigator.push(
          context,
          _fadeRoute((_) => const StudentLoginScreen()),
        );
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _BrandRingsPainter()),
          ),
          SafeArea(
            // No scrolling: everything fits on one screen. On a very short
            // phone the whole block shrinks a little (scaleDown) instead.
            child: LayoutBuilder(
              builder: (context, box) {
                final inner = box.maxWidth - 44;
                final w = inner > 480 ? 480.0 : inner;
                return Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: w,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                IconBadge(icon: Icons.school_rounded, size: 36),
                                SizedBox(width: 12),
                                Text('SAM',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 6)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _hero(),
                            const SizedBox(height: 18),
                            Floaty(
                              dy: 2,
                              phase: 0.2,
                              child: _glass(
                                const Text('Exported to Excel',
                                    style: TextStyle(
                                        color: kAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                radius: 20,
                              ),
                            ),
                            const SizedBox(height: 26),
                            const Text('Attendance,',
                                style: TextStyle(
                                    fontSize: 31,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800)),
                            ShaderMask(
                              shaderCallback: (r) => const LinearGradient(
                                      colors: [kAccent, kViolet])
                                  .createShader(r),
                              child: const Text('done in seconds.',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 31,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                                'Smart, fast and reliable. Mark, track and export for your whole university.',
                                style: TextStyle(color: kMuted, fontSize: 13.5)),
                            const SizedBox(height: 26),
                            _RoleSelector(
                              onAdmin: openAdmin,
                              onTeacher: openTeacher,
                              onStudent: openStudent,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: w,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _chip(Icons.bolt_outlined, 'Quick marking'),
                                  _chip(Icons.description_outlined,
                                      'Excel export'),
                                  _chip(Icons.cloud_off_outlined, 'Offline'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

// Role picker for the welcome screen: Admin / Teacher / Student in one control.
class _RoleSelector extends StatefulWidget {
  final VoidCallback onAdmin;
  final VoidCallback onTeacher;
  final VoidCallback onStudent;
  const _RoleSelector({
    required this.onAdmin,
    required this.onTeacher,
    required this.onStudent,
  });

  @override
  State<_RoleSelector> createState() => _RoleSelectorState();
}

class _RoleSelectorState extends State<_RoleSelector> {
  int _i = 1; // Teacher is selected first

  static const _names = ['Admin', 'Teacher', 'Student'];
  static const _icons = [
    Icons.shield_outlined,
    Icons.co_present_outlined,
    Icons.school_outlined,
  ];
  static const _desc = [
    'Manage classes, teachers and reports',
    'Mark attendance and export to Excel',
    'See your attendance and subjects',
  ];

  VoidCallback get _go =>
      [widget.onAdmin, widget.onTeacher, widget.onStudent][_i];

  Widget _seg(int i) {
    final sel = i == _i;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _i = i);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: sel ? kTileGrad : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: kAccent2.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icons[i], size: 21, color: sel ? Colors.white : kMuted),
              const SizedBox(height: 4),
              Text(
                _names[i],
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  color: sel ? Colors.white : kMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('CHOOSE YOUR ROLE',
              style: TextStyle(
                  color: kLabelBlue,
                  fontSize: 11.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700)),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0x4D0A0F2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGlassBorder),
          ),
          child: Row(children: [for (var i = 0; i < 3; i++) _seg(i)]),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Container(
            key: ValueKey(_i),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kGlass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kGlassBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: kTileGrad,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_icons[_i], color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_names[_i],
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(_desc[_i],
                          style: const TextStyle(color: kMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: GradPill(
            label: 'Continue as ${_names[_i]}',
            onTap: _go,
            expand: true,
            height: 50,
            radius: 18,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

// Faint concentric rings behind the brand on the welcome screen.
class _BrandRingsPainter extends CustomPainter {
  const _BrandRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.07);
    for (final r in const [120.0, 200.0, 280.0, 360.0]) {
      canvas.drawCircle(c, r, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Admin login screen
// Admins sign in with an email, or with a username for the second admin.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscure = true;

  static int _hiddenFails = 0;
  static DateTime? _hiddenLockUntil;

  static const String _noInternetMsg =
      "Internet connection is required to log in. Please check your connection and try again.";

  Future<void> _submit() async {
    final id = _idController.text.trim();
    final password = _passwordController.text.trim();

    if (id.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = "Both fields are required");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (id.contains('@')) {
        // ---- First admin: Firebase email/password ----
        if (_isLogin || !kAllowAdminSignUp) {
          await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: id, password: password)
              .timeout(const Duration(seconds: 10));
        } else {
          await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: id, password: password)
              .timeout(const Duration(seconds: 10));
        }
        await AppSession.clearForFirebaseAdmin();
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        // ---- Second admin: username/password from departments ----
        // Slows down guessing: 5 wrong tries lock this login for 5 minutes.
        final lock = _hiddenLockUntil;
        if (lock != null && DateTime.now().isBefore(lock)) {
          final mins = lock.difference(DateTime.now()).inMinutes + 1;
          setState(() =>
              _errorMessage = "Too many attempts. Try again in $mins min.");
          return;
        }
        final ok = await _checkHiddenAdmin(id, password);
        if (ok) {
          _hiddenFails = 0;
          _hiddenLockUntil = null;
          await AppSession.loginHiddenAdmin();
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        } else {
          _hiddenFails++;
          if (_hiddenFails >= 5) {
            _hiddenFails = 0;
            _hiddenLockUntil = DateTime.now().add(const Duration(minutes: 5));
          }
          setState(() => _errorMessage = "Incorrect email or password");
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? "Something went wrong");
    } on TimeoutException {
      setState(() => _errorMessage = _noInternetMsg);
    } catch (e) {
      setState(() => _errorMessage = _noInternetMsg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkHiddenAdmin(String username, String password) async {
    return _sha256Hex('sam|$username|$password') == kHiddenAdminHash;
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showToggle = kAllowAdminSignUp;
    return AuthShell(
      icon: Icons.admin_panel_settings_outlined,
      title: _isLogin ? 'Admin Login' : 'Create Admin Account',
      subtitle: 'Secure access to your dashboard',
      children: [
        AuthField(
          label: 'Email',
          hint: 'you@gmail.com',
          icon: Icons.person_outline,
          controller: _idController,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: 'Password',
          hint: 'Enter your password',
          icon: Icons.lock_outline,
          controller: _passwordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
        ),
        const SizedBox(height: 16),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: kAbsent),
              textAlign: TextAlign.center,
            ),
          ),
        GradientButton(
          label: _isLogin ? 'Login' : 'Sign Up',
          loading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
        if (showToggle) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() {
              _isLogin = !_isLogin;
              _errorMessage = null;
            }),
            child: Text(_isLogin
                ? "Don't have an account? Sign up"
                : "Already have an account? Login"),
          ),
        ],
      ],
    );
  }
}

// Teacher login / sign up
// Stored at teachers/{username}: name, username, pw_salt, pw_hash, status.
// The password itself is never stored, only a salted hash.
// New sign-ups start as 'pending' and need admin approval.
class TeacherAuthScreen extends StatefulWidget {
  const TeacherAuthScreen({super.key});

  @override
  State<TeacherAuthScreen> createState() => _TeacherAuthScreenState();
}

class _TeacherAuthScreenState extends State<TeacherAuthScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(username)) {
      setState(() => _error =
          'Username can only contain letters, numbers, dots, dashes or underscores');
      return;
    }

    final id = username.toLowerCase();
    final ref = FirebaseFirestore.instance.collection('teachers').doc(id);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final snap = await safeGetDocOrNull(ref);
      final exists = snap != null && snap.exists;

      if (_isLogin) {
        if (!exists) {
          // A missing doc that came from the cache (or a failed read) does not
          // prove the account is missing, so do not say so.
          final unsure = snap == null || snap.metadata.isFromCache;
          setState(() => _error = unsure
              ? 'Could not load your account. Please check your internet and try again.'
              : 'Account not found. Please sign up first.');
          return;
        }
        final data = snap.data() ?? {};
        // New accounts store only a salted hash (pw_salt + pw_hash). Old accounts
        // still have a plain 'password' field: it is accepted once, then replaced
        // by a hash right after a successful login.
        final storedHash = (data['pw_hash'] ?? '').toString();
        final legacyPlain = (data['password'] ?? '').toString();
        bool passOk;
        bool needUpgrade = false;
        if (storedHash.isNotEmpty) {
          passOk = _teacherPwHash(
                  id, (data['pw_salt'] ?? '').toString(), password) ==
              storedHash;
        } else {
          passOk = legacyPlain.isNotEmpty && legacyPlain == password;
          needUpgrade = passOk;
        }
        if (!passOk) {
          setState(() => _error = 'Incorrect username or password');
          return;
        }
        // Approval is checked at login and again later by AppSession.recheckTeacher
        // (on app start, on reconnect, every 30 min). Accounts with no status
        // (created before this feature) count as approved.
        final status = teacherStatusOf(data);
        if (status == 'pending') {
          setState(() =>
              _error = 'Your account is waiting for admin approval.');
          return;
        }
        if (status == 'denied') {
          setState(() =>
              _error = 'Your account request was rejected by the admin.');
          return;
        }
        if (needUpgrade) {
          unawaited(_upgradeTeacherPassword(ref, id, password));
        }
        final tName = (data['name'] ?? username).toString();
        unawaited(LocalDb.upsertTeacher(id, tName, username));
        await AppSession.loginTeacher(id, tName);
      } else {
        if (exists) {
          setState(() => _error = 'This username is already taken');
          return;
        }
        final salt = _newSalt();
        final newDoc = {
          'name': name,
          'username': username,
          'pw_salt': salt,
          'pw_hash': _teacherPwHash(id, salt, password),
          'status': 'pending',
        };
        if (await _isOnline()) {
          await AppSession.ensureSignedIn();
          try {
            await ref.set(newDoc).timeout(const Duration(seconds: 8));
          } on TimeoutException {
            // Slow network: Firestore keeps the write and sends it later.
          } on FirebaseException catch (e) {
            debugPrint('teacher sign up failed: ${e.code}');
            setState(() => _error =
                'Could not create the account (${e.code}). Please try again.');
            return;
          }
        } else {
          // Not awaited: set() does not complete while offline.
          unawaited(ref.set(newDoc).catchError((_) {}));
        }
        // No auto login: the admin has to approve the account first.
        if (mounted) {
          setState(() {
            _isLogin = true;
            _passwordController.clear();
            _error = null;
          });
          showSnack(context,
              'Account created. You can log in after the admin approves it.');
        }
        return;
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      setState(() => _error =
          'No saved data on this device. Please try once with an internet connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      icon: Icons.person_outline,
      title: _isLogin ? 'Teacher Login' : 'Teacher Sign Up',
      subtitle: 'Take attendance in seconds',
      children: [
        if (!_isLogin) ...[
          AuthField(
            label: 'Full name',
            hint: 'Enter your full name',
            icon: Icons.badge_outlined,
            controller: _nameController,
            capitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
        ],
        AuthField(
          label: 'Username',
          hint: 'Enter your username',
          icon: Icons.person_outline,
          controller: _usernameController,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: 'Password',
          hint: 'Enter your password',
          icon: Icons.lock_outline,
          controller: _passwordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kAbsent)),
          ),
        GradientButton(
          label: _isLogin ? 'Login' : 'Create Account',
          loading: _busy,
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() {
            _isLogin = !_isLogin;
            _error = null;
          }),
          child: Text.rich(TextSpan(
            style: const TextStyle(
                color: kAccent, fontSize: 14, fontWeight: FontWeight.w600),
            children: [
              TextSpan(
                  text: _isLogin ? 'New teacher? ' : 'Already have an account? '),
              TextSpan(
                text: _isLogin ? 'Sign up' : 'Login',
                style: const TextStyle(
                    decoration: TextDecoration.underline,
                    decorationColor: kAccent),
              ),
            ],
          )),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Teacher approval
// Status at teachers/{id}.status: 'pending' | 'approved' | 'denied'.
// No status (older accounts) counts as approved.
// ---------------------------------------------------------------------------
String teacherStatusOf(Map<String, dynamic> data) {
  final s = (data['status'] ?? 'approved').toString();
  return (s == 'pending' || s == 'denied') ? s : 'approved';
}

// ---- Teacher password hashing ----
// Random per-account salt, then repeated SHA-256 so that guessing is slower.
String _newSalt() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

String _teacherPwHash(String id, String salt, String password) {
  var h = _sha256Hex('sam-teacher|$id|$salt|$password');
  for (var i = 0; i < 2000; i++) {
    h = _sha256Hex('$h|$salt');
  }
  return h;
}

// Replaces an old plain-text password field with a salted hash (best effort).
Future<void> _upgradeTeacherPassword(
    DocumentReference<Map<String, dynamic>> ref,
    String id,
    String password) async {
  try {
    if (!await AppSession.ensureSignedIn()) return;
    final salt = _newSalt();
    await ref.update({
      'pw_salt': salt,
      'pw_hash': _teacherPwHash(id, salt, password),
      'password': FieldValue.delete(),
    }).timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('teacher password upgrade failed: $e');
  }
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

  // Denied tab only: removes the teacher account completely. The same username
  // can then sign up again (new request -> Pending -> Approve / Deny -> Delete).
  Future<void> _confirmDelete(
      BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this teacher?'),
        content: Text(
            "'$name' will be removed permanently. They can send a new request by signing up again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kAbsent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Free this teacher's subjects first (reads their claims list, which must
    // still exist), so no subject keeps showing the deleted teacher's name.
    await releaseAllClaimsOfTeacher(id);
    // Not awaited: delete() never completes offline. The list updates from the local cache.
    unawaited(FirebaseFirestore.instance
        .collection('teachers')
        .doc(id)
        .delete()
        .catchError((_) {
      if (context.mounted) {
        showSnack(context, 'Could not delete the teacher.', color: kAbsent);
      }
    }));
    unawaited(LocalDb.deleteTeacher(id));
    if (context.mounted) showSnack(context, 'Teacher deleted');
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
              if (status == 'denied')
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, d.id, name),
                  icon: const Icon(Icons.delete_outline, color: kAbsent),
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

// Seed data (written to Firestore only the first time)
final List<Map<String, String>> initialStudents = [
  {"roll": "1", "name": "Muhammad Ahmad"},
  {"roll": "2", "name": "Usman Ahmad"},
  {"roll": "3", "name": "Ahmad Khan"},
  {"roll": "4", "name": "Sadaf Gul"},
  {"roll": "5", "name": "Awais Ahmad"},
  {"roll": "6", "name": "Umaima Zubair"},
  {"roll": "7", "name": "Salman Ali"},
  {"roll": "8", "name": "Talha Khan"},
  {"roll": "9", "name": "Laila Rahim"},
  {"roll": "10", "name": "Muhammad Mustafa"},
  {"roll": "11", "name": "Ayan Khan"},
  {"roll": "12", "name": "Muhammad Umar"},
  {"roll": "13", "name": "Zarghona Khalid"},
  {"roll": "14", "name": "Salman Khan"},
  {"roll": "15", "name": "Usman Ali"},
  {"roll": "16", "name": "Abdal Ahmad"},
  {"roll": "17", "name": "Syed Lal Shah"},
  {"roll": "18", "name": "Rishail Zaman"},
  {"roll": "19", "name": "Abbas Khan"},
  {"roll": "20", "name": "Marjan Yousafzai"},
  {"roll": "21", "name": "Muhammad Hassan Anwar"},
  {"roll": "22", "name": "Muhammad Abbas"},
  {"roll": "23", "name": "Umar Azan"},
  {"roll": "24", "name": "Muhammad Ismail Khan"},
  {"roll": "25", "name": "Manahil Rehman"},
  {"roll": "26", "name": "Muhammad Shayan Gohar"},
  {"roll": "27", "name": "Rashid Amin"},
  {"roll": "28", "name": "Muhammad Umar"},
  {"roll": "29", "name": "Rayyan Javed"},
  {"roll": "30", "name": "Ibad ur Rehman"},
  {"roll": "31", "name": "Shah Fahad"},
  {"roll": "32", "name": "Umar Muzammil"},
  {"roll": "33", "name": "Abdur Rahman"},
  {"roll": "34", "name": "Muhammad Khuzaima"},
  {"roll": "35", "name": "Khubaib Hassan"},
  {"roll": "36", "name": "Zulqarnain Khan"},
  {"roll": "37", "name": "Abdul Basit"},
  {"roll": "38", "name": "Adan Pari"},
  {"roll": "39", "name": "Muhammad Hasnain"},
  {"roll": "40", "name": "Ali Khalid"},
  {"roll": "41", "name": "Akbar Mehmood"},
  {"roll": "42", "name": "Mujeeb ur Rahman"},
  {"roll": "43", "name": "Haseeb Ahmad"},
  {"roll": "44", "name": "Hanif Ullah"},
  {"roll": "45", "name": "Muhammad Daud"},
  {"roll": "46", "name": "Muhammad Kashif"},
  {"roll": "47", "name": "Akhtar Ali Shah"},
  {"roll": "48", "name": "Danish Ali Khan"},
  {"roll": "49", "name": "Muhammad Farhan"},
  {"roll": "50", "name": "Hassan Yaqoob"},
  {"roll": "51", "name": "Hilal Khan"},
  {"roll": "52", "name": "ABDULLAH"}
];

final List<String> initialSubjects = [
  "DATABASE",
  "SOFTWARE ENGINEERING",
  "DSA",
  "PAK STUDY",
  "INTRODUCTION TO MARKETING",
  "CALCULUS"
];

// Departments are created with a name only (no username or password).
final List<String> fixedDepartments = [
  "Software Engineering",
  "Computer Science",
  "Data Science",
  "Cyber Security",
  "A.I.",
];
