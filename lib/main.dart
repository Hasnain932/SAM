import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart' as zip;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'download_stub.dart'
    if (dart.library.html) 'download_web.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0E6275),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // On the web, SQLite runs through the ffi-web factory (IndexedDB based).
  if (kIsWeb) {
    sql.databaseFactory = databaseFactoryFfiWeb;
  }
  // Read the saved login while Firebase starts (saves start-up time).
  final sessionReady = AppSession.restore();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBlokxXBdPiOPCC0P6P7DtS72tSruzJcHk",
      authDomain: "attendance-app-26577.firebaseapp.com",
      projectId: "attendance-app-26577",
      storageBucket: "attendance-app-26577.firebasestorage.app",
      messagingSenderId: "1095236912937",
      appId: "1:1095236912937:web:8c4871cc43129d14a2d938",
      measurementId: "G-S2WWMZSVFS",
    ),
  );

  // Keep a copy of the data on the device. Changes made offline sync
  // automatically once the internet is back.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await sessionReady;
  runApp(const AttendanceApp());
}

// App-wide constants
const List<String> kSections = ['A', 'B', 'C', 'D'];
const List<String> kSemesterIds = ['1', '2', '3', '4', '5', '6', '7', '8'];

// Teachers can mark attendance only in the first 20 minutes of each hour.
const int kMarkWindowMinutes = 20;

// Time picker range: 6:00 AM to 6:00 PM.
const int kPickerStartHour = 6;
const int kPickerEndHour = 18;

// Lets people create a new admin account on the Admin Login screen. It is false
// because teachers also sign up in this app, and otherwise any teacher could
// become an admin. Create new admins from the Firebase console.
const bool kAllowAdminSignUp = false;

// ---- Second (hidden) admin ----
// Stored like a normal department. The app finds this admin only by matching
// the username. You can change the department name to anything ordinary.
const String kHiddenAdminDeptName = 'Information Technology';
const String kHiddenAdminUsername = 'BUDDY';
const String kHiddenAdminPassword = 'buddy11';

const String kSoftwareEngineeringDeptId = "Software Engineering";

// Theme and colors: "Aurora Glass" - deep navy to teal gradient background,
// frosted glass cards, white pill buttons. Green means present, red means absent.
const Color kBgTop = Color(0xFF1A1245);
const Color kBgMid = Color(0xFF10285C);
const Color kBgBottom = Color(0xFF0E6275);
const Color kBg = kBgMid;
const Color kSurface = Color(0xFF10285C); // solid navy: dialogs, menus
const Color kSurfaceHi = Color(0xFF173A70);
const Color kGlass = Color(0x1AFFFFFF); // glass card fill (10% white)
const Color kGlassBorder = Color(0x2EFFFFFF); // glass card border (18% white)
const Color kOutline = Color(0x33FFFFFF);
const Color kAccent = Color(0xFF7DD3C0); // light teal: icons, highlights
const Color kOnAccent = Color(0xFF0D2A66); // dark navy: text on white buttons
const Color kButton = Colors.white; // primary pill buttons
const Color kPresent = Color(0xFF6EE7B7);
const Color kAbsent = Color(0xFFFF8FA0);
const Color kMuted = Color(0xFFB4C3DC);

const LinearGradient kAuroraGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kBgTop, kBgMid, kBgBottom],
);

// Paints the aurora gradient behind a page.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: kAuroraGradient),
      child: child,
    );
  }
}

// Light page transition for the web (a plain fade).
class _WebFadeTransitions extends PageTransitionsBuilder {
  const _WebFadeTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

// Pages are transparent, so every route gets its own gradient. This stops the
// previous page from showing through while a page slides in.
class _AuroraTransitions extends PageTransitionsBuilder {
  final PageTransitionsBuilder inner;
  const _AuroraTransitions(this.inner);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return inner.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      AuroraBackground(child: child),
    );
  }
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kAccent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: kAccent,
      onPrimary: kOnAccent,
      secondary: kAccent,
      surface: kSurface,
      onSurface: Colors.white,
      outline: kOutline,
      error: kAbsent,
    );
    const pillShape = StadiumBorder();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SAM',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: kSurface,
        dividerColor: kOutline,
        pageTransitionsTheme: kIsWeb
            ? const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android:
                      _AuroraTransitions(_WebFadeTransitions()),
                  TargetPlatform.iOS: _AuroraTransitions(_WebFadeTransitions()),
                  TargetPlatform.macOS:
                      _AuroraTransitions(_WebFadeTransitions()),
                  TargetPlatform.windows:
                      _AuroraTransitions(_WebFadeTransitions()),
                  TargetPlatform.linux:
                      _AuroraTransitions(_WebFadeTransitions()),
                  TargetPlatform.fuchsia:
                      _AuroraTransitions(_WebFadeTransitions()),
                },
              )
            : const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android:
                      _AuroraTransitions(ZoomPageTransitionsBuilder()),
                  TargetPlatform.iOS:
                      _AuroraTransitions(CupertinoPageTransitionsBuilder()),
                  TargetPlatform.macOS:
                      _AuroraTransitions(CupertinoPageTransitionsBuilder()),
                  TargetPlatform.windows:
                      _AuroraTransitions(ZoomPageTransitionsBuilder()),
                  TargetPlatform.linux:
                      _AuroraTransitions(ZoomPageTransitionsBuilder()),
                  TargetPlatform.fuchsia:
                      _AuroraTransitions(ZoomPageTransitionsBuilder()),
                },
              ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kButton,
            foregroundColor: kOnAccent,
            disabledBackgroundColor: const Color(0x33FFFFFF),
            disabledForegroundColor: const Color(0x80FFFFFF),
            elevation: 0,
            shape: pillShape,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0x0FFFFFFF),
            side: const BorderSide(color: Color(0x4DFFFFFF)),
            shape: pillShape,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kAccent),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kButton,
          foregroundColor: kOnAccent,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          shape: StadiumBorder(),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kGlass,
          labelStyle: const TextStyle(color: kMuted),
          hintStyle: const TextStyle(color: Color(0x80FFFFFF)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kGlassBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kGlassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kAccent, width: 1.5),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: kGlassBorder),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: kSurfaceHi,
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: kSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kGlassBorder),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
        ),
        datePickerTheme: const DatePickerThemeData(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
        ),
        timePickerTheme: const TimePickerThemeData(
          backgroundColor: kSurface,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: kMuted,
          indicatorColor: kAccent,
          dividerColor: Colors.transparent,
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? const Color(0x40FFFFFF)
                    : Colors.transparent),
            foregroundColor: WidgetStateProperty.all(Colors.white),
            side: WidgetStateProperty.all(
                const BorderSide(color: Color(0x4DFFFFFF))),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.all(Colors.white),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? kAccent
                  : const Color(0x33FFFFFF)),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? kAccent
                  : Colors.transparent),
          checkColor: WidgetStateProperty.all(kOnAccent),
          side: const BorderSide(color: Color(0x80FFFFFF), width: 1.5),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: kAccent,
          linearTrackColor: kOutline,
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Colors.white,
          iconColor: kAccent,
        ),
        dividerTheme: const DividerThemeData(color: kOutline),
      ),
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
      home: const RootGate(),
    );
  }
}

// ---- Small reusable widgets ----
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double blur;
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    this.radius = 20,
    this.blur = 10,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final card = Material(
      color: kGlass,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: kGlassBorder),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: r,
        // Web: no blur. BackdropFilter per card makes the page slow there, and
        // on this smooth gradient background the blur is hardly visible anyway.
        child: kIsWeb
            ? card
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: card,
              ),
      ),
    );
  }
}

// Round P / A button used on the attendance screen.
class AttendanceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  const AttendanceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color : Colors.transparent,
            border: Border.all(
              color: selected ? color : const Color(0x4DFFFFFF),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: selected ? kOnAccent : const Color(0xB3FFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(
      {super.key, required this.icon, this.color = kAccent, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: kMuted),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const InfoBanner(
      {super.key,
      required this.text,
      this.icon = Icons.info_outline,
      this.color = kAccent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String msg, {Color? color}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: color),
  );
}

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

  // Best effort: if the Firestore rules need request.auth != null, an anonymous
  // sign-in lets teachers and the second admin through.
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
// Root gate: shows the right screen based on the login status
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppSession.tick,
      builder: (context, _, _) {
        return StreamBuilder<User?>(
          // initialData: the saved login is known immediately, so there is
          // no spinner on start-up (important when the phone is offline).
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
// Welcome screen (Admin Login / Teacher Login)
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppCard(
                radius: 32,
                blur: 16,
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // SAM logo: glass tile + graduation cap
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: const Color(0x1FFFFFFF),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0x40FFFFFF)),
                      ),
                      child: const Icon(Icons.school_rounded,
                          color: Colors.white, size: 56),
                    ),
                    const SizedBox(height: 22),
                    const Text('SAM',
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 10)),
                    const SizedBox(height: 8),
                    Text('Smart Attendance',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: kAccent.withValues(alpha: 0.95),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 3)),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminLoginScreen()),
                        ),
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Admin Login',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TeacherAuthScreen()),
                        ),
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Teacher Login / Sign Up',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
        // ---- Second admin: username/password from the departments collection
        // ----
        final ok = await _checkHiddenAdmin(id, password);
        if (ok) {
          await AppSession.loginHiddenAdmin();
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        } else {
          setState(() => _errorMessage = "Incorrect username or password");
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
    if (username != kHiddenAdminUsername) return false;
    final snap = await safeGetQuery(FirebaseFirestore.instance
        .collection('departments')
        .where('username', isEqualTo: username));
    for (final d in snap.docs) {
      if ((d.data()['password'] ?? '').toString() == password) return true;
    }
    return false;
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
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const IconBadge(
                  icon: Icons.admin_panel_settings_outlined, size: 72),
              const SizedBox(height: 16),
              Text(
                _isLogin ? 'Admin Login' : 'Create Admin Account',
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _idController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email or username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
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
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: kOnAccent, strokeWidth: 2),
                        )
                      : Text(
                          _isLogin ? 'Login' : 'Sign Up',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
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
          ),
        ),
      ),
    );
  }
}

// Teacher login / sign up
// Stored at teachers/{username}: name, username, password, status.
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
          setState(() => _error = 'Account not found. Please sign up first.');
          return;
        }
        final data = snap.data() ?? {};
        if ((data['password'] ?? '').toString() != password) {
          setState(() => _error = 'Incorrect username or password');
          return;
        }
        // Approval is checked only here, at login. Once approved, the saved
        // local session is used and the server is never asked again.
        // Teachers without a status (created before this feature) count as
        // approved.
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
        final tName = (data['name'] ?? username).toString();
        unawaited(LocalDb.upsertTeacher(id, tName, username));
        await AppSession.loginTeacher(id, tName);
      } else {
        if (exists) {
          setState(() => _error = 'This username is already taken');
          return;
        }
        // Not awaited: set() does not complete while offline.
        unawaited(ref.set({
          'name': name,
          'username': username,
          'password': password,
          'status': 'pending',
        }).catchError((_) {}));
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
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const IconBadge(icon: Icons.person_outline, size: 72),
              const SizedBox(height: 16),
              Text(_isLogin ? 'Teacher Login' : 'Teacher Sign Up',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              if (!_isLogin) ...[
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _usernameController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kAbsent)),
                ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: kOnAccent, strokeWidth: 2))
                      : Text(_isLogin ? 'Login' : 'Create Account',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _isLogin = !_isLogin;
                  _error = null;
                }),
                child: Text(_isLogin
                    ? "New teacher? Sign up"
                    : "Already have an account? Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teacher approval
// Status is stored at teachers/{id}.status: 'pending' | 'approved' | 'denied'.
// Teachers without a status (created before this feature) count as approved.
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
        return IconButton(
          tooltip: 'Teacher requests',
          icon: Badge(
            isLabelVisible: pending > 0,
            label: Text('$pending'),
            child: const Icon(Icons.how_to_reg_outlined),
          ),
          onPressed: () => Navigator.push(
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
    // Not awaited: set() does not complete while offline. The list updates
    // from the local cache right away and syncs when internet is back.
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

// Firestore path helpers
// departments/{dept}/sections/{A-D}/semesters/{1-8}/
//     students/{key}      key = roll; duplicate rolls become roll__2, roll__3 ...
//     subjects/{name}                    (claimed_by, claimed_by_name)
//     subjects/{name}/overrides/{roll}   (subject-level add / soft-remove)
//     attendance/{subject}/dates/{date_Session_n}
class SemRef {
  final String deptId;
  final String section;
  final String semester;
  const SemRef(this.deptId, this.section, this.semester);

  DocumentReference<Map<String, dynamic>> get doc => FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .collection('sections')
      .doc(section)
      .collection('semesters')
      .doc(semester);

  CollectionReference<Map<String, dynamic>> get students =>
      doc.collection('students');
  CollectionReference<Map<String, dynamic>> get subjects =>
      doc.collection('subjects');
  DocumentReference<Map<String, dynamic>> subjectDoc(String subject) =>
      subjects.doc(subject);
  CollectionReference<Map<String, dynamic>> overrides(String subject) =>
      subjectDoc(subject).collection('overrides');
  CollectionReference<Map<String, dynamic>> dates(String subject) =>
      doc.collection('attendance').doc(subject).collection('dates');

  String claimKey(String subject) => '$deptId|$section|$semester|$subject';
}

String defaultSemesterLabel(String semesterId) => 'Semester $semesterId';

CollectionReference<Map<String, dynamic>> teacherClaimsRef(String teacherId) =>
    FirebaseFirestore.instance
        .collection('teachers')
        .doc(teacherId)
        .collection('claims');

DocumentReference<Map<String, dynamic>> permissionsRef() =>
    FirebaseFirestore.instance.collection('settings').doc('permissions');

// ---- Teacher permissions (settings/permissions) ----
// kPermMaster is the master switch: when ON, teachers can do everything.
// When it is OFF, each of the detailed permissions below applies on its own.
// A missing field means "not allowed", so nothing changes for old data.
const String kPermMaster = 'teachers_unrestricted';
const String kPermAnytime = 'perm_anytime'; // mark outside the 20-minute window
const String kPermChangeTime = 'perm_change_time'; // pick the class time
const String kPermChangeDate = 'perm_change_date'; // pick other / past dates
const String kPermEdit = 'perm_edit'; // edit existing records
const String kPermDelete = 'perm_delete'; // delete records
const List<String> kDetailedPerms = [
  kPermAnytime,
  kPermChangeTime,
  kPermChangeDate,
  kPermEdit,
  kPermDelete,
];

class TeacherPerms {
  final bool master;
  final bool anytime;
  final bool changeTime;
  final bool changeDate;
  final bool edit;
  final bool delete;
  const TeacherPerms({
    this.master = false,
    this.anytime = false,
    this.changeTime = false,
    this.changeDate = false,
    this.edit = false,
    this.delete = false,
  });

  static const TeacherPerms none = TeacherPerms();

  factory TeacherPerms.from(Map<String, dynamic>? d) {
    if (d == null) return none;
    return TeacherPerms(
      master: d[kPermMaster] == true,
      anytime: d[kPermAnytime] == true,
      changeTime: d[kPermChangeTime] == true,
      changeDate: d[kPermChangeDate] == true,
      edit: d[kPermEdit] == true,
      delete: d[kPermDelete] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TeacherPerms &&
      other.master == master &&
      other.anytime == anytime &&
      other.changeTime == changeTime &&
      other.changeDate == changeDate &&
      other.edit == edit &&
      other.delete == delete;

  @override
  int get hashCode =>
      Object.hash(master, anytime, changeTime, changeDate, edit, delete);
}

// ---- Old paths (from before sections existed), used only for migration and
// delete ----
CollectionReference<Map<String, dynamic>> legacyStudentsRef(String deptId) =>
    FirebaseFirestore.instance
        .collection('departments')
        .doc(deptId)
        .collection('students');

CollectionReference<Map<String, dynamic>> legacySubjectsRef(String deptId) =>
    FirebaseFirestore.instance
        .collection('departments')
        .doc(deptId)
        .collection('subjects');

CollectionReference<Map<String, dynamic>> legacyDatesRef(
    String deptId, String subjectName) {
  if (deptId == kSoftwareEngineeringDeptId) {
    return FirebaseFirestore.instance
        .collection('attendance')
        .doc(subjectName)
        .collection('dates');
  }
  return FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .collection('attendance')
      .doc(subjectName)
      .collection('dates');
}

// Offline-safe read helpers
const Duration _kNetworkTimeout = Duration(seconds: 2);
// Web: do not make every screen wait for the server. After this time the
// cached copy is shown (the server read keeps running and refreshes the cache).
const Duration _kReadTimeout =
    kIsWeb ? Duration(milliseconds: 900) : _kNetworkTimeout;

// Wi-Fi being connected does not always mean the internet works. _netState()
// adds a quick DNS check (cached for a few seconds). When the phone is
// connected but offline, we go straight to the local cache instead of waiting
// for a timeout on every screen. That waiting was the cause of the endless
// loading.
enum _Net { none, unreachable, reachable }

_Net? _netCache;
DateTime _netCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

void resetNetCache() {
  _netCache = null;
}

Future<_Net> _netState() async {
  bool linked = true;
  try {
    final r = await Connectivity().checkConnectivity();
    linked = !r.contains(ConnectivityResult.none);
  } catch (_) {}
  if (!linked) {
    _netCache = _Net.none;
    _netCacheAt = DateTime.now();
    return _Net.none;
  }
  final cached = _netCache;
  if (cached != null && cached != _Net.none) {
    final ttl = cached == _Net.reachable
        ? const Duration(seconds: 10)
        : const Duration(seconds: 4);
    if (DateTime.now().difference(_netCacheAt) < ttl) return cached;
  }
  // InternetAddress.lookup is not available on the web; the connectivity
  // check above is enough there.
  if (kIsWeb) {
    _netCache = _Net.reachable;
    _netCacheAt = DateTime.now();
    return _Net.reachable;
  }
  _Net result;
  try {
    final res = await InternetAddress.lookup('firestore.googleapis.com')
        .timeout(const Duration(seconds: 3));
    result = res.isNotEmpty ? _Net.reachable : _Net.unreachable;
  } catch (_) {
    result = _Net.unreachable;
  }
  _netCache = result;
  _netCacheAt = DateTime.now();
  return result;
}

Future<bool> _isOnline() async {
  try {
    final r = await Connectivity().checkConnectivity();
    return !r.contains(ConnectivityResult.none);
  } catch (_) {
    return true;
  }
}

Future<DocumentSnapshot<Map<String, dynamic>>> safeGetDoc(
    DocumentReference<Map<String, dynamic>> ref) async {
  const cacheOnly = GetOptions(source: Source.cache);
  final net = await _netState();
  if (net == _Net.reachable) {
    final server = ref.get();
    server.ignore();
    try {
      return await server.timeout(_kReadTimeout);
    } catch (_) {}
    try {
      return await ref.get(cacheOnly);
    } catch (_) {
      // Not cached yet: give the server a little more time.
      return server.timeout(const Duration(seconds: 8));
    }
  }
  try {
    final c = await ref.get(cacheOnly);
    if (c.exists || net == _Net.none) return c;
  } catch (_) {
    if (net == _Net.none) rethrow;
  }
  return ref.get().timeout(_kNetworkTimeout);
}

Future<DocumentSnapshot<Map<String, dynamic>>?> safeGetDocOrNull(
    DocumentReference<Map<String, dynamic>> ref) async {
  try {
    return await safeGetDoc(ref);
  } catch (_) {
    return null;
  }
}

Future<QuerySnapshot<Map<String, dynamic>>> safeGetQuery(
    Query<Map<String, dynamic>> query) async {
  const cacheOnly = GetOptions(source: Source.cache);
  final net = await _netState();
  if (net == _Net.reachable) {
    final server = query.get();
    server.ignore();
    try {
      return await server.timeout(_kReadTimeout);
    } catch (_) {}
    final cached = await query.get(cacheOnly);
    if (cached.docs.isNotEmpty) return cached;
    // Nothing cached: wait a bit longer for the server instead of showing an
    // empty list.
    try {
      return await server.timeout(const Duration(seconds: 8));
    } catch (_) {
      return cached;
    }
  }
  final cached = await query.get(cacheOnly);
  if (cached.docs.isNotEmpty || net == _Net.none) return cached;
  try {
    return await query.get().timeout(_kNetworkTimeout);
  } catch (_) {
    return cached;
  }
}

class _QRes {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool fromCache;
  const _QRes(this.docs, this.fromCache);
}

// Never throws. On any failure it returns an empty result marked as from cache.
Future<_QRes> _safeQuery(Query<Map<String, dynamic>> query) async {
  try {
    final snap = await safeGetQuery(query);
    return _QRes(snap.docs, snap.metadata.isFromCache);
  } catch (_) {
    return const _QRes([], true);
  }
}

// Cache-first live query for StreamBuilders. The first result comes from the
// device cache right away, then live updates take over.
Stream<QuerySnapshot<Map<String, dynamic>>> liveQuery(
    Query<Map<String, dynamic>> q) {
  late final StreamController<QuerySnapshot<Map<String, dynamic>>> ctrl;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
  bool gotLive = false;
  bool cancelled = false;
  ctrl = StreamController<QuerySnapshot<Map<String, dynamic>>>(
    onListen: () {
      sub = q.snapshots().listen(
        (snap) {
          gotLive = true;
          if (!cancelled) ctrl.add(snap);
        },
        onError: (Object e, StackTrace st) {
          if (!cancelled) ctrl.addError(e, st);
        },
      );
      unawaited(() async {
        try {
          final cached = await q.get(const GetOptions(source: Source.cache));
          if (gotLive || cancelled) return;
          if (cached.docs.isNotEmpty) {
            ctrl.add(cached);
            return;
          }
          // Empty cache: give the live stream a moment, then show the empty
          // result instead of loading forever.
          await Future.delayed(const Duration(milliseconds: 1500));
          if (!gotLive && !cancelled) ctrl.add(cached);
        } catch (_) {}
      }());
    },
    onCancel: () async {
      cancelled = true;
      await sub?.cancel();
    },
  );
  return ctrl.stream;
}

// An attendance doc is {roll: 'P'/'A', ...} plus meta keys that start with '_':
// _time (HH:mm), _marked_by, _marked_by_name.
class ParsedAttendance {
  final Map<String, String> status;
  final Map<String, String> meta;
  ParsedAttendance(this.status, this.meta);
}

ParsedAttendance parseAttendance(Map<String, dynamic> data) {
  final status = <String, String>{};
  final meta = <String, String>{};
  data.forEach((k, v) {
    if (v is! String) return;
    if (k.startsWith('_')) {
      meta[k] = v;
    } else {
      status[k] = v;
    }
  });
  return ParsedAttendance(status, meta);
}

// ---- Time helpers ----
String hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? parseHhmm(String? s) {
  if (s == null) return null;
  final p = s.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String fmtHhmm(String? s) {
  final t = parseHhmm(s);
  if (t == null) return '';
  return DateFormat('hh:mm a').format(DateTime(2000, 1, 1, t.hour, t.minute));
}

// ---- Shared Excel layout ----
// Both the monthly and overall exports use this layout:
//   top info section (Program / Semester / Instructor / Course / Section /
//   Marks), then three header rows (Week, Date, Class No.), then the students.
// Attendance is stored as 1 (present) / 0 (absent). Total Classes, Total
// Present, Percentage and Marks are Excel formulas, so they follow any edit.

// Total attendance marks of a course. It is only the starting value of the
// "Marks" cell in the sheet; the formulas read that cell, so it can be changed
// per course directly in Excel.
const double kDefaultAttendanceMarks = 5;

// Details shown in the top info section. Nothing is hardcoded: everything
// comes from the semester / subject that is being exported.
class ExcelInfo {
  final String program;
  final String semester;
  final String instructor;
  final String course;
  final String section;
  final double marks;
  const ExcelInfo({
    required this.program,
    required this.semester,
    required this.instructor,
    required this.course,
    required this.section,
    this.marks = kDefaultAttendanceMarks,
  });
}

Future<ExcelInfo> loadExcelInfo(SemRef sem, String subject) async {
  String semLabel = defaultSemesterLabel(sem.semester);
  try {
    final labels = await loadSemesterLabels(sem.deptId, sem.section);
    semLabel = labels[sem.semester] ?? semLabel;
  } catch (_) {}

  String instructor = '';
  try {
    final res = await _safeQuery(
        sem.subjects.where(FieldPath.documentId, isEqualTo: subject));
    if (res.docs.isNotEmpty) {
      instructor = (res.docs.first.data()['claimed_by_name'] ?? '').toString();
    }
  } catch (_) {}
  if (instructor.isEmpty && !AppSession.isAdmin) {
    instructor = AppSession.teacherName;
  }

  return ExcelInfo(
    program: sem.deptId,
    semester: semLabel,
    instructor: instructor,
    course: subject,
    section: sem.section,
  );
}

String _excelColLetters(int c) {
  var n = c + 1;
  var s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _ordinal(int n) {
  final m100 = n % 100;
  if (m100 >= 11 && m100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

// ---- Direct .xlsx writer ----
// The excel package was dropping styles / merges on some builds (that is why
// the title, "Week N" and the info section never looked centered or big).
// The sheet is now written straight as xlsx XML, so every style, merge, width
// and row height is exactly what is set below.
class _XlsxBuilder {
  final List<String> _fonts = [
    '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
  ];
  final List<String> _fills = [
    '<fill><patternFill patternType="none"/></fill>',
    '<fill><patternFill patternType="gray125"/></fill>'
  ];
  final List<String> _borders = [
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
  ];
  final List<String> _xfs = [
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
  ];
  final Map<int, Map<int, String>> _cells = {};
  final Map<int, double> rowHeights = {};
  final Map<int, double> colWidths = {};
  final List<String> merges = [];

  int _idx(List<String> list, String xml) {
    final i = list.indexOf(xml);
    if (i >= 0) return i;
    list.add(xml);
    return list.length - 1;
  }

  String _side(String tag, String? style, String color) => style == null
      ? '<$tag/>'
      : '<$tag style="$style"><color rgb="$color"/></$tag>';

  int style({
    String font = 'FF000000',
    String? bg,
    int size = 11,
    bool bold = true,
    bool left = false,
    bool wrap = false,
    bool border = true,
    bool thick = false,
  }) {
    final fontId = _idx(
        _fonts,
        '<font>${bold ? '<b/>' : ''}<sz val="$size"/>'
        '<color rgb="$font"/><name val="Calibri"/><family val="2"/></font>');
    final fillId = bg == null
        ? 0
        : _idx(
            _fills,
            '<fill><patternFill patternType="solid"><fgColor rgb="$bg"/>'
            '<bgColor indexed="64"/></patternFill></fill>');
    final bStyle = border ? (thick ? 'medium' : 'thin') : null;
    final bColor = thick ? 'FF1F3864' : 'FF8EA9C1';
    final borderId = _idx(
        _borders,
        '<border>${_side('left', bStyle, bColor)}${_side('right', bStyle, bColor)}'
        '${_side('top', bStyle, bColor)}${_side('bottom', bStyle, bColor)}'
        '<diagonal/></border>');
    return _idx(
        _xfs,
        '<xf numFmtId="0" fontId="$fontId" fillId="$fillId" borderId="$borderId" '
        'xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
        '<alignment horizontal="${left ? 'left' : 'center'}" vertical="center"'
        '${wrap ? ' wrapText="1"' : ''}/></xf>');
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _num(num v) => v == v.roundToDouble() ? v.round().toString() : '$v';

  void _put(int c, int r, String xml) =>
      (_cells[r] ??= <int, String>{})[c] = xml;

  String _ref(int c, int r) => '${_excelColLetters(c)}${r + 1}';

  void blank(int c, int r, int s) => _put(c, r, '<c r="${_ref(c, r)}" s="$s"/>');

  void text(int c, int r, String v, int s) => _put(
      c,
      r,
      '<c r="${_ref(c, r)}" s="$s" t="inlineStr"><is>'
      '<t xml:space="preserve">${_esc(v)}</t></is></c>');

  void number(int c, int r, num v, int s) =>
      _put(c, r, '<c r="${_ref(c, r)}" s="$s"><v>${_num(v)}</v></c>');

  void formula(int c, int r, String f, num cached, int s) => _put(c, r,
      '<c r="${_ref(c, r)}" s="$s"><f>${_esc(f)}</f><v>${_num(cached)}</v></c>');

  // Merged area: every cell gets the style (so colour + borders are kept),
  // the text is written in the first cell only.
  void merge(int c1, int r1, int c2, int r2, String? v, int s) {
    for (int r = r1; r <= r2; r++) {
      for (int c = c1; c <= c2; c++) {
        blank(c, r, s);
      }
    }
    if (v != null) text(c1, r1, v, s);
    if (c1 != c2 || r1 != r2) merges.add('${_ref(c1, r1)}:${_ref(c2, r2)}');
  }

  List<int> build() {
    final rows = <int>{..._cells.keys, ...rowHeights.keys}.toList()..sort();
    final sb = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
        '<sheetViews><sheetView workbookViewId="0" tabSelected="1"/></sheetViews>'
        '<sheetFormatPr defaultRowHeight="22" customHeight="1"/>');
    if (colWidths.isNotEmpty) {
      sb.write('<cols>');
      final keys = colWidths.keys.toList()..sort();
      for (final c in keys) {
        sb.write('<col min="${c + 1}" max="${c + 1}" '
            'width="${colWidths[c]}" customWidth="1"/>');
      }
      sb.write('</cols>');
    }
    sb.write('<sheetData>');
    for (final r in rows) {
      final h = rowHeights[r];
      sb.write('<row r="${r + 1}"'
          '${h != null ? ' ht="$h" customHeight="1"' : ''}>');
      final row = _cells[r];
      if (row != null) {
        final cols = row.keys.toList()..sort();
        for (final c in cols) {
          sb.write(row[c]);
        }
      }
      sb.write('</row>');
    }
    sb.write('</sheetData>');
    if (merges.isNotEmpty) {
      sb.write('<mergeCells count="${merges.length}">'
          '${merges.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>');
    }
    sb.write('<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" '
        'header="0.3" footer="0.3"/>'
        '<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
        '</worksheet>');

    final styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="${_fonts.length}">${_fonts.join()}</fonts>'
        '<fills count="${_fills.length}">${_fills.join()}</fills>'
        '<borders count="${_borders.length}">${_borders.join()}</borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${_xfs.length}">${_xfs.join()}</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';

    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>';
    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';
    const workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
        '<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>';
    const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>';

    final out = zip.Archive();
    void add(String name, String content) {
      final data = utf8.encode(content);
      out.addFile(zip.ArchiveFile(name, data.length, data));
    }

    add('[Content_Types].xml', contentTypes);
    add('_rels/.rels', rootRels);
    add('xl/workbook.xml', workbook);
    add('xl/_rels/workbook.xml.rels', workbookRels);
    add('xl/styles.xml', styles);
    add('xl/worksheets/sheet1.xml', sb.toString());
    return zip.ZipEncoder().encode(out) ?? <int>[];
  }
}

List<int>? buildAttendanceExcelBytes({
  required ExcelInfo info,
  required List<DateRecord> recs,
  required List<Map<String, String>> students,
}) {
  final records = List<DateRecord>.from(recs)
    ..sort((a, b) => a.id.compareTo(b.id));
  final x = _XlsxBuilder();

  // ---- Colour theme ----
  const navy = 'FF1F3864';
  const blue = 'FF2F5597';
  final titleStyle = x.style(size: 40, font: 'FFFFFFFF', bg: navy, thick: true);
  final fillerStyle = x.style(bg: 'FFEAF0F8', thick: true);
  final infoLabelStyle =
      x.style(size: 16, font: 'FFFFFFFF', bg: blue, thick: true);
  final infoValueStyle = x.style(size: 17, bg: 'FFFFF2CC', thick: true);
  final idHeadStyle =
      x.style(size: 16, font: 'FFFFFFFF', bg: navy, wrap: true, thick: true);
  final totalHeadStyle =
      x.style(size: 13, font: 'FFFFFFFF', bg: 'FF44546A', wrap: true, thick: true);
  final presentHeadStyle =
      x.style(size: 13, font: 'FFFFFFFF', bg: 'FF548235', wrap: true, thick: true);
  final pctHeadStyle =
      x.style(size: 13, font: 'FFFFFFFF', bg: 'FFC55A11', wrap: true, thick: true);
  final marksHeadStyle =
      x.style(size: 13, font: 'FFFFFFFF', bg: 'FFBF9000', wrap: true, thick: true);
  final marksCellStyle = x.style(size: 13, bg: 'FFFFF2CC');
  final totalCellStyle = x.style(size: 13, bg: 'FFE7EAF0');
  final cellStyle = x.style(size: 13, bg: 'FFFFFFFF');
  final cellStyleAlt = x.style(size: 13, bg: 'FFF2F2F2');
  final nameStyle = x.style(size: 13, left: true, bg: 'FFFFFFFF');
  final nameStyleAlt = x.style(size: 13, left: true, bg: 'FFF2F2F2');

  const weekHeadColors = [
    'FF2E75B6', 'FF548235', 'FFC55A11', 'FF7030A0', 'FF00808A', 'FFBF9000'
  ];
  const weekTintColors = [
    'FFBDD7EE', 'FFC6E0B4', 'FFF8CBAD', 'FFD9C3E8', 'FFB2DFDB', 'FFFFE699'
  ];
  const weekLightColors = [
    'FFDDEBF7', 'FFE2EFDA', 'FFFCE4D6', 'FFEDE2F4', 'FFDDF1EF', 'FFFFF2CC'
  ];
  final weekHeadStyles = [
    for (final c in weekHeadColors)
      x.style(size: 24, font: 'FFFFFFFF', bg: c, thick: true)
  ];
  final weekDateStyles = [
    for (final c in weekTintColors) x.style(size: 13, bg: c, wrap: true)
  ];
  final weekSerialStyles = [
    for (final c in weekLightColors) x.style(size: 12, bg: c)
  ];
  final presentStyle = x.style(size: 13, font: 'FF375623', bg: 'FFC6EFCE');
  final absentStyle = x.style(size: 13, font: 'FF9C0006', bg: 'FFFFC7CE');

  // ---- Columns ----
  const int firstSessionCol = 2;
  final n = records.length;
  final totalClassesCol = firstSessionCol + n;
  final presentCol = totalClassesCol + 1;
  final pctCol = totalClassesCol + 2;
  final marksCol = totalClassesCol + 3;
  final lastCol = marksCol < 11 ? 11 : marksCol;

  // ---- Rows ----
  const int infoRow0 = 1;
  const int weekRow = 4;
  const int dateRow = 5;
  const int serialRow = 6;
  const int firstStudentRow = 7;

  // Row 0: title, merged across the whole width, big and centered.
  x.merge(0, 0, lastCol, 0, 'University of Swabi', titleStyle);

  void infoRow(int row, String l1, Object v1, String l2, String v2) {
    x.merge(0, row, 1, row, l1, infoLabelStyle);
    if (v1 is num) {
      x.merge(2, row, 4, row, null, infoValueStyle);
      x.number(2, row, v1, infoValueStyle);
    } else {
      x.merge(2, row, 4, row, v1.toString(), infoValueStyle);
    }
    x.merge(5, row, 6, row, l2, infoLabelStyle);
    x.merge(7, row, 11, row, v2, infoValueStyle);
    for (int c = 12; c <= lastCol; c++) {
      x.blank(c, row, fillerStyle);
    }
  }

  final num marksValue =
      info.marks == info.marks.roundToDouble() ? info.marks.round() : info.marks;
  infoRow(infoRow0, 'Program', info.program, 'Course', info.course);
  infoRow(infoRow0 + 1, 'Semester', info.semester, 'Section', info.section);
  infoRow(infoRow0 + 2, 'Marks', marksValue, 'Instructor', info.instructor);
  final marksRef = '\$C\$${infoRow0 + 3}';

  // ---- Header rows: Week / Date / Class No. ----
  x.merge(0, weekRow, 0, serialRow, 'Roll No', idHeadStyle);
  x.merge(1, weekRow, 1, serialRow, 'Name', idHeadStyle);

  DateTime mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  final dates = <DateTime?>[];
  for (final r in records) {
    dates.add(DateTime.tryParse(r.id.split('_Session_')[0]));
  }
  DateTime? firstMonday;
  for (final d in dates) {
    if (d != null) {
      final m = mondayOf(d);
      if (firstMonday == null || m.isBefore(firstMonday)) firstMonday = m;
    }
  }

  final weekOf = List<int>.filled(n, 1);
  for (int i = 0; i < n; i++) {
    final d = dates[i];
    if (d != null && firstMonday != null) {
      final md = mondayOf(d);
      final days = DateTime.utc(md.year, md.month, md.day)
          .difference(DateTime.utc(
              firstMonday.year, firstMonday.month, firstMonday.day))
          .inDays;
      weekOf[i] = days ~/ 7 + 1;
    } else if (i > 0) {
      weekOf[i] = weekOf[i - 1];
    }
  }

  // "Week N" merged across that week's columns, centered and big.
  int i0 = 0;
  while (i0 < n) {
    int i1 = i0;
    while (i1 + 1 < n && weekOf[i1 + 1] == weekOf[i0]) {
      i1++;
    }
    x.merge(firstSessionCol + i0, weekRow, firstSessionCol + i1, weekRow,
        'Week ${weekOf[i0]}',
        weekHeadStyles[(weekOf[i0] - 1) % weekHeadStyles.length]);
    i0 = i1 + 1;
  }

  int classInWeek = 0;
  for (int i = 0; i < n; i++) {
    final d = dates[i];
    final dateLabel = d == null
        ? records[i].id.split('_Session_')[0]
        : DateFormat('d MMM').format(d);
    if (i == 0 || weekOf[i] != weekOf[i - 1]) {
      classInWeek = 0;
    }
    classInWeek++;
    final wi = (weekOf[i] - 1) % weekDateStyles.length;
    x.text(firstSessionCol + i, dateRow, dateLabel, weekDateStyles[wi]);
    x.text(firstSessionCol + i, serialRow, _ordinal(classInWeek),
        weekSerialStyles[wi]);
  }

  x.merge(totalClassesCol, weekRow, totalClassesCol, serialRow,
      'Total Classes', totalHeadStyle);
  x.merge(presentCol, weekRow, presentCol, serialRow, 'Total Present',
      presentHeadStyle);
  x.merge(pctCol, weekRow, pctCol, serialRow, 'Percentage of Present',
      pctHeadStyle);
  x.merge(marksCol, weekRow, marksCol, serialRow, 'Marks', marksHeadStyle);

  // ---- Student rows ----
  int rowIndex = firstStudentRow;
  int maxName = 4;
  for (final st in students) {
    final roll = st['roll'] ?? '';
    final name = st['name'] ?? '';
    if (name.length > maxName) maxName = name.length;
    int present = 0;
    final alt = (rowIndex - firstStudentRow) % 2 == 1;
    x.text(0, rowIndex, rollOf(roll), alt ? cellStyleAlt : cellStyle);
    x.text(1, rowIndex, name, alt ? nameStyleAlt : nameStyle);
    for (int i = 0; i < n; i++) {
      final isP = (records[i].status[roll] ?? 'P') == 'P';
      if (isP) present++;
      x.number(firstSessionCol + i, rowIndex, isP ? 1 : 0,
          isP ? presentStyle : absentStyle);
    }

    final xr = rowIndex + 1;
    final pct = n == 0 ? 0.0 : (present / n) * 100;
    final pctRounded = (pct * 100).round() / 100;
    final marksCached = (pctRounded / 100 * info.marks * 100).round() / 100;

    if (n > 0) {
      final first = '${_excelColLetters(firstSessionCol)}$xr';
      final last = '${_excelColLetters(firstSessionCol + n - 1)}$xr';
      final tcRef = '${_excelColLetters(totalClassesCol)}$xr';
      final tpRef = '${_excelColLetters(presentCol)}$xr';
      final pcRef = '${_excelColLetters(pctCol)}$xr';
      x.formula(totalClassesCol, rowIndex, 'COUNT($first:$last)', n,
          totalCellStyle);
      x.formula(presentCol, rowIndex, 'SUM($first:$last)', present,
          presentStyle);
      x.formula(pctCol, rowIndex, 'IF($tcRef=0,0,ROUND($tpRef/$tcRef*100,2))',
          pctRounded, pct >= 75 ? presentStyle : absentStyle);
      x.formula(marksCol, rowIndex, 'ROUND($pcRef/100*$marksRef,2)',
          marksCached, marksCellStyle);
    } else {
      x.number(totalClassesCol, rowIndex, 0, totalCellStyle);
      x.number(presentCol, rowIndex, 0, presentStyle);
      x.number(pctCol, rowIndex, 0, absentStyle);
      x.number(marksCol, rowIndex, 0, marksCellStyle);
    }
    x.rowHeights[rowIndex] = 28;
    rowIndex++;
  }

  // ---- Column widths: every session column the same size ----
  x.colWidths[0] = 11;
  x.colWidths[1] = (maxName * 1.3 + 6).clamp(26, 50).toDouble();
  for (int c = 2; c <= lastCol; c++) {
    x.colWidths[c] = 13; // all date / info columns equal
  }
  x.colWidths[totalClassesCol] = 15;
  x.colWidths[presentCol] = 15;
  x.colWidths[pctCol] = 19;
  x.colWidths[marksCol] = 15;

  // ---- Row heights ----
  x.rowHeights[0] = 72;
  for (int r = infoRow0; r < infoRow0 + 3; r++) {
    x.rowHeights[r] = 36;
  }
  x.rowHeights[weekRow] = 44;
  x.rowHeights[dateRow] = 30;
  x.rowHeights[serialRow] = 26;

  return x.build();
}


// ---- Student loaders ----
// Internal key of a student (called "roll" across the app). The first student
// with roll "12" gets "12", the next gets "12__2", then "12__3" and so on. This
// way students with the same roll or name never overwrite each other. Screens
// and Excel always show rollOf(key), which is just "12".
String rollOf(String key) {
  final i = key.indexOf('__');
  return i < 0 ? key : key.substring(0, i);
}

String uniqueStudentKey(String roll, Iterable<String> existingKeys) {
  final taken = existingKeys.toSet();
  if (!taken.contains(roll)) return roll;
  var n = 2;
  while (taken.contains('${roll}__$n')) {
    n++;
  }
  return '${roll}__$n';
}

int compareStudentKeys(String a, String b) {
  final c = (int.tryParse(rollOf(a)) ?? 0).compareTo(int.tryParse(rollOf(b)) ?? 0);
  if (c != 0) return c;
  if (a.length != b.length) return a.length.compareTo(b.length);
  return a.compareTo(b);
}

List<Map<String, String>> _sortedStudents(Map<String, String> m) {
  final list = m.entries.map((e) => {'roll': e.key, 'name': e.value}).toList();
  list.sort((a, b) => compareStudentKeys(a['roll']!, b['roll']!));
  return list;
}

// Semester labels (custom names), used by the copy dialog.
Future<Map<String, String>> loadSemesterLabels(
    String deptId, String section) async {
  final res = await _safeQuery(FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .collection('sections')
      .doc(section)
      .collection('semesters'));
  final out = <String, String>{};
  for (final d in res.docs) {
    final l = (d.data()['label'] ?? '').toString();
    if (l.isNotEmpty) out[d.id] = l;
  }
  return out;
}

// Copies all students of semester [from] into semester [to] (same department
// and section). The source keeps its students and nothing in the destination is
// overwritten: if a roll already exists there, a new unique key is created.
// Returns the number of students copied.
Future<int> copyStudentsToSemester(SemRef from, SemRef to) async {
  final src = await loadSemesterStudents(from);
  if (src.isEmpty) return 0;
  final dest = await loadSemesterStudents(to);
  final taken = dest.map((s) => s['roll']!).toSet();
  for (final s in src) {
    final key = uniqueStudentKey(rollOf(s['roll']!), taken);
    taken.add(key);
    final name = s['name']!;
    unawaited(to.students
        .doc(key)
        .set({'roll': key, 'name': name}).catchError((_) {}));
    unawaited(LocalDb.upsertStudent(to, key, name));
  }
  return src.length;
}

// Master list of a semester (managed by the admin). It reads Firestore first
// (server or cache). If nothing is cached yet, it falls back to the SQLite copy
// so the list is not empty just because we are offline.
Future<List<Map<String, String>>> loadSemesterStudents(SemRef sem) async {
  final res = await _safeQuery(sem.students);
  final m = <String, String>{};
  for (final d in res.docs) {
    final data = d.data();
    m[(data['roll'] ?? d.id).toString()] = (data['name'] ?? '').toString();
  }
  if (m.isEmpty && res.fromCache) {
    m.addAll(await LocalDb.students(sem));
  }
  return _sortedStudents(m);
}

// Subject-level overrides: roll -> {'name': ..., 'kind': 'extra' | 'hidden'}
Future<Map<String, Map<String, String>>> loadOverrides(
    SemRef sem, String subject) async {
  final res = await _safeQuery(sem.overrides(subject));
  final out = <String, Map<String, String>>{};
  for (final d in res.docs) {
    final data = d.data();
    out[(data['roll'] ?? d.id).toString()] = {
      'name': (data['name'] ?? '').toString(),
      'kind': (data['kind'] ?? '').toString(),
    };
  }
  if (out.isEmpty && res.fromCache) {
    out.addAll(await LocalDb.overrides(sem, subject));
  }
  return out;
}

// Actual student list of a subject = master list - hidden + extra.
Future<List<Map<String, String>>> loadSubjectStudents(
    SemRef sem, String subject) async {
  final masterF = loadSemesterStudents(sem);
  final ovF = loadOverrides(sem, subject);
  final master = await masterF;
  final ov = await ovF;
  final m = {for (final s in master) s['roll']!: s['name']!};
  ov.forEach((roll, o) {
    if (o['kind'] == 'hidden') {
      m.remove(roll);
    } else if (o['kind'] == 'extra') {
      m[roll] = o['name'] ?? '';
    }
  });
  return _sortedStudents(m);
}

// One attendance record (one date and session) of a subject.
class DateRecord {
  final String id; // yyyy-MM-dd_Session_n
  final Map<String, String> status; // roll -> 'P' / 'A'
  final Map<String, String> meta; // _time, _marked_by, _marked_by_name
  DateRecord(this.id, this.status, this.meta);
}

// All attendance records of a subject in one read (sorted by id). Falls back to
// the SQLite copy when Firestore has nothing cached.
Future<List<DateRecord>> loadDateRecords(SemRef sem, String subject) async {
  final res = await _safeQuery(sem.dates(subject));
  List<DateRecord> out;
  if (res.docs.isNotEmpty || !res.fromCache) {
    out = res.docs.map((d) {
      final p = parseAttendance(d.data());
      return DateRecord(d.id, p.status, p.meta);
    }).toList();
  } else {
    out = await LocalDb.dateRecords(sem, subject);
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

// Claim / unclaim a subject (teacher)
class ClaimException implements Exception {
  final String message;
  ClaimException(this.message);
}

Future<void> claimSubject(
    BuildContext context, SemRef sem, String subject) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Claim this subject?'),
      content: Text(
          "'$subject' will be assigned to you. No other teacher can claim it until you release it."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Claim')),
      ],
    ),
  );
  if (confirm != true) return;
  if (!context.mounted) return;

  // A transaction needs internet so the server can confirm that two teachers
  // cannot claim the same subject.
  if ((await _netState()) != _Net.reachable) {
    if (context.mounted) {
      showSnack(context, 'An internet connection is required to claim a subject.');
    }
    return;
  }

  final subRef = sem.subjectDoc(subject);
  final claimRef =
      teacherClaimsRef(AppSession.teacherId).doc(sem.claimKey(subject));
  try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(subRef);
      if (!snap.exists) throw ClaimException('This subject no longer exists.');
      final cb = (snap.data()?['claimed_by'] ?? '').toString();
      if (cb.isNotEmpty && cb != AppSession.teacherId) {
        throw ClaimException(
            'This subject has already been claimed by ${(snap.data()?['claimed_by_name'] ?? 'another teacher').toString()}.');
      }
      tx.update(subRef, {
        'claimed_by': AppSession.teacherId,
        'claimed_by_name': AppSession.teacherName,
      });
      tx.set(claimRef, {
        'dept': sem.deptId,
        'section': sem.section,
        'semester': sem.semester,
        'subject': subject,
      });
    }).timeout(const Duration(seconds: 15));

    unawaited(LocalDb.setSubjectClaim(
        sem, subject, AppSession.teacherId, AppSession.teacherName));
    unawaited(LocalDb.upsertClaim(AppSession.teacherId, sem, subject));
    if (context.mounted) showSnack(context, "You claimed '$subject'");
  } on ClaimException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Could not claim the subject. Please check your internet and try again.');
    }
  }
}

Future<void> unclaimSubject(
    BuildContext context, SemRef sem, String subject) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Leave this subject?'),
      content: Text(
          "'$subject' will become available to all teachers again. Existing attendance history will not be deleted."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: kAbsent))),
      ],
    ),
  );
  if (confirm != true) return;

  unawaited(sem.subjectDoc(subject).update({
    'claimed_by': FieldValue.delete(),
    'claimed_by_name': FieldValue.delete(),
  }).catchError((_) {}));
  unawaited(teacherClaimsRef(AppSession.teacherId)
      .doc(sem.claimKey(subject))
      .delete()
      .catchError((_) {}));
  unawaited(LocalDb.setSubjectClaim(sem, subject, '', ''));
  unawaited(LocalDb.deleteClaim(AppSession.teacherId, sem, subject));
  if (context.mounted) showSnack(context, "You left '$subject'");
}

// Firestore delete helpers
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getDocsForDelete(
    Query<Map<String, dynamic>> query) async {
  try {
    if (await _isOnline()) {
      final snap = await query.get().timeout(const Duration(seconds: 10));
      return snap.docs;
    }
  } catch (_) {}
  try {
    final snap = await query.get(const GetOptions(source: Source.cache));
    return snap.docs;
  } catch (_) {
    return [];
  }
}

void _deleteDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  for (int i = 0; i < docs.length; i += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs.skip(i).take(400)) {
      batch.delete(d.reference);
    }
    unawaited(batch.commit().catchError((_) {}));
  }
}

// When a subject is deleted, also remove the teacher's claim on it.
Future<void> _cleanupClaimOfSubject(
    SemRef sem, String subject, Map<String, dynamic>? subjectData) async {
  final cb = (subjectData?['claimed_by'] ?? '').toString();
  if (cb.isEmpty) return;
  unawaited(teacherClaimsRef(cb)
      .doc(sem.claimKey(subject))
      .delete()
      .catchError((_) {}));
  await LocalDb.deleteClaim(cb, sem, subject);
}

Future<void> deleteSubjectEverywhere(SemRef sem, String subject) async {
  final subSnap = await safeGetDocOrNull(sem.subjectDoc(subject));
  await _cleanupClaimOfSubject(sem, subject, subSnap?.data());
  _deleteDocs(await _getDocsForDelete(sem.dates(subject)));
  _deleteDocs(await _getDocsForDelete(sem.overrides(subject)));
  unawaited(sem.subjectDoc(subject).delete().catchError((_) {}));
  await LocalDb.deleteSubject(sem, subject);
}

// Delete a whole department: everything in every section and semester, plus old
// data.
Future<void> deleteDepartmentEverywhere(String deptId) async {
  unawaited(FirebaseFirestore.instance
      .collection('meta')
      .doc('seed')
      .set({'done': true}, SetOptions(merge: true)).catchError((_) {}));

  for (final sec in kSections) {
    for (final sid in kSemesterIds) {
      final sem = SemRef(deptId, sec, sid);
      final subjects = await _getDocsForDelete(sem.subjects);
      for (final sub in subjects) {
        await _cleanupClaimOfSubject(sem, sub.id, sub.data());
        _deleteDocs(await _getDocsForDelete(sem.dates(sub.id)));
        _deleteDocs(await _getDocsForDelete(sem.overrides(sub.id)));
      }
      _deleteDocs(subjects);
      _deleteDocs(await _getDocsForDelete(sem.students));
      unawaited(sem.doc.delete().catchError((_) {}));
    }
  }

  // Old data from before sections existed, if any is left
  final oldSubjects = await _getDocsForDelete(legacySubjectsRef(deptId));
  for (final sub in oldSubjects) {
    _deleteDocs(await _getDocsForDelete(legacyDatesRef(deptId, sub.id)));
  }
  _deleteDocs(oldSubjects);
  _deleteDocs(await _getDocsForDelete(legacyStudentsRef(deptId)));

  unawaited(FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .delete()
      .catchError((_) {}));

  await LocalDb.deleteDepartment(deptId);
}

// Admin only: deletes every attendance record of every subject from Firestore,
// SQLite and the on-device cache. Departments, subjects and students are not
// touched. Needs internet so the server copy is really deleted (throws
// otherwise).
Future<void> deleteAllAttendanceEverywhere() async {
  final fs = FirebaseFirestore.instance;
  final snap =
      await fs.collectionGroup('dates').get().timeout(const Duration(seconds: 30));
  if (snap.metadata.isFromCache) {
    throw Exception('Server not reachable');
  }
  final docs = snap.docs;
  for (int i = 0; i < docs.length; i += 400) {
    final batch = fs.batch();
    for (final d in docs.skip(i).take(400)) {
      batch.delete(d.reference);
    }
    await batch.commit().timeout(const Duration(seconds: 30));
  }
  await LocalDb.deleteAllAttendance();
}

// ---------------------------------------------------------------------------
// Backup & restore
// Backup: every document of the app is read from Firestore and written into one
// JSON file (kept on the phone, or downloaded on the web).
// Restore: the JSON file is read back and every document is written to its
// original path. Documents that are not in the file are left alone, so a
// restore never deletes anything. Running it twice is harmless.
// ---------------------------------------------------------------------------
const String kBackupFormat = 'attendance_backup_v1';
const List<String> _kBackupRoots = ['departments', 'teachers', 'settings', 'meta'];
const List<String> _kBackupGroups = [
  'sections',
  'semesters',
  'students',
  'subjects',
  'overrides',
  'dates',
  'claims',
];

dynamic _bkEncode(dynamic v) {
  if (v is Timestamp) {
    return {'__t': 'ts', 's': v.seconds, 'n': v.nanoseconds};
  }
  if (v is GeoPoint) {
    return {'__t': 'geo', 'lat': v.latitude, 'lng': v.longitude};
  }
  if (v is DocumentReference) return {'__t': 'ref', 'p': v.path};
  if (v is Blob) return {'__t': 'bytes', 'b': base64Encode(v.bytes)};
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _bkEncode(val)));
  }
  if (v is Iterable) return v.map(_bkEncode).toList();
  return v;
}

dynamic _bkDecode(dynamic v) {
  if (v is Map) {
    final t = v['__t'];
    if (t == 'ts') return Timestamp(v['s'] as int, v['n'] as int);
    if (t == 'geo') {
      return GeoPoint((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble());
    }
    if (t == 'ref') return FirebaseFirestore.instance.doc(v['p'] as String);
    if (t == 'bytes') return Blob(base64Decode(v['b'] as String));
    return v.map((k, val) => MapEntry(k.toString(), _bkDecode(val)));
  }
  if (v is List) return v.map(_bkDecode).toList();
  return v;
}

Future<Map<String, dynamic>> _collectBackup() async {
  final fs = FirebaseFirestore.instance;
  const t = Duration(seconds: 60);
  final docs = <String, dynamic>{};
  void addAll(QuerySnapshot<Map<String, dynamic>> snap) {
    // A cached answer would give an incomplete backup, so refuse it.
    if (snap.metadata.isFromCache) throw Exception('Server not reachable');
    for (final d in snap.docs) {
      docs[d.reference.path] = _bkEncode(d.data());
    }
  }

  for (final c in _kBackupRoots) {
    addAll(await fs.collection(c).get().timeout(t));
  }
  for (final g in _kBackupGroups) {
    addAll(await fs.collectionGroup(g).get().timeout(t));
  }
  return {
    'format': kBackupFormat,
    'created': DateTime.now().toIso8601String(),
    'count': docs.length,
    'docs': docs,
  };
}

// Creates the backup file and saves/shares it. Returns the number of records.
Future<int> createBackupFile() async {
  final data = await _collectBackup();
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
  final name =
      'attendance_backup_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.json';
  if (kIsWeb) {
    downloadBytes(bytes, name);
    return data['count'] as int;
  }
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(path)],
    text: 'Attendance backup',
  ));
  return data['count'] as int;
}

Future<void> runBackupWithUi(BuildContext context) async {
  if ((await _netState()) != _Net.reachable) {
    if (!context.mounted) return;
    showSnack(context, 'Internet is required to take a backup.',
        color: kAbsent);
    return;
  }
  if (context.mounted) showSnack(context, 'Preparing backup...');
  try {
    final n = await createBackupFile();
    if (context.mounted) showSnack(context, 'Backup ready ($n records)');
  } catch (e) {
    debugPrint('Backup error: $e');
    if (context.mounted) {
      showSnack(context, 'Backup failed. Check your internet and try again.',
          color: kAbsent);
    }
  }
}

bool _bkPathOk(String path) {
  final parts = path.split('/');
  return parts.length.isEven &&
      parts.every((p) => p.isNotEmpty) &&
      _kBackupRoots.contains(parts.first);
}

Future<void> restoreFromBackupUi(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
  } catch (e) {
    debugPrint('File picker error: $e');
    if (context.mounted) {
      showSnack(context, 'Could not open the file picker.', color: kAbsent);
    }
    return;
  }
  if (f == null) return;

  Map<String, dynamic> docs;
  String created = '';
  try {
    final bytes = await f.readAsBytes();
    final m = jsonDecode(utf8.decode(bytes));
    if (m is! Map || m['format'] != kBackupFormat || m['docs'] is! Map) {
      throw const FormatException('not a backup');
    }
    docs = Map<String, dynamic>.from(m['docs'] as Map);
    created = (m['created'] ?? '').toString();
    if (docs.keys.any((p) => !_bkPathOk(p))) {
      throw const FormatException('bad path');
    }
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'This is not a valid backup file.', color: kAbsent);
    }
    return;
  }
  if (!context.mounted) return;

  String when = created;
  try {
    when = DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(created));
  } catch (_) {}

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(
        'Backup taken: $when\nRecords in file: ${docs.length}\n\n'
        'Every record in the file is written back to the server and replaces the current version of that record. '
        'Records that are not in the file are not deleted. Internet is required.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  if ((await _netState()) != _Net.reachable) {
    if (context.mounted) {
      showSnack(context, 'Internet is required to restore.', color: kAbsent);
    }
    return;
  }
  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Text('Restoring...'),
        ],
      ),
    ),
  );

  bool success = false;
  try {
    final fs = FirebaseFirestore.instance;
    final entries = docs.entries.toList();
    for (int i = 0; i < entries.length; i += 400) {
      final batch = fs.batch();
      for (final e in entries.skip(i).take(400)) {
        batch.set(fs.doc(e.key),
            Map<String, dynamic>.from(_bkDecode(e.value) as Map));
      }
      await batch.commit().timeout(const Duration(seconds: 30));
    }
    success = true;
    await syncLocalDbIfStale(force: true);
  } catch (e) {
    debugPrint('Restore error: $e');
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  showSnack(
    context,
    success
        ? 'Restore complete'
        : 'Restore did not finish. Check your internet and run it again.',
    color: success ? null : kAbsent,
  );
}

// One-time migration of the old Software Engineering data
//   -> Software Engineering / Section A / Semester 3
// The old data is copied, not deleted, so this is safe. Running it again
// changes nothing (it merges).
Future<void> _copyDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  DocumentReference<Map<String, dynamic>> Function(
          QueryDocumentSnapshot<Map<String, dynamic>> d)
      target,
) async {
  for (int i = 0; i < docs.length; i += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs.skip(i).take(400)) {
      batch.set(target(d), d.data(), SetOptions(merge: true));
    }
    await batch.commit().timeout(const Duration(seconds: 30));
  }
}

Future<bool> migrateSoftwareEngineeringLegacy() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('migr_se_a3_v1') == true) return false;
  if (!await _isOnline()) return false;

  final fs = FirebaseFirestore.instance;
  final metaRef = fs.collection('meta').doc('migration_se_a3_v1');
  try {
    const t = Duration(seconds: 20);
    final meta = await metaRef.get().timeout(const Duration(seconds: 10));
    if (meta.exists && meta.data()?['done'] == true) {
      await prefs.setBool('migr_se_a3_v1', true);
      return false;
    }

    final target = SemRef(kSoftwareEngineeringDeptId, 'A', '3');

    final students =
        await legacyStudentsRef(kSoftwareEngineeringDeptId).get().timeout(t);
    await _copyDocs(students.docs, (d) => target.students.doc(d.id));

    final subjects =
        await legacySubjectsRef(kSoftwareEngineeringDeptId).get().timeout(t);
    await _copyDocs(subjects.docs, (d) => target.subjects.doc(d.id));

    for (final sub in subjects.docs) {
      final dates = await legacyDatesRef(kSoftwareEngineeringDeptId, sub.id)
          .get()
          .timeout(t);
      await _copyDocs(dates.docs, (d) => target.dates(sub.id).doc(d.id));
    }

    await metaRef.set({'done': true}).timeout(const Duration(seconds: 10));
    await prefs.setBool('migr_se_a3_v1', true);
    await LocalDb.replaceAllFromFirestore();
    return true;
  } catch (e) {
    debugPrint('Migration failed (agli baar phir try hoga): $e');
    return false;
  }
}

// Create the second admin (one time): a doc that looks like a normal department
Future<void> ensureHiddenAdminDepartment() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('hidden_admin_v1') == true) return;
    if (!await _isOnline()) return;

    final fs = FirebaseFirestore.instance;
    final metaRef = fs.collection('meta').doc('hidden_admin_v1');
    final meta = await metaRef.get().timeout(const Duration(seconds: 10));
    if (meta.exists && meta.data()?['done'] == true) {
      await prefs.setBool('hidden_admin_v1', true);
      return;
    }

    final deptRef =
        fs.collection('departments').doc(kHiddenAdminDeptName);
    final snap = await deptRef.get().timeout(const Duration(seconds: 10));
    if (!snap.exists) {
      await deptRef.set({
        'name': kHiddenAdminDeptName,
        'username': kHiddenAdminUsername,
        'password': kHiddenAdminPassword,
      }).timeout(const Duration(seconds: 10));
    }
    await metaRef.set({'done': true}).timeout(const Duration(seconds: 10));
    await prefs.setBool('hidden_admin_v1', true);
  } catch (_) {}
}

// Local SQLite database (used alongside Firestore, not instead of it)
// Every function catches its own errors, so an SQLite problem never stops the
// app or Firestore.
// Passwords are NOT saved here. The department username is not saved either, so
// an export does not reveal the second admin.
class LocalDb {
  static sql.Database? _db;
  static bool _syncing = false;
  static const String _fileName = 'attendance_local.db';

  static Future<String> filePath() async {
    final dir = await sql.getDatabasesPath();
    return '$dir/$_fileName';
  }

  static const List<String> _tables = [
    'attendance',
    'overrides',
    'claims',
    'subjects',
    'students',
    'semesters',
    'teachers',
    'departments',
  ];

  static Future<void> _createAll(sql.Database db) async {
    await db.execute(
        'CREATE TABLE departments (dept_id TEXT PRIMARY KEY, name TEXT, username TEXT)');
    await db.execute(
        'CREATE TABLE semesters (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, label TEXT, PRIMARY KEY (dept_id, section, semester))');
    await db.execute(
        'CREATE TABLE students (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, roll TEXT NOT NULL, name TEXT, PRIMARY KEY (dept_id, section, semester, roll))');
    await db.execute(
        'CREATE TABLE subjects (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, name TEXT NOT NULL, claimed_by TEXT, claimed_by_name TEXT, PRIMARY KEY (dept_id, section, semester, name))');
    await db.execute(
        'CREATE TABLE overrides (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, roll TEXT NOT NULL, name TEXT, kind TEXT, PRIMARY KEY (dept_id, section, semester, subject, roll))');
    await db.execute(
        'CREATE TABLE attendance (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, session_id TEXT NOT NULL, roll TEXT NOT NULL, status TEXT, marked_time TEXT, marked_by TEXT, marked_by_name TEXT, PRIMARY KEY (dept_id, section, semester, subject, session_id, roll))');
    await db.execute(
        'CREATE TABLE teachers (teacher_id TEXT PRIMARY KEY, name TEXT, username TEXT)');
    await db.execute(
        'CREATE TABLE claims (teacher_id TEXT NOT NULL, dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, PRIMARY KEY (teacher_id, dept_id, section, semester, subject))');
  }

  static Future<sql.Database> _open() async {
    if (_db != null && _db!.isOpen) return _db!;
    final path = await filePath();
    _db = await sql.openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async => _createAll(db),
      // v1 -> v2: the structure changed (sections and semesters). The local DB
      // is only a copy of Firestore, so we drop the old tables and create new
      // ones. The data fills back in from Firestore when the internet returns.
      onUpgrade: (db, oldV, newV) async {
        for (final t in _tables) {
          await db.execute('DROP TABLE IF EXISTS $t');
        }
        await _createAll(db);
      },
    );
    return _db!;
  }

  static Future<void> _run(Future<void> Function(sql.Database db) action) async {
    try {
      final db = await _open();
      await action(db);
    } catch (e) {
      debugPrint('LocalDb error: $e');
    }
  }

  // ---------------- departments ----------------
  static Future<void> upsertDepartment(String deptId, String name) {
    if (deptId == kHiddenAdminDeptName) return Future.value();
    return _run((db) async {
      await db.insert(
        'departments',
        {'dept_id': deptId, 'name': name, 'username': ''},
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteDepartment(String deptId) {
    return _run((db) async {
      await db.transaction((txn) async {
        for (final t in ['attendance', 'overrides', 'subjects', 'students', 'semesters']) {
          await txn.delete(t, where: 'dept_id = ?', whereArgs: [deptId]);
        }
        await txn.delete('claims', where: 'dept_id = ?', whereArgs: [deptId]);
        await txn.delete('departments', where: 'dept_id = ?', whereArgs: [deptId]);
      });
    });
  }

  // ---------------- semester labels ----------------
  static Future<void> upsertSemesterLabel(SemRef s, String label) {
    return _run((db) async {
      await db.insert(
        'semesters',
        {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'label': label,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteSemesterLabel(SemRef s) {
    return _run((db) async {
      await db.delete('semesters',
          where: 'dept_id = ? AND section = ? AND semester = ?',
          whereArgs: [s.deptId, s.section, s.semester]);
    });
  }

  // ---------------- students ----------------
  static Future<void> upsertStudent(SemRef s, String roll, String name) {
    return _run((db) async {
      await db.insert(
        'students',
        {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'roll': roll,
          'name': name,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteStudent(SemRef s, String roll) {
    return _run((db) async {
      await db.delete('students',
          where: 'dept_id = ? AND section = ? AND semester = ? AND roll = ?',
          whereArgs: [s.deptId, s.section, s.semester, roll]);
    });
  }

  // ---------------- subjects ----------------
  static Future<void> upsertSubject(SemRef s, String name) {
    return _run((db) async {
      final n = await db.update(
        'subjects',
        {'name': name},
        where: 'dept_id = ? AND section = ? AND semester = ? AND name = ?',
        whereArgs: [s.deptId, s.section, s.semester, name],
      );
      if (n == 0) {
        await db.insert('subjects', {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'name': name,
          'claimed_by': '',
          'claimed_by_name': '',
        });
      }
    });
  }

  static Future<void> setSubjectClaim(
      SemRef s, String name, String teacherId, String teacherName) {
    return _run((db) async {
      await db.update(
        'subjects',
        {'claimed_by': teacherId, 'claimed_by_name': teacherName},
        where: 'dept_id = ? AND section = ? AND semester = ? AND name = ?',
        whereArgs: [s.deptId, s.section, s.semester, name],
      );
    });
  }

  static Future<void> deleteSubject(SemRef s, String name) {
    return _run((db) async {
      await db.transaction((txn) async {
        const w =
            'dept_id = ? AND section = ? AND semester = ? AND subject = ?';
        final args = [s.deptId, s.section, s.semester, name];
        await txn.delete('attendance', where: w, whereArgs: args);
        await txn.delete('overrides', where: w, whereArgs: args);
        await txn.delete('claims', where: w, whereArgs: args);
        await txn.delete('subjects',
            where: 'dept_id = ? AND section = ? AND semester = ? AND name = ?',
            whereArgs: args);
      });
    });
  }

  // ---------------- subject-level student overrides ----------------
  static Future<void> upsertOverride(
      SemRef s, String subject, String roll, String name, String kind) {
    return _run((db) async {
      await db.insert(
        'overrides',
        {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'subject': subject,
          'roll': roll,
          'name': name,
          'kind': kind,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteOverride(SemRef s, String subject, String roll) {
    return _run((db) async {
      await db.delete('overrides',
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND roll = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, roll]);
    });
  }

  // ---------------- attendance ----------------
  static Future<void> saveAttendance(
    SemRef s,
    String subject,
    String sessionId,
    Map<String, String> status, {
    String? time,
    String? markedBy,
    String? markedByName,
  }) {
    return _run((db) async {
      await db.transaction((txn) async {
        await txn.delete('attendance',
            where:
                'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
            whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
        final batch = txn.batch();
        status.forEach((roll, st) {
          batch.insert(
            'attendance',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'subject': subject,
              'session_id': sessionId,
              'roll': roll,
              'status': st,
              'marked_time': time ?? '',
              'marked_by': markedBy ?? '',
              'marked_by_name': markedByName ?? '',
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        });
        await batch.commit(noResult: true);
      });
    });
  }

  static Future<void> deleteAttendance(
      SemRef s, String subject, String sessionId) {
    return _run((db) async {
      await db.delete('attendance',
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
    });
  }

  // ---------------- teachers & claims ----------------
  static Future<void> upsertTeacher(String id, String name, String username) {
    return _run((db) async {
      await db.insert(
        'teachers',
        {'teacher_id': id, 'name': name, 'username': username},
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> upsertClaim(String teacherId, SemRef s, String subject) {
    return _run((db) async {
      await db.insert(
        'claims',
        {
          'teacher_id': teacherId,
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'subject': subject,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteClaim(String teacherId, SemRef s, String subject) {
    return _run((db) async {
      await db.delete('claims',
          where:
              'teacher_id = ? AND dept_id = ? AND section = ? AND semester = ? AND subject = ?',
          whereArgs: [teacherId, s.deptId, s.section, s.semester, subject]);
    });
  }

  // Reads all Firestore data and rebuilds SQLite to match it. collectionGroup
  // fetches each collection in one query, and the document path tells which
  // department / section / semester it belongs to.
  static Future<bool> replaceAllFromFirestore() async {
    if (_syncing) return false;
    if (!await _isOnline()) return false;
    _syncing = true;
    try {
      const t = Duration(seconds: 30);
      final fs = FirebaseFirestore.instance;

      final depts = await fs.collection('departments').get().timeout(t);
      final semDocs = await fs.collectionGroup('semesters').get().timeout(t);
      final students = await fs.collectionGroup('students').get().timeout(t);
      final subjects = await fs.collectionGroup('subjects').get().timeout(t);
      final overrides = await fs.collectionGroup('overrides').get().timeout(t);
      final dates = await fs.collectionGroup('dates').get().timeout(t);
      final teachers = await fs.collection('teachers').get().timeout(t);
      final claims = await fs.collectionGroup('claims').get().timeout(t);

      // If any data came from the offline cache, we are not really online. Keep
      // the existing SQLite data instead of replacing it with a partial copy.
      final allSnaps = [
        depts,
        semDocs,
        students,
        subjects,
        overrides,
        dates,
        teachers,
        claims,
      ];
      if (allSnaps.any((x) => x.metadata.isFromCache)) return false;

      bool isNew(List<String> seg, int len, String coll) =>
          seg.length == len &&
          seg[0] == 'departments' &&
          seg[2] == 'sections' &&
          seg[4] == 'semesters' &&
          seg[6] == coll;

      final deptRows = <Map<String, Object?>>[];
      final semRows = <Map<String, Object?>>[];
      final studentRows = <Map<String, Object?>>[];
      final subjectRows = <Map<String, Object?>>[];
      final overrideRows = <Map<String, Object?>>[];
      final attendanceRows = <Map<String, Object?>>[];
      final teacherRows = <Map<String, Object?>>[];
      final claimRows = <Map<String, Object?>>[];

      for (final d in depts.docs) {
        if (d.id == kHiddenAdminDeptName) continue; // hidden admin
        deptRows.add({
          'dept_id': d.id,
          'name': (d.data()['name'] ?? d.id).toString(),
          'username': '',
        });
      }

      for (final d in semDocs.docs) {
        final seg = d.reference.path.split('/');
        if (seg.length == 6 &&
            seg[0] == 'departments' &&
            seg[2] == 'sections' &&
            seg[4] == 'semesters') {
          final label = (d.data()['label'] ?? '').toString();
          if (label.isNotEmpty) {
            semRows.add({
              'dept_id': seg[1],
              'section': seg[3],
              'semester': seg[5],
              'label': label,
            });
          }
        }
      }

      for (final d in students.docs) {
        final seg = d.reference.path.split('/');
        if (!isNew(seg, 8, 'students')) continue;
        final sd = d.data();
        studentRows.add({
          'dept_id': seg[1],
          'section': seg[3],
          'semester': seg[5],
          'roll': (sd['roll'] ?? d.id).toString(),
          'name': (sd['name'] ?? '').toString(),
        });
      }

      for (final d in subjects.docs) {
        final seg = d.reference.path.split('/');
        if (!isNew(seg, 8, 'subjects')) continue;
        final sd = d.data();
        subjectRows.add({
          'dept_id': seg[1],
          'section': seg[3],
          'semester': seg[5],
          'name': d.id,
          'claimed_by': (sd['claimed_by'] ?? '').toString(),
          'claimed_by_name': (sd['claimed_by_name'] ?? '').toString(),
        });
      }

      for (final d in overrides.docs) {
        final seg = d.reference.path.split('/');
        if (!(seg.length == 10 &&
            seg[0] == 'departments' &&
            seg[2] == 'sections' &&
            seg[4] == 'semesters' &&
            seg[6] == 'subjects' &&
            seg[8] == 'overrides')) {
          continue;
        }
        final od = d.data();
        overrideRows.add({
          'dept_id': seg[1],
          'section': seg[3],
          'semester': seg[5],
          'subject': seg[7],
          'roll': (od['roll'] ?? d.id).toString(),
          'name': (od['name'] ?? '').toString(),
          'kind': (od['kind'] ?? '').toString(),
        });
      }

      for (final d in dates.docs) {
        final seg = d.reference.path.split('/');
        if (!(seg.length == 10 &&
            seg[0] == 'departments' &&
            seg[2] == 'sections' &&
            seg[4] == 'semesters' &&
            seg[6] == 'attendance' &&
            seg[8] == 'dates')) {
          continue;
        }
        final parsed = parseAttendance(d.data());
        parsed.status.forEach((roll, status) {
          attendanceRows.add({
            'dept_id': seg[1],
            'section': seg[3],
            'semester': seg[5],
            'subject': seg[7],
            'session_id': d.id,
            'roll': roll,
            'status': status,
            'marked_time': parsed.meta['_time'] ?? '',
            'marked_by': parsed.meta['_marked_by'] ?? '',
            'marked_by_name': parsed.meta['_marked_by_name'] ?? '',
          });
        });
      }

      for (final d in teachers.docs) {
        final td = d.data();
        teacherRows.add({
          'teacher_id': d.id,
          'name': (td['name'] ?? '').toString(),
          'username': (td['username'] ?? '').toString(),
        });
      }

      for (final d in claims.docs) {
        final seg = d.reference.path.split('/');
        if (!(seg.length == 4 && seg[0] == 'teachers' && seg[2] == 'claims')) {
          continue;
        }
        final cd = d.data();
        claimRows.add({
          'teacher_id': seg[1],
          'dept_id': (cd['dept'] ?? '').toString(),
          'section': (cd['section'] ?? '').toString(),
          'semester': (cd['semester'] ?? '').toString(),
          'subject': (cd['subject'] ?? '').toString(),
        });
      }

      final db = await _open();
      await db.transaction((txn) async {
        for (final table in _tables) {
          await txn.delete(table);
        }
        final batch = txn.batch();
        void addAll(String table, List<Map<String, Object?>> rows) {
          for (final r in rows) {
            batch.insert(table, r, conflictAlgorithm: sql.ConflictAlgorithm.replace);
          }
        }

        addAll('departments', deptRows);
        addAll('semesters', semRows);
        addAll('students', studentRows);
        addAll('subjects', subjectRows);
        addAll('overrides', overrideRows);
        addAll('attendance', attendanceRows);
        addAll('teachers', teacherRows);
        addAll('claims', claimRows);
        await batch.commit(noResult: true);
      });
      return true;
    } catch (e) {
      debugPrint('LocalDb sync error: $e');
      return false;
    } finally {
      _syncing = false;
    }
  }

  // Reads: offline fallback for the loaders and the monthly attendance view
  static const String _semWhere =
      'dept_id = ? AND section = ? AND semester = ?';

  static List<Object?> _semArgs(SemRef s) => [s.deptId, s.section, s.semester];

  static Future<Map<String, String>> students(SemRef s) async {
    try {
      final db = await _open();
      final rows = await db.query('students',
          where: _semWhere, whereArgs: _semArgs(s));
      return {
        for (final r in rows)
          (r['roll'] ?? '').toString(): (r['name'] ?? '').toString()
      };
    } catch (e) {
      debugPrint('LocalDb students error: $e');
      return {};
    }
  }

  static Future<Map<String, Map<String, String>>> overrides(
      SemRef s, String subject) async {
    try {
      final db = await _open();
      final rows = await db.query('overrides',
          where: '$_semWhere AND subject = ?',
          whereArgs: [..._semArgs(s), subject]);
      return {
        for (final r in rows)
          (r['roll'] ?? '').toString(): {
            'name': (r['name'] ?? '').toString(),
            'kind': (r['kind'] ?? '').toString(),
          }
      };
    } catch (e) {
      debugPrint('LocalDb overrides error: $e');
      return {};
    }
  }

  // Attendance records of a subject from SQLite, grouped by session.
  // monthPrefix = 'yyyy-MM' limits the result to one month.
  static Future<List<DateRecord>> dateRecords(SemRef s, String subject,
      {String? monthPrefix}) async {
    try {
      final db = await _open();
      final rows = await db.query(
        'attendance',
        where:
            '$_semWhere AND subject = ?${monthPrefix == null ? '' : ' AND session_id LIKE ?'}',
        whereArgs: [
          ..._semArgs(s),
          subject,
          if (monthPrefix != null) '$monthPrefix-%',
        ],
        orderBy: 'session_id',
      );
      final byId = <String, DateRecord>{};
      for (final r in rows) {
        final id = (r['session_id'] ?? '').toString();
        final rec = byId.putIfAbsent(
            id, () => DateRecord(id, <String, String>{}, <String, String>{}));
        rec.status[(r['roll'] ?? '').toString()] =
            (r['status'] ?? '').toString();
        final t = (r['marked_time'] ?? '').toString();
        if (t.isNotEmpty) rec.meta['_time'] = t;
        final by = (r['marked_by'] ?? '').toString();
        if (by.isNotEmpty) rec.meta['_marked_by'] = by;
        final byName = (r['marked_by_name'] ?? '').toString();
        if (byName.isNotEmpty) rec.meta['_marked_by_name'] = byName;
      }
      return byId.values.toList();
    } catch (e) {
      debugPrint('LocalDb dateRecords error: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> claimsOf(String teacherId) async {
    try {
      final db = await _open();
      final rows = await db
          .query('claims', where: 'teacher_id = ?', whereArgs: [teacherId]);
      return [
        for (final r in rows)
          {
            'dept': (r['dept_id'] ?? '').toString(),
            'section': (r['section'] ?? '').toString(),
            'semester': (r['semester'] ?? '').toString(),
            'subject': (r['subject'] ?? '').toString(),
          }
      ];
    } catch (e) {
      debugPrint('LocalDb claimsOf error: $e');
      return [];
    }
  }

  // Quick refresh of one subject's attendance from the server (used by the
  // monthly view so SQLite also shows records marked on other devices). Returns
  // true only if fresh server data was written.
  static Future<bool> refreshSubjectAttendance(SemRef s, String subject) async {
    try {
      if ((await _netState()) != _Net.reachable) return false;
      final snap =
          await s.dates(subject).get().timeout(const Duration(seconds: 10));
      if (snap.metadata.isFromCache) return false;
      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete('attendance',
            where: '$_semWhere AND subject = ?',
            whereArgs: [..._semArgs(s), subject]);
        final batch = txn.batch();
        for (final d in snap.docs) {
          final parsed = parseAttendance(d.data());
          parsed.status.forEach((roll, st) {
            batch.insert(
              'attendance',
              {
                'dept_id': s.deptId,
                'section': s.section,
                'semester': s.semester,
                'subject': subject,
                'session_id': d.id,
                'roll': roll,
                'status': st,
                'marked_time': parsed.meta['_time'] ?? '',
                'marked_by': parsed.meta['_marked_by'] ?? '',
                'marked_by_name': parsed.meta['_marked_by_name'] ?? '',
              },
              conflictAlgorithm: sql.ConflictAlgorithm.replace,
            );
          });
        }
        await batch.commit(noResult: true);
      });
      return true;
    } catch (e) {
      debugPrint('LocalDb refreshSubjectAttendance error: $e');
      return false;
    }
  }

  static Future<void> deleteAllAttendance() {
    return _run((db) async {
      await db.delete('attendance');
    });
  }
}

// Refreshes the SQLite copy from Firestore at most every few hours, and right
// after the phone comes back online. Safe to call any time.
Future<void> syncLocalDbIfStale({bool force = false}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('sqlite_last_sync_ms') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - last;
    if (!force && age < const Duration(hours: 3).inMilliseconds) return;
    final ok = await LocalDb.replaceAllFromFirestore();
    if (ok) {
      await prefs.setInt(
          'sqlite_last_sync_ms', DateTime.now().millisecondsSinceEpoch);
    }
  } catch (_) {}
}

// Login-time prefetch: students, subjects, semesters and attendance are cached
// with one query each, so the lists and attendance also show up offline.
Future<void> prefetchAllData() async {
  try {
    if ((await _netState()) != _Net.reachable) return;
    final fs = FirebaseFirestore.instance;
    const t = Duration(seconds: 20);
    final futures = <Future>[
      fs.collection('departments').get().timeout(t),
      fs.collectionGroup('semesters').get().timeout(t),
      fs.collectionGroup('students').get().timeout(t),
      fs.collectionGroup('subjects').get().timeout(t),
      fs.collectionGroup('overrides').get().timeout(t),
      fs.collectionGroup('dates').get().timeout(t),
      permissionsRef().get().timeout(t),
      if (!AppSession.isAdmin && AppSession.teacherId.isNotEmpty)
        teacherClaimsRef(AppSession.teacherId).get().timeout(t),
    ];
    await Future.wait(futures.map((f) => f.catchError((_) => null)));
  } catch (_) {}
}

// Departments screen (first screen after login, for admin and teacher)
class DepartmentsScreen extends StatefulWidget {
  // claimMode is the teacher's "Claim Subject" entry point: Department ->
  // Section -> Semester -> Subject (tap to claim).
  final bool claimMode;
  const DepartmentsScreen({super.key, this.claimMode = false});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  bool _seeded = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasOffline = false;
  Timer? _seedGuard;

  bool get _isAdmin => AppSession.isAdmin;

  @override
  void initState() {
    super.initState();
    if (widget.claimMode) {
      // The teacher home already did the prefetch and sync.
      _seeded = true;
      return;
    }
    if (_isAdmin) {
      unawaited(_adminBootstrap());
      // Never keep the admin on a spinner because of a slow network.
      _seedGuard = Timer(const Duration(seconds: 3), () {
        if (mounted && !_seeded) setState(() => _seeded = true);
      });
    } else {
      _seeded = true;
      unawaited(syncLocalDbIfStale());
    }
    unawaited(prefetchAllData());
    unawaited(_isOnline().then((on) => _wasOffline = !on));

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
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
    _seedGuard?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // On admin login, run these in order: seed -> second admin -> copy old
  // Software Engineering data into Section A / Semester 3 -> local sync.
  Future<void> _adminBootstrap() async {
    await _ensureSeedData();
    await ensureHiddenAdminDepartment();
    final moved = await migrateSoftwareEngineeringLegacy();
    if (moved && mounted) {
      showSnack(context,
          'Software Engineering ka purana data Section A → Semester 3 mein daal diya gaya.');
    }
    await syncLocalDbIfStale();
  }

  Future<void> _ensureSeedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('seed_done_v1') == true) {
      unawaited(FirebaseFirestore.instance
          .collection('meta')
          .doc('seed')
          .set({'done': true}, SetOptions(merge: true)).catchError((_) {}));
      if (mounted) setState(() => _seeded = true);
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final deptsCollection = firestore.collection('departments');

      if (!await _isOnline()) {
        if (mounted) setState(() => _seeded = true);
        return;
      }

      final metaSnap = await firestore
          .collection('meta')
          .doc('seed')
          .get()
          .timeout(_kNetworkTimeout);
      if (metaSnap.exists && metaSnap.data()?['done'] == true) {
        await prefs.setBool('seed_done_v1', true);
        if (mounted) setState(() => _seeded = true);
        return;
      }

      for (var name in fixedDepartments) {
        final docRef = deptsCollection.doc(name);
        final snap = await docRef.get().timeout(_kNetworkTimeout);
        if (!snap.exists) {
          await docRef.set({'name': name});
        }
      }

      // The old Software Engineering students and subjects are now seeded
      // directly into Section A / Semester 3.
      final target = SemRef(kSoftwareEngineeringDeptId, 'A', '3');
      final studentsSnap = await target.students.limit(1).get().timeout(_kNetworkTimeout);
      if (studentsSnap.docs.isEmpty) {
        var batch = firestore.batch();
        for (var s in initialStudents) {
          batch.set(target.students.doc(s['roll']),
              {'roll': s['roll'], 'name': s['name']});
        }
        await batch.commit();
      }

      final subjectsSnap = await target.subjects.limit(1).get().timeout(_kNetworkTimeout);
      if (subjectsSnap.docs.isEmpty) {
        var batch2 = firestore.batch();
        for (var sub in initialSubjects) {
          batch2.set(target.subjects.doc(sub), {'name': sub});
        }
        await batch2.commit();
      }

      await firestore
          .collection('meta')
          .doc('seed')
          .set({'done': true}).timeout(_kNetworkTimeout);
      await prefs.setBool('seed_done_v1', true);
    } catch (_) {}

    if (mounted) setState(() => _seeded = true);
  }

  // Departments no longer have their own passwords, so we ask the user to type
  // the department name to confirm the delete.
  void _confirmDeleteDepartment(String deptId, String deptName) {
    final controller = TextEditingController();
    String? errorText;
    bool busy = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Delete Department?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "All sections, semesters, students, subjects and attendance under '$deptName' will be permanently deleted. This cannot be undone.",
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Type the department name to confirm',
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (controller.text.trim() != deptName) {
                        setDialogState(() => errorText = 'Name does not match');
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                      });
                      try {
                        await deleteDepartmentEverywhere(deptId);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          showSnack(context, "Deleted department '$deptName'");
                        }
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          errorText = 'Could not delete. Please try again.';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Delete', style: TextStyle(color: kAbsent)),
            ),
          ],
        ),
      ),
    );
  }

  // Only the department name is needed now (no username or password).
  void _showAddDepartmentDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Department'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Department Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty || name.contains('/')) return;

              final docRef =
                  FirebaseFirestore.instance.collection('departments').doc(name);
              final existing = await safeGetDocOrNull(docRef);
              if (existing != null && existing.exists) {
                if (context.mounted) {
                  showSnack(context, 'This department name already exists');
                }
                return;
              }

              unawaited(docRef.set({'name': name}).catchError((_) {}));
              unawaited(LocalDb.upsertDepartment(name, name));

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Admin only: delete the overall attendance of every subject.
  void _confirmDeleteOverallAttendance() {
    bool busy = false;
    String? errorText;
    String? backupNote;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Delete overall attendance?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes the attendance records of EVERY subject in every department: from the server (Firebase), the local SQLite database and this device.\n\nDepartments, subjects and students are not touched. This cannot be undone.',
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Note: take a backup first, so you can restore it if this was a mistake.',
                  style: TextStyle(
                      color: kAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (backupNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(backupNote!,
                      style: const TextStyle(color: kPresent, fontSize: 13)),
                ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(errorText!,
                      style: const TextStyle(color: kAbsent, fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                        backupNote = null;
                      });
                      try {
                        if ((await _netState()) != _Net.reachable) {
                          throw Exception('offline');
                        }
                        final n = await createBackupFile();
                        setDialogState(() {
                          busy = false;
                          backupNote = 'Backup ready ($n records).';
                        });
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          errorText =
                              'Backup failed. Check your internet and try again.';
                        });
                      }
                    },
              child: const Text('Backup now'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                      });
                      if ((await _netState()) != _Net.reachable) {
                        setDialogState(() {
                          busy = false;
                          errorText =
                              'Internet is required so the records are also removed from the server. Please connect and try again.';
                        });
                        return;
                      }
                      try {
                        await deleteAllAttendanceEverywhere();
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          showSnack(context, 'All attendance records deleted');
                        }
                      } catch (_) {
                        setDialogState(() {
                          busy = false;
                          errorText =
                              'Could not delete. Please check your connection and try again.';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Delete everything',
                      style: TextStyle(color: kAbsent)),
            ),
          ],
        ),
      ),
    );
  }

  // Master switch: one button that applies to all teachers at once.
  void _showMasterSwitch() {
    final items = <({String key, String label, IconData icon})>[
      (key: kPermAnytime, label: 'TIME', icon: Icons.schedule),
      (key: kPermChangeTime, label: 'SET TIME', icon: Icons.access_time),
      (key: kPermChangeDate, label: 'DATE', icon: Icons.calendar_today),
      (key: kPermEdit, label: 'EDIT', icon: Icons.edit_outlined),
      (key: kPermDelete, label: 'DELETE', icon: Icons.delete_outline),
    ];

    void setPerms(Map<String, dynamic> m) {
      unawaited(permissionsRef()
          .set(m, SetOptions(merge: true))
          .catchError((_) {}));
    }

    showDialog(
      context: context,
      builder: (dialogContext) =>
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: permissionsRef().snapshots(),
        builder: (ctx, snap) {
          final d = snap.data?.data() ?? <String, dynamic>{};
          final on = d[kPermMaster] == true;
          return AlertDialog(
            title: const Text('Teacher permissions'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: on,
                      title: Text(on ? 'Master switch: ON' : 'Master switch: OFF'),
                      subtitle: const Text('ALL',
                          style: TextStyle(
                              color: kAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      onChanged: (v) => setPerms({kPermMaster: v}),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      on
                          ? 'Teachers can mark attendance at any time, add attendance for past dates, edit or delete records, and change the time or session.'
                          : 'Master switch OFF: turn on the options below one by one to give a teacher only that ability.',
                      style: const TextStyle(color: kMuted, fontSize: 13),
                    ),
                    const Divider(height: 20, color: kOutline),
                    for (final it in items)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(it.icon, color: kAccent),
                        value: on || d[it.key] == true,
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: kAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                it.label,
                                style: const TextStyle(
                                    color: kAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          _permSubtitle(it.key),
                          style: const TextStyle(color: kMuted, fontSize: 12),
                        ),
                        onChanged: on ? null : (v) => setPerms({it.key: v}),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Short English explanation shown under each permission's code label.
  String _permSubtitle(String key) {
    switch (key) {
      case kPermAnytime:
        return 'TIME: let the teacher mark attendance any time, not just the first $kMarkWindowMinutes minutes of the hour.';
      case kPermChangeTime:
        return 'SET TIME: let the teacher pick the class time manually.';
      case kPermChangeDate:
        return 'DATE: let the teacher choose any date, not just today.';
      case kPermEdit:
        return 'EDIT: let the teacher change attendance that is already taken.';
      case kPermDelete:
        return 'DELETE: let the teacher delete attendance records.';
      default:
        return '';
    }
  }

  void _showBackupRestore() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Backup & Restore'),
        content: const Text(
          'Backup saves all departments, subjects, students, teachers and attendance into one file that you can keep safely (phone, Google Drive, email).\n\n'
          'Restore reads that file and puts the data back if something was deleted by mistake.\n\n'
          'The file contains teacher passwords, so keep it private.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (mounted) restoreFromBackupUi(context);
            },
            child: const Text('Restore'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (mounted) runBackupWithUi(context);
            },
            child: const Text('Backup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.claimMode;
    return Scaffold(
      appBar: AppBar(
        title: Text(claim ? 'Claim Subject' : 'Departments'),
        actions: [
          if (_isAdmin && !claim)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Teacher permissions (master switch)',
              onPressed: _showMasterSwitch,
            ),
          if (_isAdmin && !claim) const TeacherRequestsButton(),
          if (_isAdmin && !claim)
            IconButton(
              icon: const Icon(Icons.backup_outlined),
              tooltip: 'Backup & Restore',
              onPressed: _showBackupRestore,
            ),
          if (_isAdmin && !claim)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: kAbsent),
              tooltip: 'Delete overall attendance',
              onPressed: _confirmDeleteOverallAttendance,
            ),
          if (!claim)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: () => confirmAndLogout(context),
            ),
        ],
      ),
      floatingActionButton: (_isAdmin && !claim)
          ? FloatingActionButton(
              onPressed: _showAddDepartmentDialog,
              backgroundColor: kButton,
              foregroundColor: kOnAccent,
              child: const Icon(Icons.add),
            )
          : null,
      body: !_seeded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (claim)
                  const InfoBanner(
                    text:
                        'Pick a department, then a section and semester. Tap a subject to claim it.',
                    icon: Icons.bookmark_add_outlined,
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: liveQuery(FirebaseFirestore.instance
                        .collection('departments')
                        .orderBy('name')),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      // Do not show the hidden admin in the department list.
                      final docs = (snapshot.data?.docs ?? [])
                          .where((d) => d.id != kHiddenAdminDeptName)
                          .toList();
                      if (!snapshot.hasData || docs.isEmpty) {
                        return const EmptyState(
                            icon: Icons.apartment, text: 'No department found.');
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 90),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final deptId = docs[index].id;
                          final deptName = (data['name'] ?? deptId).toString();

                          return AppCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SectionsScreen(
                                    deptId: deptId, deptName: deptName),
                              ),
                            ),
                            child: Row(
                              children: [
                                const IconBadge(icon: Icons.apartment),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(deptName,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                ),
                                if (_isAdmin)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: kAbsent),
                                    tooltip: 'Delete department',
                                    onPressed: () => _confirmDeleteDepartment(
                                        deptId, deptName),
                                  )
                                else
                                  const Icon(Icons.chevron_right, color: kMuted),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// Sections screen: Department -> Section A / B / C / D
class SectionsScreen extends StatelessWidget {
  final String deptId;
  final String deptName;
  const SectionsScreen({super.key, required this.deptId, required this.deptName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(deptName)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Choose a section',
                style: TextStyle(color: kMuted, fontSize: 14)),
          ),
          for (final sec in kSections)
            AppCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SemestersScreen(
                      deptId: deptId, deptName: deptName, section: sec),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(sec,
                        style: const TextStyle(
                            color: kAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Section $sec',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.chevron_right, color: kMuted),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

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

// Subjects screen (subjects of one department, section and semester)
// Admin: add / delete / open. Teacher: claim / unclaim / open (own subjects
// only).
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
                    if (isAdmin)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: kAbsent),
                        tooltip: 'Delete subject',
                        onPressed: () =>
                            _confirmDeleteSubject(context, subjectName),
                      )
                    else if (isMine)
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

// My subjects (subjects the teacher has claimed, with full context)
class SemLabelText extends StatelessWidget {
  final SemRef sem;
  final TextStyle? style;
  const SemLabelText({super.key, required this.sem, this.style});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: safeGetDocOrNull(sem.doc),
      builder: (context, snap) {
        final l = (snap.data?.data()?['label'] ?? '').toString();
        return Text(l.isEmpty ? defaultSemesterLabel(sem.semester) : l,
            style: style);
      },
    );
  }
}

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
    // Remove the entry only if the server confirms the subject is gone or
    // reassigned. When offline (or unreadable), just open it and never remove a
    // claim.
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

// Import students (Excel .xlsx / CSV / TXT)
// The file only needs names. Roll numbers are made in file order: the first
// name gets 1, the second 2, and so on. Both the admin (semester master list)
// and the teacher (subject list) use these helpers.
final RegExp _importLetterRe = RegExp(r'\p{L}', unicode: true);

void _importSnack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

List<List<String>> _parseCsvText(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final firstLine = text
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  var delim = ',';
  var best = -1;
  for (final d in [',', ';', '\t']) {
    final c = d.allMatches(firstLine).length;
    if (c > best) {
      best = c;
      delim = d;
    }
  }
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == delim) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().trim());
    rows.add(row);
  }
  return rows;
}

// The cell value type is different in different versions of the excel package,
// so we read it as dynamic and convert it to text.
String _excelCellText(dynamic data) {
  try {
    final v = data?.value;
    if (v == null) return '';
    final inner = (v as dynamic).value;
    if (inner is String) return inner.trim();
    try {
      final t = (inner as dynamic).text;
      if (t is String) return t.trim();
    } catch (_) {}
    return inner.toString().trim();
  } catch (_) {
    return '';
  }
}

// Rows that are never student names (totals, signature lines, ...).
final RegExp _importSkipRowRe = RegExp(
    r'^(total|grand total|average|signature|remarks?|present|absent)$',
    caseSensitive: false);

// Cleans one name cell: hidden/odd spaces, serial prefixes like "1." "01)" or
// "12 Rahul", and stray punctuation at the ends.
String _cleanImportedName(String raw) {
  var s = raw.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^\(?\d{1,6}\s*[.)\]:\-\u2013]\s*'), '');
  s = s.replaceFirst(RegExp(r'^\d{1,6}\s+(?=\p{L})', unicode: true), '');
  s = s.replaceAll(RegExp(r'^[\s,;:\-\u2013]+|[\s,;:\-\u2013]+$'), '');
  return s.trim();
}

// 0 = not a name header, 1 = full name, 2 = first name, 3 = last name.
int _importNameHeaderKind(String raw) {
  final c = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (c.isEmpty || c.length > 32) return 0;
  if (RegExp(r'father|mother|guardian|parent|husband|spouse').hasMatch(c) ||
      c.contains('\u092A\u093F\u0924\u093E') ||
      c.contains('\u092E\u093E\u0924\u093E')) {
    return 0;
  }
  if (RegExp(r'^(first|given)\b').hasMatch(c) && c.contains('name')) return 2;
  if (RegExp(r'^(last|sur|family)').hasMatch(c) && c.contains('name')) {
    return 3;
  }
  if (c == 'student' || c == 'students') return 1;
  if (RegExp(r'\b(names?|naam)\b').hasMatch(c) || c.contains('\u0928\u093E\u092E')) {
    return 1;
  }
  return 0;
}

bool _importLooksLikeName(String n) =>
    n.length >= 2 &&
    _importLetterRe.hasMatch(n) &&
    !RegExp(r'\d').hasMatch(n) &&
    !_importSkipRowRe.hasMatch(n);

List<String> _namesFromRows(List<List<String>> rows) {
  final data = rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
  if (data.isEmpty) return [];

  final out = <String>[];
  void add(String raw) {
    final name = _cleanImportedName(raw);
    if (name.isEmpty || !_importLetterRe.hasMatch(name)) return;
    if (_importSkipRowRe.hasMatch(name)) return;
    out.add(name);
  }

  // 1) Look for a header row in the first 15 rows (title rows above it are
  //    ignored). Supports "Name", "Student Name", "Name of Student", Hindi
  //    "naam", and separate "First Name" + "Last Name" columns.
  var headerRow = -1;
  var nameCol = -1, firstCol = -1, lastCol = -1;
  final scan = data.length < 15 ? data.length : 15;
  for (var i = 0; i < scan && headerRow < 0; i++) {
    var n = -1, f = -1, l = -1;
    for (var c = 0; c < data[i].length; c++) {
      final k = _importNameHeaderKind(data[i][c]);
      if (k == 1 && n < 0) {
        n = c;
      } else if (k == 2 && f < 0) {
        f = c;
      } else if (k == 3 && l < 0) {
        l = c;
      }
    }
    if (n >= 0 || (f >= 0 && l >= 0)) {
      headerRow = i;
      nameCol = n;
      firstCol = f;
      lastCol = l;
    }
  }

  if (headerRow >= 0) {
    for (final r in data.skip(headerRow + 1)) {
      String at(int c) => (c >= 0 && c < r.length) ? r[c] : '';
      if (nameCol >= 0) {
        add(at(nameCol));
      } else {
        add('${at(firstCol)} ${at(lastCol)}');
      }
    }
    return out;
  }

  // 2) No name header: skip a roll/serial header row if there is one, then
  //    pick the column that looks most like names (letters, no digits,
  //    preferably several words). Roll codes like "21CS001" are not names.
  const headerWords = {
    'roll', 'roll no', 'roll no.', 'roll number', 'rollno', 'sr', 'sr.',
    'sr no', 'sr no.', 'sr#', 's.no', 's no', 'sno', 'serial', 'serial no',
    '#', 'no', 'no.', 'id', 'reg no', 'registration no',
  };
  final firstNorm = data.first
      .map((c) => c.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim())
      .toList();
  final body = data.skip(firstNorm.any(headerWords.contains) ? 1 : 0).toList();
  var width = 0;
  for (final r in body) {
    if (r.length > width) width = r.length;
  }
  var bestCol = 0;
  var bestScore = -1;
  for (var c = 0; c < width; c++) {
    var score = 0;
    for (final r in body) {
      if (c >= r.length) continue;
      final n = _cleanImportedName(r[c]);
      if (_importLooksLikeName(n)) score += n.contains(' ') ? 3 : 2;
    }
    if (score > bestScore) {
      bestScore = score;
      bestCol = c;
    }
  }
  for (final r in body) {
    if (bestCol < r.length) add(r[bestCol]);
  }
  return out;
}

// Pick a file and read the list of names from it. Returns null on error.
Future<List<String>?> pickStudentNamesFromFile(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'csv', 'txt'],
    );
  } catch (e) {
    debugPrint('File picker error: $e');
    if (!context.mounted) return null;
    _importSnack(context, 'Could not open the file picker.');
    return null;
  }
  if (f == null) return null;

  Uint8List? bytes;
  try {
    bytes = await f.readAsBytes();
  } catch (_) {}
  if (bytes == null) {
    if (!context.mounted) return null;
    _importSnack(context, 'Could not read the selected file.');
    return null;
  }

  final ext = (f.extension ?? f.name.split('.').last).toLowerCase();
  List<String> names;
  try {
    if (ext == 'xlsx' || ext == 'xlsm') {
      var rows = <List<String>>[];
      for (final r in _allXlsxGrids(bytes, forAttendance: false)) {
        if (_namesFromRows(r).isNotEmpty) {
          rows = r;
          break;
        }
      }
      names = _namesFromRows(rows);
    } else if (ext == 'txt') {
      final lines = utf8
          .decode(bytes, allowMalformed: true)
          .replaceFirst('\uFEFF', '')
          .split(RegExp(r'\r?\n'));
      names = _namesFromRows([
        for (final l in lines) [l.trim()]
      ]);
    } else {
      names = _namesFromRows(
          _parseCsvText(utf8.decode(bytes, allowMalformed: true)));
    }
  } catch (e) {
    debugPrint('Import parse error: $e');
    if (!context.mounted) return null;
    _importSnack(context,
        'Could not read this file. Please use .xlsx, .csv or .txt (old .xls is not supported).');
    return null;
  }

  if (names.isEmpty) {
    if (!context.mounted) return null;
    _importSnack(context, 'No student names found in this file.');
    return null;
  }
  return names;
}

// Confirm dialog. Asks for the first roll number (default 1) and returns it,
// or null if cancelled. It shows the resulting roll range live and warns if
// some of those roll numbers are already used (existingRolls).
Future<int?> confirmStudentImport(
  BuildContext context,
  List<String> names,
  String where, {
  Set<String> existingRolls = const <String>{},
}) {
  final startCtrl = TextEditingController(text: '1');
  final seen = <String>{};
  var dupes = 0;
  for (final n in names) {
    if (!seen.add(n.toLowerCase())) dupes++;
  }
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final parsed = int.tryParse(startCtrl.text.trim());
        final int? start = (parsed != null && parsed >= 1) ? parsed : null;
        var clash = 0;
        if (start != null) {
          for (var i = 0; i < names.length; i++) {
            if (existingRolls.contains((start + i).toString())) clash++;
          }
        }
        return AlertDialog(
          title: Text(
              'Import ${names.length} student${names.length == 1 ? '' : 's'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Into: $where',
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 10),
                for (final n in names.take(5))
                  Text('\u2022 $n', maxLines: 1, overflow: TextOverflow.ellipsis),
                if (names.length > 5)
                  Text('\u2026 and ${names.length - 5} more',
                      style: const TextStyle(color: kMuted)),
                if (dupes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$dupes name${dupes == 1 ? '' : 's'} appear more than once in the file.',
                    style: const TextStyle(color: kAccent, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Roll numbers are given in file order, counting up from '
                  'the number you enter (first name = first roll number).',
                  style: TextStyle(color: kMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: startCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    labelText: 'First roll number',
                    errorText:
                        start != null ? null : 'Enter a number (1 or more)',
                    helperText: start != null
                        ? 'Roll $start to ${start + names.length - 1}'
                        : null,
                  ),
                ),
                if (clash > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$clash of these roll numbers already exist. The new '
                    'students will be added next to them with the same roll '
                    'number; nothing is overwritten.',
                    style: const TextStyle(color: kAccent, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  start != null ? () => Navigator.pop(ctx, start) : null,
              child: const Text('Import'),
            ),
          ],
        );
      },
    ),
  );
}

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
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Student' : 'Add Student'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rollController,
              enabled: !isEditing,
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final roll = rollController.text.trim();
              final name = nameController.text.trim();
              if (roll.isEmpty || name.isEmpty) return;

              // Edit: the same student (existingRoll is its key). Add: if the
              // roll already exists, a new unique key is created and the old
              // student is not overwritten.
              String key = existingRoll ?? roll;
              if (!isEditing) {
                final existing = await loadSemesterStudents(sem);
                key = uniqueStudentKey(roll, existing.map((s) => s['roll']!));
              }
              unawaited(sem.students
                  .doc(key)
                  .set({'roll': key, 'name': name}).catchError((_) {}));
              unawaited(LocalDb.upsertStudent(sem, key, name));

              if (context.mounted) Navigator.pop(context);
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
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
      // If the roll already exists, a new unique key is created and nothing is
      // overwritten.
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

// Subject students (add / "remove" for this subject only)
// Remove is a soft remove: the student is not deleted from the admin's master
// list, just hidden from this subject's list.
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
              // If the same roll already exists (master / extra / hidden),
              // create a unique key.
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

// Time picker (6:00 AM to 6:00 PM only)
// Flutter's default picker cannot limit the range, so this is a small custom
// dialog: hours from 6 AM to 6 PM, and only :00 at 6 PM.
Future<TimeOfDay?> pickClassTime(BuildContext context, TimeOfDay? initial) {
  int hour = (initial?.hour ?? 9).clamp(kPickerStartHour, kPickerEndHour).toInt();
  int minute = initial?.minute ?? 0;
  if (hour == kPickerEndHour) minute = 0;

  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final maxMinute = hour == kPickerEndHour ? 0 : 59;
        return AlertDialog(
          title: const Text('Select class time'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: hour,
                items: [
                  for (int h = kPickerStartHour; h <= kPickerEndHour; h++)
                    DropdownMenuItem(
                      value: h,
                      child: Text(DateFormat('hh a').format(DateTime(2000, 1, 1, h))),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() {
                    hour = v;
                    if (hour == kPickerEndHour) minute = 0;
                  });
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(':', style: TextStyle(fontSize: 20)),
              ),
              DropdownButton<int>(
                value: minute > maxMinute ? 0 : minute,
                items: [
                  for (int m = 0; m <= maxMinute; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => minute = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
              child: const Text('OK'),
            ),
          ],
        );
      },
    ),
  );
}

// Import old attendance (Excel .xlsx / CSV) into a subject's attendance
// Expected layout: a row of dates on top, student names on the left, and P / A
// under each date. Each date becomes one session record. Excel files exported
// by this app can be imported directly.
class ImportColumn {
  final int col;
  final DateTime date;
  final int session;
  ImportColumn(this.col, this.date, this.session);
  String get docId =>
      '${DateFormat('yyyy-MM-dd').format(date)}_Session_$session';
}

class ImportRow {
  final String name;
  final String roll; // roll from the file (only if there is a 'Roll' column)
  final Map<int, String> status; // column index -> 'P' / 'A'
  ImportRow(this.name, this.roll, this.status);
}

class ImportSheet {
  final List<ImportColumn> columns;
  final List<ImportRow> rows;
  ImportSheet(this.columns, this.rows);
}

class ImportPlan {
  final Map<int, String> rowToStudent; // file row index -> student key
  final Set<int> cols; // date columns to import
  final bool blankPresent; // blank cell = Present (otherwise Absent)
  ImportPlan(this.rowToStudent, this.cols, this.blankPresent);
}

const Map<String, int> _kImportMonths = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

DateTime? _importMakeDate(int y, int m, int d) {
  if (y < 100) y += 2000;
  if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  if (dt.month != m || dt.day != d) return null;
  return dt;
}

// true: 12/09/2025 means 12 Sep (day first). false: it means Dec 9.
// parseAttendanceSheet sets this by looking at the whole sheet.
bool _importDayFirst = true;

bool _inferDayFirst(List<List<String>> g) {
  var df = 0, mf = 0;
  final re = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$');
  for (final r in g) {
    for (final t in r) {
      final m = re.firstMatch(t.trim());
      if (m == null) continue;
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      if (a > 12 && b <= 12) {
        df++;
      } else if (b > 12 && a <= 12) {
        mf++;
      }
    }
  }
  return mf <= df;
}

// Reads a date from cell text. Numeric formats are treated as day first
// (dd/mm/yyyy).
DateTime? _parseImportDate(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // Excel serial number (e.g. 45912)
  final serial = double.tryParse(s);
  if (serial != null) {
    if (serial >= 36000 && serial <= 60000) {
      return DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
    }
    return null;
  }

  s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  s = s.replaceAll(
      RegExp(r'\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\b[\s,.\-]*',
          caseSensitive: false),
      ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return null;

  // 2025-09-12 (a time after it is fine too)
  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)').firstMatch(s);
  if (m != null) {
    return _importMakeDate(int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!));
  }

  // 12/09/2025, 12-09-25, 12.09.2025
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    int day, mon;
    if (a > 12 && b <= 12) {
      day = a;
      mon = b;
    } else if (b > 12 && a <= 12) {
      day = b;
      mon = a;
    } else if (_importDayFirst) {
      day = a;
      mon = b;
    } else {
      day = b;
      mon = a;
    }
    return _importMakeDate(y, mon, day);
  }

  // 12 Sep 2025, 12-Sep-25, 12th September
  m = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?[\s,./-]*([A-Za-z]{3,})[\s,./-]*(\d{2,4})?$')
      .firstMatch(s);
  if (m != null) {
    final mon = _kImportMonths[m.group(2)!.toLowerCase().substring(0, 3)];
    if (mon != null) {
      final y = m.group(3) == null ? DateTime.now().year : int.parse(m.group(3)!);
      return _importMakeDate(y, mon, int.parse(m.group(1)!));
    }
  }

  // Sep 12, 2025
  m = RegExp(r'^([A-Za-z]{3,})[\s,./-]*(\d{1,2})(?:st|nd|rd|th)?[\s,./-]*(\d{2,4})?$')
      .firstMatch(s);
  if (m != null) {
    final mon = _kImportMonths[m.group(1)!.toLowerCase().substring(0, 3)];
    if (mon != null) {
      final y = m.group(3) == null ? DateTime.now().year : int.parse(m.group(3)!);
      return _importMakeDate(y, mon, int.parse(m.group(2)!));
    }
  }
  return null;
}

// 'P' / 'A', or null (blank or not understood).
String? _parseImportStatus(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  final n = double.tryParse(s);
  if (n != null) {
    if (n == 1) return 'P';
    if (n == 0) return 'A';
    return null;
  }
  // "P.", "(P)", "Pre sent" -> remove punctuation and spaces
  s = s.replaceAll(RegExp(r'[\s.\-_()\[\]]+'), '');
  if (s.isEmpty) return null;
  const present = {
    'p', 'pr', 'prs', 'prsnt', 'pre', 'present', 'y', 'yes', 'true',
    'late', 'lt', 'od', '✓', '✔', '√', '☑', '✅'
  };
  const absent = {
    'a', 'ab', 'abs', 'abst', 'absnt', 'absent', 'n', 'no', 'false', 'x',
    'l', 'lv', 'leave', '✗', '✘', '✕', '✖', '❌'
  };
  if (present.contains(s)) return 'P';
  if (absent.contains(s)) return 'A';
  if (s.startsWith('present')) return 'P';
  if (s.startsWith('absent')) return 'A';
  return null;
}

// Text of an Excel cell. Date cells become yyyy-MM-dd.
String _importCellText(dynamic data) {
  try {
    final inner = (data?.value) as dynamic;
    if (inner == null) return '';
    final typeName = inner.runtimeType.toString();
    if (typeName.contains('Date')) {
      DateTime? dt;
      try {
        dt = inner.asDateTimeLocal() as DateTime;
      } catch (_) {}
      if (dt == null) {
        try {
          dt = DateTime(inner.year as int, inner.month as int, inner.day as int);
        } catch (_) {}
      }
      if (dt != null) return DateFormat('yyyy-MM-dd').format(dt);
    }
    if (typeName.contains('Double')) {
      final d = inner.value as double;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
  } catch (_) {}
  return _excelCellText(data);
}

// Fallback XLSX reader. The 'excel' package often crashes on files from WPS,
// Google Sheets and mobile apps ("not found" / null error). This reads the XML
// inside the zip directly, so every kind of .xlsx opens.
String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&amp;', '&');

String _xmlTextOf(String xml) {
  final cleaned =
      xml.replaceAll(RegExp(r'<rPh\b[^>]*>.*?</rPh>', dotAll: true), '');
  final b = StringBuffer();
  for (final m
      in RegExp(r'<t\b[^>]*?(?:/>|>(.*?)</t>)', dotAll: true).allMatches(cleaned)) {
    b.write(m.group(1) ?? '');
  }
  return _xmlUnescape(b.toString());
}

int _xlsxColIndex(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u >= 65 && u <= 90) {
      n = n * 26 + (u - 64);
    } else if (u >= 97 && u <= 122) {
      n = n * 26 + (u - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

int _xlsxRowIndex(String ref) =>
    (int.tryParse(ref.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1) - 1;

bool _xlsxIsDateFmt(int id, String? code) {
  if ((id >= 14 && id <= 22) ||
      (id >= 27 && id <= 36) ||
      (id >= 45 && id <= 47) ||
      (id >= 50 && id <= 58)) {
    return true;
  }
  if (code == null) return false;
  final c = code
      .replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '')
      .toLowerCase()
      .replaceAll('general', '');
  return RegExp(r'[dmyh]').hasMatch(c);
}

List<bool> _xlsxDateStyles(String xml) {
  final fmts = <int, String>{};
  for (final m in RegExp(r'<numFmt\b([^>]*?)/?>').allMatches(xml)) {
    final a = m.group(1)!;
    final id =
        int.tryParse(RegExp(r'numFmtId="(\d+)"').firstMatch(a)?.group(1) ?? '');
    final code = RegExp(r'formatCode="([^"]*)"').firstMatch(a)?.group(1);
    if (id != null && code != null) fmts[id] = _xmlUnescape(code);
  }
  final out = <bool>[];
  final cx =
      RegExp(r'<cellXfs\b[^>]*>(.*?)</cellXfs>', dotAll: true).firstMatch(xml);
  if (cx == null) return out;
  for (final m in RegExp(r'<xf\b([^>]*?)/?>').allMatches(cx.group(1)!)) {
    final id = int.tryParse(
            RegExp(r'numFmtId="(\d+)"').firstMatch(m.group(1)!)?.group(1) ??
                '') ??
        0;
    out.add(_xlsxIsDateFmt(id, fmts[id]));
  }
  return out;
}

List<List<String>> _xlsxSheetGrid(
    String xml, List<String> shared, List<bool> dateStyle) {
  final cells = <int, Map<int, String>>{};
  var maxC = 0, maxR = 0;
  for (final m
      in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(xml)) {
    final attrs = m.group(1)!;
    final body = m.group(2) ?? '';
    final ref = RegExp(r'\br="([A-Za-z]+\d+)"').firstMatch(attrs)?.group(1);
    if (ref == null) continue;
    final r = _xlsxRowIndex(ref);
    final c = _xlsxColIndex(ref);
    if (r < 0 || c < 0 || r > 4000 || c > 400) continue;
    final t = RegExp(r'\bt="(\w+)"').firstMatch(attrs)?.group(1) ?? 'n';
    final si =
        int.tryParse(RegExp(r'\bs="(\d+)"').firstMatch(attrs)?.group(1) ?? '');
    final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1);
    var text = '';
    if (t == 'inlineStr') {
      text = _xmlTextOf(body);
    } else if (v == null) {
      text = '';
    } else if (t == 's') {
      final i = int.tryParse(v.trim());
      text = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
    } else if (t == 'str' || t == 'e') {
      text = _xmlUnescape(v);
    } else if (t == 'b') {
      text = v.trim() == '1' ? 'TRUE' : 'FALSE';
    } else {
      final n = double.tryParse(v.trim());
      if (n == null) {
        text = v.trim();
      } else if (si != null && si < dateStyle.length && dateStyle[si] && n >= 1) {
        final d = DateTime(1899, 12, 30).add(Duration(days: n.floor()));
        text = DateFormat('yyyy-MM-dd').format(d);
      } else {
        text = n == n.roundToDouble() ? n.toInt().toString() : v.trim();
      }
    }
    text = text.trim();
    if (text.isEmpty) continue;
    (cells[r] ??= <int, String>{})[c] = text;
    if (r > maxR) maxR = r;
    if (c > maxC) maxC = c;
  }
  if (cells.isEmpty) return [];
  return [
    for (var r = 0; r <= maxR; r++)
      [for (var c = 0; c <= maxC; c++) cells[r]?[c] ?? '']
  ];
}

List<List<List<String>>> _rawXlsxGrids(Uint8List bytes) {
  final arch = zip.ZipDecoder().decodeBytes(bytes);
  String? read(String name) {
    for (final f in arch.files) {
      if (f.name.replaceAll('\\', '/') == name) {
        final c = (f as dynamic).content;
        if (c is List<int>) return utf8.decode(c, allowMalformed: true);
      }
    }
    return null;
  }

  final shared = <String>[];
  final ss = read('xl/sharedStrings.xml');
  if (ss != null) {
    for (final m in RegExp(r'<si\b[^>]*?(?:/>|>(.*?)</si>)', dotAll: true)
        .allMatches(ss)) {
      shared.add(_xmlTextOf(m.group(1) ?? ''));
    }
  }
  final st = read('xl/styles.xml');
  final dateStyle = st == null ? <bool>[] : _xlsxDateStyles(st);

  final names = <MapEntry<int, String>>[];
  for (final f in arch.files) {
    final n = f.name.replaceAll('\\', '/');
    final m = RegExp(r'^xl/worksheets/sheet(\d+)\.xml$').firstMatch(n);
    if (m != null) names.add(MapEntry(int.parse(m.group(1)!), n));
  }
  names.sort((a, b) => a.key.compareTo(b.key));

  final out = <List<List<String>>>[];
  for (final e in names) {
    final xml = read(e.value);
    if (xml == null) continue;
    final g = _xlsxSheetGrid(xml, shared, dateStyle);
    if (g.isNotEmpty) out.add(g);
  }
  return out;
}

// Grids of all sheets, from the excel package and the fallback reader.
List<List<List<String>>> _allXlsxGrids(Uint8List bytes,
    {required bool forAttendance}) {
  final out = <List<List<String>>>[];
  try {
    final book = excel_lib.Excel.decodeBytes(bytes);
    for (final table in book.tables.values) {
      final r = table.rows
          .map((row) => row
              .map((c) => forAttendance ? _importCellText(c) : _excelCellText(c))
              .toList())
          .toList();
      if (r.any((x) => x.any((c) => c.isNotEmpty))) out.add(r);
    }
  } catch (e) {
    debugPrint('excel package failed: $e');
  }
  try {
    out.addAll(_rawXlsxGrids(bytes));
  } catch (e) {
    debugPrint('raw xlsx reader failed: $e');
  }
  return out;
}

// parseAttendanceSheet (works with any layout)
// Detects three layouts by itself and uses the one with the most P/A entries:
//   1) WIDE       : dates in one row, student names in one column (P/A below)
//   2) TRANSPOSED : dates in one column, student names in the top row
//   3) LONG       : each row = Date | Name | Status (any column order)
// Column order, extra columns and status wording (P / Present / 1 / ...) do not
// matter. ImportColumn.col is just a unique id, so it works for every layout.
class _ImportHeader {
  final int row;
  final Map<int, DateTime> dates;
  _ImportHeader(this.row, this.dates);
}

class _ImportDraft {
  final List<ImportColumn> columns;
  final List<ImportRow> rows;
  _ImportDraft(this.columns, this.rows);
  int get score {
    var n = 0;
    for (final r in rows) {
      n += r.status.length;
    }
    return n;
  }
}

class _ImportLongRec {
  final String name;
  final String roll;
  final DateTime date;
  final int sess;
  final String status;
  _ImportLongRec(this.name, this.roll, this.date, this.sess, this.status);
}

final RegExp _importSessionRe = RegExp(
    r'(?:session|lecture|lec|class|period|slot)\s*#?\s*[-:]?\s*(\d+)',
    caseSensitive: false);

final RegExp _importSkipNameRe = RegExp(
    r'^(time|total|totals|session|date|name|names|percentage|percent|present|absent|average|avg|summary|signature|sign|sr|sno|roll|remarks?|day|month|week|subject|faculty|teacher)\b',
    caseSensitive: false);

bool _importIsNameHeader(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return false;
  if (RegExp(r'father|mother|parent|guardian').hasMatch(t)) return false;
  return t == 'student' || t == 'naam' || t.contains('name');
}

bool _importIsRollHeader(String raw) {
  final t = raw.trim().toLowerCase();
  return t.contains('roll') ||
      t.startsWith('reg') ||
      t.contains('enrol') ||
      t.contains('admission');
}

// "1. Ali Khan" / "01 Ali Khan" -> "Ali Khan"
String _importCleanName(String raw) {
  final s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final stripped =
      s.replaceFirst(RegExp(r'^\d+\s*[.)\-:]\s*|^\d+\s+(?=\p{L})', unicode: true), '');
  return _importLetterRe.hasMatch(stripped) ? stripped.trim() : s;
}

List<List<String>> _importPad(List<List<String>> rows) {
  var w = 0;
  for (final r in rows) {
    if (r.length > w) w = r.length;
  }
  return [
    for (final r in rows)
      [for (var c = 0; c < w; c++) c < r.length ? r[c].trim() : '']
  ];
}

List<List<String>> _importTranspose(List<List<String>> g) {
  if (g.isEmpty) return g;
  final nC = g[0].length;
  return [
    for (var c = 0; c < nC; c++) [for (var r = 0; r < g.length; r++) g[r][c]]
  ];
}

_ImportHeader? _importHeaderFromRow(List<List<String>> g, int r) {
  final dates = <int, DateTime>{};
  for (var c = 0; c < g[r].length; c++) {
    final d = _parseImportDate(g[r][c]);
    if (d != null) dates[c] = d;
  }
  return dates.isEmpty ? null : _ImportHeader(r, dates);
}

// Gets [year, month] from the title or header (e.g. "September 2025",
// "09/2025").
List<int>? _importFindMonthYear(List<List<String>> g, int upToRow) {
  final monthRe = RegExp(
      r"\b(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)\b(?:[\s,.\-/']*(20\d{2}))?",
      caseSensitive: false);
  final mYRe = RegExp(r'\b(\d{1,2})\s*[/\-.]\s*(20\d{2})\b');
  final yMRe = RegExp(r'\b(20\d{2})\s*[-/.]\s*(\d{1,2})\b');
  final yearRe = RegExp(r'\b(20\d{2})\b');
  int? looseYear;
  for (var r = 0; r <= upToRow && r < g.length; r++) {
    for (final t in g[r]) {
      if (t.isEmpty) continue;
      looseYear ??= int.tryParse(yearRe.firstMatch(t)?.group(1) ?? '');
    }
  }
  for (var r = 0; r <= upToRow && r < g.length; r++) {
    for (final t in g[r]) {
      if (t.isEmpty) continue;
      var m = monthRe.firstMatch(t);
      if (m != null) {
        final mon = _kImportMonths[m.group(1)!.toLowerCase().substring(0, 3)];
        if (mon != null) {
          final y = int.tryParse(m.group(2) ?? '') ??
              looseYear ??
              DateTime.now().year;
          return [y, mon];
        }
      }
      m = mYRe.firstMatch(t);
      if (m != null) {
        final mon = int.parse(m.group(1)!);
        if (mon >= 1 && mon <= 12) return [int.parse(m.group(2)!), mon];
      }
      m = yMRe.firstMatch(t);
      if (m != null) {
        final mon = int.parse(m.group(2)!);
        if (mon >= 1 && mon <= 12) return [int.parse(m.group(1)!), mon];
      }
      final d = _parseImportDate(t);
      if (d != null) return [d.year, d.month];
    }
  }
  return null;
}

// A header row with only day numbers (1 2 3 ... 31), with the month and year
// above it.
_ImportHeader? _importDayNumberHeader(List<List<String>> g, int limit) {
  final dayRe = RegExp(r'^(\d{1,2})$');
  for (var r = 0; r < limit; r++) {
    final cols = <int>[];
    final nums = <int>[];
    for (var c = 0; c < g[r].length; c++) {
      final m = dayRe.firstMatch(g[r][c]);
      if (m == null) continue;
      final v = int.parse(m.group(1)!);
      if (v >= 1 && v <= 31) {
        cols.add(c);
        nums.add(v);
      }
    }
    if (cols.length < 5) continue;
    var inc = 0;
    for (var i = 1; i < nums.length; i++) {
      if (nums[i] > nums[i - 1]) inc++;
    }
    if (inc < (nums.length - 1) * 0.7) continue;
    final my = _importFindMonthYear(g, r);
    if (my == null) continue;
    final dates = <int, DateTime>{};
    for (var i = 0; i < cols.length; i++) {
      final d = _importMakeDate(my[0], my[1], nums[i]);
      if (d != null) dates[cols[i]] = d;
    }
    if (dates.length >= 2) return _ImportHeader(r, dates);
  }
  return null;
}

_ImportHeader? _importFindDateHeader(List<List<String>> g) {
  final nR = g.length;
  final limit = nR < 40 ? nR : 40;
  var bestRow = -1;
  var bestCnt = 0;
  for (var r = 0; r < limit; r++) {
    var cnt = 0;
    for (final t in g[r]) {
      if (_parseImportDate(t) != null) cnt++;
    }
    if (cnt > bestCnt) {
      bestCnt = cnt;
      bestRow = r;
    }
  }
  if (bestCnt >= 2) return _importHeaderFromRow(g, bestRow);
  final alt = _importDayNumberHeader(g, limit);
  if (alt != null) return alt;
  if (bestCnt == 1) return _importHeaderFromRow(g, bestRow);
  return null;
}

// ---- Layout 1: dates on top, names on the left (or anywhere) ----
_ImportDraft? _importParseWide(List<List<String>> g) {
  final nR = g.length;
  final nC = nR == 0 ? 0 : g[0].length;
  if (nR < 2 || nC < 2) return null;
  String cell(int r, int c) =>
      (r >= 0 && r < nR && c >= 0 && c < nC) ? g[r][c] : '';

  final hdr = _importFindDateHeader(g);
  if (hdr == null) return null;
  final dateRow = hdr.row;
  final dates = hdr.dates;
  final dateKeys = dates.keys.toList()..sort();
  final firstDateCol = dateKeys.first;

  // Name column: the one with 'name' in its header, otherwise the one with the
  // most text (not status).
  var nameCol = -1;
  var bestScore = 0.0;
  for (var c = 0; c < nC; c++) {
    if (dates.containsKey(c)) continue;
    var bonus = 0.0;
    for (var r = 0; r <= dateRow + 2 && r < nR; r++) {
      if (_importIsNameHeader(cell(r, c))) {
        bonus = 1000000.0;
        break;
      }
    }
    var txt = 0, stat = 0, filled = 0;
    for (var r = dateRow + 1; r < nR; r++) {
      final t = cell(r, c);
      if (t.isEmpty) continue;
      filled++;
      if (_parseImportStatus(t) != null) {
        stat++;
        continue;
      }
      if (!_importLetterRe.hasMatch(t) || _parseImportDate(t) != null) continue;
      txt += t.length > 40 ? 40 : t.length;
    }
    if (txt == 0 || stat * 2 > filled) continue;
    var score = txt.toDouble();
    if (c > firstDateCol) score *= 0.5;
    score += bonus;
    if (score > bestScore) {
      bestScore = score;
      nameCol = c;
    }
  }
  if (nameCol < 0) return null;

  // Roll column: only if the header has roll / reg / enrol / admission.
  var rollCol = -1;
  for (var c = 0; c < nC && rollCol < 0; c++) {
    if (c == nameCol || dates.containsKey(c)) continue;
    for (var r = 0; r <= dateRow + 2 && r < nR; r++) {
      if (_importIsRollHeader(cell(r, c))) {
        rollCol = c;
        break;
      }
    }
  }

  // Student rows
  final nameRows = <int>[];
  final names = <int, String>{};
  for (var r = dateRow + 1; r < nR; r++) {
    final name = _importCleanName(cell(r, nameCol));
    if (name.isEmpty || !_importLetterRe.hasMatch(name)) continue;
    if (_importSkipNameRe.hasMatch(name)) continue;
    if (_parseImportStatus(name) != null || _parseImportDate(name) != null) {
      continue;
    }
    nameRows.add(r);
    names[r] = name;
  }
  if (nameRows.isEmpty) return null;

  // Merged date header (several session columns under one date): the blank
  // header cells that follow, if they have P/A, belong to the same date.
  final colDate = Map<int, DateTime>.from(dates);
  for (final c in dateKeys) {
    for (var k = c + 1; k < nC; k++) {
      if (dates.containsKey(k) || k == nameCol || k == rollCol) break;
      if (cell(dateRow, k).isNotEmpty) break;
      var hits = 0;
      for (final r in nameRows) {
        if (_parseImportStatus(cell(r, k)) != null) hits++;
      }
      if (hits == 0 || hits * 2 < nameRows.length) break;
      colDate[k] = dates[c]!;
    }
  }

  // Session numbers: use "Session 2" if the header has it, otherwise count 1,
  // 2, 3 when the same date repeats.
  final allCols = colDate.keys.toList()..sort();
  final used = <String>{};
  final counter = <String, int>{};
  final columns = <ImportColumn>[];
  for (final c in allCols) {
    final d = colDate[c]!;
    final dayKey = DateFormat('yyyy-MM-dd').format(d);
    int? hint;
    for (final rr in [dateRow + 1, dateRow - 1]) {
      if (names.containsKey(rr)) continue;
      final sm = _importSessionRe.firstMatch(cell(rr, c));
      if (sm != null) {
        hint = int.tryParse(sm.group(1) ?? '');
        break;
      }
    }
    var sess = hint ?? ((counter[dayKey] ?? 0) + 1);
    while (used.contains('${dayKey}_$sess')) {
      sess++;
    }
    used.add('${dayKey}_$sess');
    counter[dayKey] = sess;
    columns.add(ImportColumn(c, d, sess));
  }

  final outRows = <ImportRow>[];
  for (final r in nameRows) {
    final st = <int, String>{};
    for (final col in columns) {
      final v = _parseImportStatus(cell(r, col.col));
      if (v != null) st[col.col] = v;
    }
    if (st.isEmpty) continue;
    outRows.add(ImportRow(names[r]!, rollCol >= 0 ? cell(r, rollCol) : '', st));
  }
  if (outRows.isEmpty) return null;

  final usedCols = <int>{for (final row in outRows) ...row.status.keys};
  final keepCols = columns.where((c) => usedCols.contains(c.col)).toList();
  if (keepCols.isEmpty) return null;
  return _ImportDraft(keepCols, outRows);
}

// ---- Layout 3: each row = Date | Name | Status ----
_ImportDraft? _importParseLong(List<List<String>> g) {
  final nR = g.length;
  final nC = nR == 0 ? 0 : g[0].length;
  if (nR < 3 || nC < 3) return null;

  final dateCnt = List<int>.filled(nC, 0);
  final statCnt = List<int>.filled(nC, 0);
  for (var r = 0; r < nR; r++) {
    for (var c = 0; c < nC; c++) {
      final t = g[r][c];
      if (t.isEmpty) continue;
      if (_parseImportStatus(t) != null) {
        statCnt[c]++;
      } else if (_parseImportDate(t) != null) {
        dateCnt[c]++;
      }
    }
  }
  int argmax(List<int> v, int skip1, int skip2) {
    var bi = -1, bv = 1; // at least 2
    for (var c = 0; c < v.length; c++) {
      if (c == skip1 || c == skip2) continue;
      if (v[c] > bv) {
        bv = v[c];
        bi = c;
      }
    }
    return bi;
  }

  final dateCol = argmax(dateCnt, -1, -1);
  final statusCol = argmax(statCnt, dateCol, -1);
  if (dateCol < 0 || statusCol < 0) return null;

  bool headerHas(int c, bool Function(String) test) {
    for (var r = 0; r < nR && r < 10; r++) {
      if (test(g[r][c])) return true;
    }
    return false;
  }

  var nameCol = -1;
  var bestScore = 0.0;
  for (var c = 0; c < nC; c++) {
    if (c == dateCol || c == statusCol) continue;
    var txt = 0;
    for (var r = 0; r < nR; r++) {
      final t = g[r][c];
      if (t.isEmpty || !_importLetterRe.hasMatch(t)) continue;
      if (_parseImportStatus(t) != null || _parseImportDate(t) != null) continue;
      txt += t.length > 40 ? 40 : t.length;
    }
    if (txt == 0) continue;
    var score = txt.toDouble();
    if (headerHas(c, _importIsNameHeader)) score += 1000000.0;
    if (score > bestScore) {
      bestScore = score;
      nameCol = c;
    }
  }
  if (nameCol < 0) return null;

  var rollCol = -1;
  var sessCol = -1;
  final sessHeaderRe = RegExp(r'session|lecture|period|slot', caseSensitive: false);
  for (var c = 0; c < nC; c++) {
    if (c == dateCol || c == statusCol || c == nameCol) continue;
    if (rollCol < 0 && headerHas(c, _importIsRollHeader)) rollCol = c;
    if (sessCol < 0 && headerHas(c, (t) => sessHeaderRe.hasMatch(t))) sessCol = c;
  }

  final recs = <_ImportLongRec>[];
  final occ = <String, int>{};
  for (var r = 0; r < nR; r++) {
    final d = _parseImportDate(g[r][dateCol]);
    final st = _parseImportStatus(g[r][statusCol]);
    final name = _importCleanName(g[r][nameCol]);
    if (d == null || st == null) continue;
    if (name.isEmpty || !_importLetterRe.hasMatch(name)) continue;
    if (_importSkipNameRe.hasMatch(name)) continue;
    final dayKey = DateFormat('yyyy-MM-dd').format(d);
    final ok = '$dayKey|${_normImportName(name)}';
    final n = (occ[ok] ?? 0) + 1;
    occ[ok] = n;
    var sess = n;
    if (sessCol >= 0) {
      final sm = RegExp(r'\d+').firstMatch(g[r][sessCol]);
      final v = int.tryParse(sm?.group(0) ?? '');
      if (v != null && v > 0) sess = v;
    }
    recs.add(_ImportLongRec(
        name, rollCol >= 0 ? g[r][rollCol] : '', d, sess, st));
  }
  if (recs.isEmpty) return null;

  String keyOf(_ImportLongRec x) =>
      '${DateFormat('yyyy-MM-dd').format(x.date)}|${x.sess.toString().padLeft(4, '0')}';
  final keyRec = <String, _ImportLongRec>{};
  for (final x in recs) {
    keyRec.putIfAbsent(keyOf(x), () => x);
  }
  final sortedKeys = keyRec.keys.toList()..sort();
  final colId = <String, int>{};
  final columns = <ImportColumn>[];
  for (var i = 0; i < sortedKeys.length; i++) {
    final x = keyRec[sortedKeys[i]]!;
    colId[sortedKeys[i]] = i;
    columns.add(ImportColumn(i, x.date, x.sess));
  }

  final byName = <String, ImportRow>{};
  for (final x in recs) {
    final nk = _normImportName(x.name);
    final row =
        byName.putIfAbsent(nk, () => ImportRow(x.name, x.roll, <int, String>{}));
    row.status[colId[keyOf(x)]!] = x.status;
  }
  return _ImportDraft(columns, byName.values.toList());
}

ImportSheet? parseAttendanceSheet(List<List<String>> rows) {
  if (rows.isEmpty) return null;
  final grid = _importPad(rows);
  if (grid.isEmpty || grid[0].isEmpty) return null;
  _importDayFirst = _inferDayFirst(grid);
  final candidates = <_ImportDraft?>[
    _importParseWide(grid),
    _importParseWide(_importTranspose(grid)),
    _importParseLong(grid),
  ];
  _ImportDraft? best;
  for (final d in candidates) {
    if (d == null) continue;
    if (best == null || d.score > best.score) best = d;
  }
  if (best == null || best.rows.isEmpty || best.columns.isEmpty) return null;
  return ImportSheet(best.columns, best.rows);
}

String _normImportName(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _sortedImportName(String s) {
  final t = _normImportName(s).split(' ')..sort();
  return t.join(' ');
}

// Match file names to the app's students. Only sure matches count (full name,
// the same words in a different order, or the roll number). Everything else is
// shown to the user.
Map<int, String> autoMatchImportRows(
    List<ImportRow> rows, List<Map<String, String>> students) {
  final result = <int, String>{};
  final taken = <String>{};

  void pass(bool Function(ImportRow row, Map<String, String> s) same) {
    for (var i = 0; i < rows.length; i++) {
      if (result.containsKey(i)) continue;
      for (final s in students) {
        final key = s['roll']!;
        if (taken.contains(key)) continue;
        if (same(rows[i], s)) {
          result[i] = key;
          taken.add(key);
          break;
        }
      }
    }
  }

  pass((r, s) => _normImportName(r.name) == _normImportName(s['name'] ?? ''));
  pass((r, s) =>
      _sortedImportName(r.name) == _sortedImportName(s['name'] ?? ''));
  pass((r, s) =>
      r.roll.isNotEmpty && r.roll.trim() == rollOf(s['roll']!).trim());
  return result;
}

// Pick a file and parse it. Returns null on error (a snackbar is shown).
Future<ImportSheet?> pickAttendanceSheetFromFile(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'csv'],
    );
  } catch (e) {
    debugPrint('File picker error: $e');
    if (!context.mounted) return null;
    _importSnack(context, 'Could not open the file picker.');
    return null;
  }
  if (f == null) return null;

  Uint8List? bytes;
  try {
    bytes = await f.readAsBytes();
  } catch (_) {}
  if (bytes == null) {
    if (!context.mounted) return null;
    _importSnack(context, 'Could not read the selected file.');
    return null;
  }

  final ext = (f.extension ?? f.name.split('.').last).toLowerCase();
  ImportSheet? sheet;
  var anyGrid = false;
  try {
    final isZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (ext == 'xlsx' || ext == 'xlsm' || isZip) {
      var bestScore = 0;
      for (final g in _allXlsxGrids(bytes, forAttendance: true)) {
        anyGrid = true;
        final sh = parseAttendanceSheet(g);
        if (sh == null) continue;
        var sc = 0;
        for (final r in sh.rows) {
          sc += r.status.length;
        }
        if (sc > bestScore) {
          bestScore = sc;
          sheet = sh;
        }
      }
    } else {
      final g = _parseCsvText(utf8.decode(bytes, allowMalformed: true));
      anyGrid = g.isNotEmpty;
      sheet = parseAttendanceSheet(g);
    }
  } catch (e) {
    debugPrint('Attendance import parse error: $e');
    if (!context.mounted) return null;
    _importSnack(context, 'Could not read this file: $e');
    return null;
  }

  if (!anyGrid) {
    if (!context.mounted) return null;
    _importSnack(context,
        'Could not read this file. Please use .xlsx or .csv (old .xls is not supported - open it and Save As .xlsx).');
    return null;
  }

  if (sheet == null) {
    if (!context.mounted) return null;
    _importSnack(context,
        'No attendance found. The file needs a row of dates on top and student names on the left with P / A under each date.');
    return null;
  }
  return sheet;
}

// Review screen: shows what will be imported and which names did not match. The
// user can link an unmatched name to a student, or skip it.
class ImportReviewScreen extends StatefulWidget {
  final ImportSheet sheet;
  final List<Map<String, String>> students;
  final Set<String> existingIds;
  final bool canOverwrite;
  const ImportReviewScreen({
    super.key,
    required this.sheet,
    required this.students,
    required this.existingIds,
    required this.canOverwrite,
  });

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late final Map<int, String> _map;
  late final Set<int> _autoRows;
  late final Set<int> _cols;
  bool _blankPresent = true;

  bool _locked(ImportColumn c) =>
      widget.existingIds.contains(c.docId) && !widget.canOverwrite;

  @override
  void initState() {
    super.initState();
    _map = autoMatchImportRows(widget.sheet.rows, widget.students);
    _autoRows = _map.keys.toSet();
    _cols = {
      for (final c in widget.sheet.columns)
        if (!_locked(c)) c.col
    };
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.sheet.rows;
    final unmatched = [
      for (var i = 0; i < rows.length; i++)
        if (!_autoRows.contains(i)) i
    ];
    final noRow =
        widget.students.where((s) => !_map.containsValue(s['roll'])).length;
    final overwriteCount = widget.sheet.columns
        .where((c) => _cols.contains(c.col) && widget.existingIds.contains(c.docId))
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Import attendance')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _cols.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      ImportPlan(Map<int, String>.from(_map),
                          Set<int>.from(_cols), _blankPresent)),
              child: Text(
                'Import ${_cols.length} date${_cols.length == 1 ? '' : 's'}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.sheet.columns.length} dates • ${rows.length} names in file',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_map.length} matched'
                  '${noRow > 0 ? ' • $noRow students of this subject have no row in the file' : ''}',
                  style: const TextStyle(color: kMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Empty cells count as',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Present')),
                    ButtonSegment(value: false, label: Text('Absent')),
                  ],
                  selected: {_blankPresent},
                  onSelectionChanged: (s) =>
                      setState(() => _blankPresent = s.first),
                ),
              ],
            ),
          ),
          if (unmatched.isNotEmpty) ...[
            InfoBanner(
              text:
                  '${unmatched.length} name${unmatched.length == 1 ? '' : 's'} could not be matched. Choose the right student for each, or skip it.',
              icon: Icons.person_search_outlined,
            ),
            for (final i in unmatched)
              AppCard(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rows[i].name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    DropdownButton<String?>(
                      isExpanded: true,
                      value: _map[i],
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Skip (not matched)')),
                        for (final s in widget.students)
                          if (s['roll'] == _map[i] ||
                              !_map.containsValue(s['roll']))
                            DropdownMenuItem<String?>(
                              value: s['roll'],
                              child: Text(
                                '${rollOf(s['roll']!)} • ${s['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: (v) => setState(() {
                        if (v == null) {
                          _map.remove(i);
                        } else {
                          _map[i] = v;
                        }
                      }),
                    ),
                  ],
                ),
              ),
          ],
          if (overwriteCount > 0)
            InfoBanner(
              text:
                  '$overwriteCount of the selected dates already have attendance. Importing will replace it.',
              icon: Icons.warning_amber_rounded,
              color: kAbsent,
            ),
          if (widget.sheet.columns.any(_locked))
            const InfoBanner(
              text:
                  'Dates that already have attendance are locked for teachers. Only an admin can replace them.',
              icon: Icons.lock_outline,
            ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text('Dates (${_cols.length} selected)',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                children: [
                  for (final c in widget.sheet.columns)
                    CheckboxListTile(
                      dense: true,
                      value: _cols.contains(c.col),
                      onChanged: _locked(c)
                          ? null
                          : (v) => setState(() {
                                if (v == true) {
                                  _cols.add(c.col);
                                } else {
                                  _cols.remove(c.col);
                                }
                              }),
                      title: Text(
                          '${DateFormat('dd MMM yyyy').format(c.date)} • Session ${c.session}'),
                      subtitle: widget.existingIds.contains(c.docId)
                          ? Text(
                              _locked(c)
                                  ? 'Already taken (locked)'
                                  : 'Already taken (will be replaced)',
                              style: const TextStyle(
                                  color: kMuted, fontSize: 12))
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Subject attendance screen
// Admin: no restrictions. Teacher: with the master switch OFF, only today's
// date, only in the first 20 minutes of each hour, and only a new record,
// unless the admin allows each ability in Detailed permissions (any time,
// change time, change date, edit, delete). With the master switch ON,
// everything is open. Each subject has its own screen.
class SubjectAttendanceScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  final DateTime? initialDate;
  final int? initialSession;
  const SubjectAttendanceScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
    this.initialDate,
    this.initialSession,
  });

  @override
  State<SubjectAttendanceScreen> createState() => _SubjectAttendanceScreenState();
}

class _SubjectAttendanceScreenState extends State<SubjectAttendanceScreen> {
  late DateTime selectedDate;
  late int selectedSession;
  Map<String, String> attendanceStatus = {};
  List<Map<String, String>> students = [];
  Map<String, double> studentPercentage = {};
  bool isLoading = true;
  bool copiedFromPreviousSession = false;

  bool existingRecord = false;
  String? timeStr; // 'HH:mm'
  Map<String, String> existingMeta = {};

  // All records of this subject, loaded once (one read), then used for the
  // selected date, copying the previous session, and the percentages.
  List<DateRecord> _records = [];

  TeacherPerms perms = TeacherPerms.none;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permSub;
  Timer? _ticker;
  bool _lastWindowState = true;

  CollectionReference<Map<String, dynamic>> get _datesRef =>
      widget.sem.dates(widget.subjectName);

  bool get _isAdmin => AppSession.isAdmin;
  // Full access: admin, or a teacher while the master switch is ON.
  bool get _unrestricted => _isAdmin || perms.master;
  bool get _canChangeTime => _unrestricted || perms.changeTime;
  bool get _canChangeDate => _unrestricted || perms.changeDate;
  bool get _canEditExisting => _unrestricted || perms.edit;
  bool get _canDeleteRec => _unrestricted || perms.delete;
  bool get _isToday {
    final n = DateTime.now();
    return selectedDate.year == n.year &&
        selectedDate.month == n.month &&
        selectedDate.day == n.day;
  }

  bool get _inWindow => DateTime.now().minute < kMarkWindowMinutes;
  bool get _canEdit {
    if (_unrestricted) return true;
    if (existingRecord) return perms.edit;
    return (_isToday || perms.changeDate) && (_inWindow || perms.anytime);
  }

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate ?? DateTime.now();
    selectedSession = widget.initialSession ?? 1;

    _permSub = permissionsRef().snapshots().listen((s) {
      final p = TeacherPerms.from(s.data());
      if (mounted && p != perms) setState(() => perms = p);
    }, onError: (_) {});

    // Update the screen when the window opens or closes
    _lastWindowState = _inWindow;
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _isAdmin) return;
      final now = _inWindow;
      if (now != _lastWindowState) {
        _lastWindowState = now;
        setState(() {});
      }
    });

    _loadAll();
  }

  @override
  void dispose() {
    _permSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _getDocumentId([int? session]) {
    String dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    return "${dateStr}_Session_${session ?? selectedSession}";
  }

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    try {
      final studentsF = loadSubjectStudents(widget.sem, widget.subjectName);
      final recordsF = loadDateRecords(widget.sem, widget.subjectName);
      students = await studentsF;
      _records = await recordsF;
      _fetchAttendanceForDate();
      _computePercentages();
    } catch (e) {
      debugPrint('Attendance load error: $e');
    }
    // Always stop the spinner, even if something above failed.
    if (mounted) setState(() => isLoading = false);

    if (copiedFromPreviousSession && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSnack(context,
            'Attendance copied from the previous session. Change if needed and tap Save.');
      });
    }
  }

  DateRecord? _recordById(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  // Uses the already loaded records: instant, no network.
  void _fetchAttendanceForDate() {
    copiedFromPreviousSession = false;
    existingRecord = false;
    existingMeta = {};
    timeStr = null;

    final cur = _recordById(_getDocumentId());
    if (cur != null) {
      attendanceStatus = Map<String, String>.from(cur.status);
      existingRecord = true;
      existingMeta = Map<String, String>.from(cur.meta);
      timeStr = cur.meta['_time'];
      return;
    }

    timeStr = hhmm(TimeOfDay.now());

    for (int s = selectedSession - 1; s >= 1; s--) {
      final prev = _recordById(_getDocumentId(s));
      if (prev != null) {
        attendanceStatus = Map<String, String>.from(prev.status);
        copiedFromPreviousSession = true;
        return;
      }
    }

    attendanceStatus = {for (var s in students) s['roll']!: "P"};
  }

  void _computePercentages() {
    final total = _records.length;
    final counts = <String, int>{};
    for (final r in _records) {
      r.status.forEach((roll, st) {
        if (st == 'P') counts[roll] = (counts[roll] ?? 0) + 1;
      });
    }
    final Map<String, double> result = {};
    for (final s in students) {
      final roll = s['roll']!;
      result[roll] = total > 0 ? ((counts[roll] ?? 0) / total) * 100 : 100.0;
    }
    studentPercentage = result;
  }

  Future<void> _afterDateOrSessionChange() async {
    _fetchAttendanceForDate();
    if (mounted) setState(() {});
    if (copiedFromPreviousSession && mounted) {
      showSnack(context, 'Attendance copied from the previous session.');
    }
  }

  void _openMonthly() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonthlyAttendanceScreen(
          sem: widget.sem,
          semLabel: widget.semLabel,
          subjectName: widget.subjectName,
        ),
      ),
    );
  }

  void _saveAttendance() async {
    // Check the rules again when saving (the window may have closed meanwhile)
    if (!_canEdit) {
      showSnack(
          context,
          existingRecord
              ? 'You do not have permission to edit this record. Ask the admin.'
              : (!_isToday && !perms.changeDate)
                  ? 'You can only mark attendance for today.'
                  : 'Attendance can only be marked within the first $kMarkWindowMinutes minutes of each hour.',
          color: kAbsent);
      return;
    }

    final docId = _getDocumentId();

    final data = <String, dynamic>{
      for (final s in students) s['roll']!: attendanceStatus[s['roll']!] ?? 'P',
    };

    // Time: an admin (or a teacher allowed to change the time, or when the
    // master switch is ON) can pick their own time. Otherwise a new record
    // gets the current time and an edited record keeps its old time.
    String? time = _canChangeTime
        ? timeStr
        : (existingRecord ? timeStr : hhmm(TimeOfDay.now()));
    if (time == null && !existingRecord) time = hhmm(TimeOfDay.now());
    if (time != null) data['_time'] = time;

    // Who marked it: if an admin edits a teacher's record, the original
    // teacher's name stays.
    String byId = AppSession.userId;
    String byName = AppSession.userName;
    if (_isAdmin && (existingMeta['_marked_by'] ?? '').isNotEmpty) {
      byId = existingMeta['_marked_by']!;
      byName = existingMeta['_marked_by_name'] ?? byName;
    }
    data['_marked_by'] = byId;
    data['_marked_by_name'] = byName;

    final status = <String, String>{
      for (final s in students) s['roll']!: attendanceStatus[s['roll']!] ?? 'P',
    };

    // Not awaited: this never completes while offline.
    unawaited(_datesRef.doc(docId).set(data).catchError((_) {}));
    unawaited(LocalDb.saveAttendance(
      widget.sem,
      widget.subjectName,
      docId,
      status,
      time: time,
      markedBy: byId,
      markedByName: byName,
    ));

    final newMeta = <String, String>{
      '_time': ?time,
      '_marked_by': byId,
      '_marked_by_name': byName,
    };
    final rec = DateRecord(docId, Map<String, String>.from(status),
        Map<String, String>.from(newMeta));

    setState(() {
      final idx = _records.indexWhere((r) => r.id == docId);
      if (idx >= 0) {
        _records[idx] = rec;
      } else {
        _records.add(rec);
        _records.sort((a, b) => a.id.compareTo(b.id));
      }
      existingRecord = true;
      timeStr = time;
      existingMeta = newMeta;
      _computePercentages();
    });

    if (mounted) {
      showSnack(context, 'Attendance Saved/Updated for Session $selectedSession!');
    }
  }

  void _deleteAttendance() async {
    if (!_canDeleteRec) return;
    final docId = _getDocumentId();
    unawaited(_datesRef.doc(docId).delete().catchError((_) {}));
    unawaited(LocalDb.deleteAttendance(widget.sem, widget.subjectName, docId));

    setState(() {
      _records.removeWhere((r) => r.id == docId);
      attendanceStatus = {for (var s in students) s['roll']!: "P"};
      existingRecord = false;
      existingMeta = {};
      timeStr = hhmm(TimeOfDay.now());
      _computePercentages();
    });

    if (mounted) {
      showSnack(context, 'Attendance record for Session $selectedSession deleted!',
          color: kAbsent);
    }
  }

  // ---- Import old attendance from Excel / CSV ----
  // For both admin and teacher. This is old-date data, so the time window and
  // "today only" rules do not apply. But an existing session record can be
  // changed only by the admin (or when the master switch is ON).
  Future<void> _importFromFile() async {
    if (students.isEmpty) {
      showSnack(context, 'Add students to this subject first.', color: kAbsent);
      return;
    }
    final sheet = await pickAttendanceSheetFromFile(context);
    if (sheet == null || !mounted) return;

    final plan = await Navigator.push<ImportPlan>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportReviewScreen(
          sheet: sheet,
          students: students,
          existingIds: _records.map((r) => r.id).toSet(),
          canOverwrite: _canEditExisting,
        ),
      ),
    );
    if (plan == null || !mounted) return;
    await _applyImport(sheet, plan);
  }

  Future<void> _applyImport(ImportSheet sheet, ImportPlan plan) async {
    final fallback = plan.blankPresent ? 'P' : 'A';
    var imported = 0;
    var skipped = 0;

    for (final col in sheet.columns) {
      if (!plan.cols.contains(col.col)) continue;
      final docId = col.docId;
      final old = _recordById(docId);
      if (old != null && !_canEditExisting) {
        skipped++;
        continue;
      }

      final status = <String, String>{
        for (final s in students) s['roll']!: fallback,
      };
      plan.rowToStudent.forEach((rowIdx, key) {
        final st = sheet.rows[rowIdx].status[col.col];
        if (st != null && status.containsKey(key)) status[key] = st;
      });

      final time = old?.meta['_time'];
      final byId = AppSession.userId;
      final byName = AppSession.userName;
      final data = <String, dynamic>{
        ...status,
        '_time': ?time,
        '_marked_by': byId,
        '_marked_by_name': byName,
      };

      // Not awaited: this never completes while offline.
      unawaited(_datesRef.doc(docId).set(data).catchError((_) {}));
      await LocalDb.saveAttendance(
        widget.sem,
        widget.subjectName,
        docId,
        status,
        time: time,
        markedBy: byId,
        markedByName: byName,
      );

      final newMeta = <String, String>{
        '_time': ?time,
        '_marked_by': byId,
        '_marked_by_name': byName,
      };
      final rec = DateRecord(docId, Map<String, String>.from(status), newMeta);
      final idx = _records.indexWhere((r) => r.id == docId);
      if (idx >= 0) {
        _records[idx] = rec;
      } else {
        _records.add(rec);
      }
      imported++;
    }

    _records.sort((a, b) => a.id.compareTo(b.id));
    _fetchAttendanceForDate();
    _computePercentages();
    if (!mounted) return;
    setState(() {});
    showSnack(
      context,
      imported == 0
          ? 'Nothing was imported.'
          : 'Imported $imported date${imported == 1 ? '' : 's'}.'
              '${skipped > 0 ? ' $skipped skipped (already taken, admin only).' : ''}',
      color: imported == 0 ? kAbsent : kPresent,
    );
  }

  void _exportToExcel() async {
    final recs = await loadDateRecords(widget.sem, widget.subjectName);
    final fileBytes = buildAttendanceExcelBytes(
      info: await loadExcelInfo(widget.sem, widget.subjectName),
      recs: recs,
      students: students,
    );
    if (kIsWeb) {
      final safeName =
          widget.subjectName.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
      downloadBytes(fileBytes!, '${safeName}_Full_Report.xlsx');
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    String filePath = "${directory.path}/${widget.subjectName}_Full_Report.xlsx";

    File(filePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes!);

    await SharePlus.instance.share(ShareParams(
      files: [XFile(filePath)],
      text: '${widget.subjectName} Attendance Report',
    ));
  }

  Widget _restrictionBanner() {
    if (_unrestricted) return const SizedBox.shrink();
    if (existingRecord) {
      if (perms.edit) return const SizedBox.shrink();
      return const InfoBanner(
        text: 'Attendance for this session has already been taken. You do not have permission to edit it. Ask the admin.',
        icon: Icons.lock_outline,
      );
    }
    if (!_isToday && !perms.changeDate) {
      return const InfoBanner(
        text: 'Aap sirf aaj ki date ki attendance le sakte hain.',
        icon: Icons.lock_outline,
      );
    }
    if (perms.anytime) return const SizedBox.shrink();
    if (!_inWindow) {
      return InfoBanner(
        text:
            'Attendance can only be taken within the first $kMarkWindowMinutes minutes of each hour (e.g. 10:00-10:$kMarkWindowMinutes). The next window opens at ${DateFormat('hh:00 a').format(DateTime.now().add(const Duration(hours: 1)))}.',
        icon: Icons.schedule,
      );
    }
    final left = kMarkWindowMinutes - DateTime.now().minute;
    return InfoBanner(
      text: 'Attendance window is open — $left minutes remaining.',
      icon: Icons.timer_outlined,
      color: kPresent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subjectName),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: 'Students of this subject',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubjectStudentsScreen(
                      sem: widget.sem, subjectName: widget.subjectName),
                ),
              ).then((_) => _loadAll());
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubjectStatsScreen(
                      sem: widget.sem, subjectName: widget.subjectName),
                ),
              );
            },
            tooltip: 'Subject History & Stats',
          ),
          if (_canEditExisting || _canDeleteRec)
            IconButton(
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManageAttendanceScreen(
                      sem: widget.sem,
                      semLabel: widget.semLabel,
                      subjectName: widget.subjectName,
                    ),
                  ),
                );
              },
              tooltip: 'Edit / Delete Past Records',
            ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _importFromFile,
            tooltip: 'Import old attendance (Excel / CSV)',
          ),
          IconButton(
            icon: const Icon(Icons.download_sharp),
            onPressed: _exportToExcel,
            tooltip: 'Export Excel',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${widget.sem.deptId} • Section ${widget.sem.section} • ${widget.semLabel}',
                      style: const TextStyle(color: kMuted, fontSize: 12.5),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openMonthly,
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: const Text('Monthly attendance'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAccent,
                        side: const BorderSide(color: kOutline),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                _restrictionBanner(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Date: ${DateFormat('dd MMM yyyy').format(selectedDate)}",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          if (_canChangeDate)
                            ElevatedButton.icon(
                              onPressed: () async {
                                DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  selectedDate = picked;
                                  await _afterDateOrSessionChange();
                                }
                              },
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: const Text('Change Date'),
                            ),
                        ],
                      ),
                      if (_canChangeTime) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Time: ${timeStr == null ? '—' : fmtHhmm(timeStr)}",
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked =
                                    await pickClassTime(context, parseHhmm(timeStr));
                                if (picked != null) {
                                  setState(() => timeStr = hhmm(picked));
                                }
                              },
                              icon: const Icon(Icons.access_time, size: 16),
                              label: const Text('Change Time'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Lecture / Session:",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          DropdownButton<int>(
                            value: selectedSession,
                            items: List.generate(5, (index) => index + 1)
                                .map((val) => DropdownMenuItem(
                                      value: val,
                                      child: Text("Session $val"),
                                    ))
                                .toList(),
                            onChanged: (newVal) async {
                              if (newVal != null) {
                                selectedSession = newVal;
                                await _afterDateOrSessionChange();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: kOutline),
                if (students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        const Text('Mark all:',
                            style: TextStyle(color: kMuted, fontSize: 13)),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: canEdit
                              ? () => setState(() {
                                    for (final st in students) {
                                      attendanceStatus[st['roll']!] = 'A';
                                    }
                                  })
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kAbsent,
                            side: BorderSide(
                                color: canEdit ? kAbsent : kOutline),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('All Absent'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: canEdit
                              ? () => setState(() {
                                    for (final st in students) {
                                      attendanceStatus[st['roll']!] = 'P';
                                    }
                                  })
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kPresent,
                            side: BorderSide(
                                color: canEdit ? kPresent : kOutline),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('All Present'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: students.isEmpty
                      ? const EmptyState(
                          icon: Icons.groups_outlined,
                          text: 'There are no students in this subject yet.\nAdmin can add them from Manage Students.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 6),
                          itemCount: students.length,
                          itemBuilder: (context, index) {
                            var student = students[index];
                            String roll = student['roll']!;
                            double? pct = studentPercentage[roll];
                            bool isLow = pct != null && pct < 75;

                            return RepaintBoundary(
                                child: AppCard(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                              child: Row(
                                children: [
                                  RollBadge(roll: roll),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          student['name']!,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: isLow ? kAbsent : null,
                                          ),
                                        ),
                                        if (pct != null)
                                          Text('${pct.toStringAsFixed(1)}% attendance',
                                              style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: isLow ? kAbsent : kMuted)),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AttendanceChip(
                                        label: 'P',
                                        selected:
                                            (attendanceStatus[roll] ?? 'P') ==
                                                'P',
                                        color: kPresent,
                                        onTap: canEdit
                                            ? () => setState(() =>
                                                attendanceStatus[roll] = 'P')
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      AttendanceChip(
                                        label: 'A',
                                        selected:
                                            (attendanceStatus[roll] ?? 'P') ==
                                                'A',
                                        color: kAbsent,
                                        onTap: canEdit
                                            ? () => setState(() =>
                                                attendanceStatus[roll] = 'A')
                                            : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ));
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      if (_canDeleteRec) ...[
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAbsent,
                                foregroundColor: kOnAccent,
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Attendance?'),
                                    content: Text('Are you sure you want to delete the attendance for Session $selectedSession?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteAttendance();
                                        },
                                        child: const Text('Delete', style: TextStyle(color: kAbsent)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: const Icon(Icons.delete),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: canEdit ? _saveAttendance : null,
                            child: Text(
                              existingRecord ? 'Save / Update' : 'Save Attendance',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
    );
  }
}

// Manage attendance screen (edit / delete old records)
// Admin, or a teacher who was given the Edit and/or Delete permission (or when
// the master switch is ON). The Edit and Delete buttons follow those permissions.
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: permissionsRef().snapshots(),
      builder: (context, permSnap) {
        final perms = TeacherPerms.from(permSnap.data?.data());
        final full = AppSession.isAdmin || perms.master;
        return _buildRecords(context, full || perms.edit, full || perms.delete);
      },
    );
  }

  Widget _buildRecords(BuildContext context, bool canEdit, bool canDelete) {
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
            return const EmptyState(
                icon: Icons.event_busy, text: 'No attendance records found.');
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
              try {
                List<String> parts = docId.split('_Session_');
                parsedDate = DateFormat('yyyy-MM-dd').parse(parts[0]);
                parsedSession = int.parse(parts[1]);
                label = "${DateFormat('dd MMM yyyy').format(parsedDate)} - Session $parsedSession";
              } catch (e) {
                label = docId;
              }

              final parsed = parseAttendance(doc.data());
              int presentCount = parsed.status.values.where((v) => v == 'P').length;
              int absentCount = parsed.status.values.where((v) => v == 'A').length;
              final time = fmtHhmm(parsed.meta['_time']);
              final by = parsed.meta['_marked_by_name'] ?? '';

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
                          Text(label,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
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
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: kAbsent),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(context, docId, label),
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

// Student status card (shared by Subject Stats and Monthly Attendance, for
// admin and teacher). Compact and centered. All text sits in a Column /
// Expanded cell so nothing can overflow the card.
class StatEntry {
  final String label;
  final bool present;
  const StatEntry(this.label, this.present);
}

// '2026-10-01_Session_2' -> '01 Oct · S2'
String prettySession(String id) {
  try {
    final parts = id.split('_Session_');
    final d = DateFormat('yyyy-MM-dd').parse(parts[0]);
    return '${DateFormat('dd MMM').format(d)} · S${parts[1]}';
  } catch (_) {
    return id;
  }
}

class StudentStatCard extends StatefulWidget {
  final String roll;
  final String name;
  final int present;
  final int absent;
  final int total;
  final List<StatEntry> entries;
  const StudentStatCard({
    super.key,
    required this.roll,
    required this.name,
    required this.present,
    required this.absent,
    required this.total,
    required this.entries,
  });

  @override
  State<StudentStatCard> createState() => _StudentStatCardState();
}

class _StudentStatCardState extends State<StudentStatCard> {
  bool _open = false;

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 1),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted, fontSize: 11.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final pct = w.total > 0 ? (w.present / w.total) * 100 : 0.0;
    final good = pct >= 75;
    final color = good ? kPresent : kAbsent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: kGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGlassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: w.entries.isEmpty ? null : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  w.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: good ? null : kAbsent,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Roll No. ${rollOf(w.roll)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 5,
                    backgroundColor: kOutline,
                    color: color,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _stat('${w.present}', 'Present', kPresent),
                    Container(width: 1, height: 26, color: kOutline),
                    _stat('${w.absent}', 'Absent', kAbsent),
                    Container(width: 1, height: 26, color: kOutline),
                    _stat('${w.total}', 'Sessions', Colors.white70),
                  ],
                ),
                if (w.entries.isNotEmpty)
                  Icon(
                    _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: kMuted,
                    size: 20,
                  ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in w.entries)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (e.present ? kPresent : kAbsent)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${e.label} · ${e.present ? 'P' : 'A'}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: e.present ? kPresent : kAbsent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

StudentStatCard buildStudentStatCard(
    Map<String, String> student, List<DateRecord> records,
    {Key? key}) {
  final roll = student['roll']!;
  int present = 0;
  int absent = 0;
  final entries = <StatEntry>[];
  for (final r in records) {
    final st = r.status[roll];
    if (st == 'P') {
      present++;
      entries.add(StatEntry(prettySession(r.id), true));
    } else if (st == 'A') {
      absent++;
      entries.add(StatEntry(prettySession(r.id), false));
    }
  }
  return StudentStatCard(
    key: key ?? ValueKey(roll),
    roll: roll,
    name: student['name'] ?? '',
    present: present,
    absent: absent,
    total: records.length,
    entries: entries,
  );
}

// Subject stats screen (overall, for admin and teacher)
class SubjectStatsScreen extends StatefulWidget {
  final SemRef sem;
  final String subjectName;
  const SubjectStatsScreen({super.key, required this.sem, required this.subjectName});

  @override
  State<SubjectStatsScreen> createState() => _SubjectStatsScreenState();
}

class _SubjectStatsScreenState extends State<SubjectStatsScreen> {
  bool _loading = true;
  List<Map<String, String>> _students = [];
  List<DateRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final studentsF = loadSubjectStudents(widget.sem, widget.subjectName);
      final recordsF = loadDateRecords(widget.sem, widget.subjectName);
      _students = await studentsF;
      _records = await recordsF;
    } catch (e) {
      debugPrint('Stats load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.subjectName} - Stats')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const EmptyState(
                  icon: Icons.insights_outlined,
                  text: 'No attendance records found.')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 6, bottom: 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: Text(
                          '${_records.length} session${_records.length == 1 ? '' : 's'} recorded',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kMuted, fontSize: 13),
                        ),
                      ),
                      for (final st in _students)
                        buildStudentStatCard(st, _records),
                    ],
                  ),
                ),
    );
  }
}

// Monthly attendance (admin and teacher): pick a month and see only that
// month's attendance of this subject. It is read from the local SQLite database
// (works offline) and refreshed first when online.
class MonthlyAttendanceScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  const MonthlyAttendanceScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
  });

  @override
  State<MonthlyAttendanceScreen> createState() =>
      _MonthlyAttendanceScreenState();
}

class _MonthlyAttendanceScreenState extends State<MonthlyAttendanceScreen> {
  late DateTime _month; // always the 1st of the month
  bool _loading = true;
  bool _syncing = false;
  List<Map<String, String>> _students = [];
  List<DateRecord> _records = [];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _init();
  }

  Future<void> _init() async {
    try {
      _students = await loadSubjectStudents(widget.sem, widget.subjectName);
    } catch (e) {
      debugPrint('Monthly students load error: $e');
    }
    await _loadMonth();
    unawaited(_refreshFromServer());
  }

  Future<void> _loadMonth({bool spinner = true}) async {
    final month = _month;
    if (spinner && mounted) setState(() => _loading = true);
    final prefix = DateFormat('yyyy-MM').format(month);
    final recs = await LocalDb.dateRecords(widget.sem, widget.subjectName,
        monthPrefix: prefix);
    if (!mounted || month != _month) return;
    setState(() {
      _records = recs;
      _loading = false;
    });
  }

  // Online: pull this subject's latest records into SQLite, then redraw.
  Future<void> _refreshFromServer() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    final ok = await LocalDb.refreshSubjectAttendance(
        widget.sem, widget.subjectName);
    if (ok) await _loadMonth(spinner: false);
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _setMonth(DateTime m) async {
    _month = DateTime(m.year, m.month);
    await _loadMonth();
  }

  Future<void> _pickMonth() async {
    int month = _month.month;
    int year = _month.year.clamp(2020, 2030).toInt();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Select month'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: month,
                items: [
                  for (int m = 1; m <= 12; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(DateFormat('MMMM').format(DateTime(2000, m))),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => month = v);
                },
              ),
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: year,
                items: [
                  for (int y = 2020; y <= 2030; y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => year = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, DateTime(year, month)),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) await _setMonth(picked);
  }

  // ---- Excel export of the selected month (admin and teacher, every subject)
  // ----
  bool _exporting = false;

  Future<void> _exportExcel() async {
    if (_exporting || _records.isEmpty || _students.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final recs = List<DateRecord>.from(_records)
        ..sort((a, b) => a.id.compareTo(b.id));

      final bytes = buildAttendanceExcelBytes(
        info: await loadExcelInfo(widget.sem, widget.subjectName),
        recs: recs,
        students: _students,
      );
      if (bytes == null) throw Exception('Excel file could not be created');

      final safeSubject =
          widget.subjectName.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
      final monthKey = DateFormat('yyyy-MM').format(_month);
      if (kIsWeb) {
        downloadBytes(bytes, '${safeSubject}_${monthKey}_Monthly_Report.xlsx');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${safeSubject}_${monthKey}_Monthly_Report.xlsx';
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        text:
            '${widget.subjectName} - ${DateFormat('MMMM yyyy').format(_month)} Attendance',
      ));
    } catch (e) {
      debugPrint('Monthly Excel export error: $e');
      if (mounted) {
        showSnack(context, 'Could not create Excel file: $e', color: kAbsent);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildList() {
    if (_students.isEmpty) {
      return const EmptyState(
          icon: Icons.groups_outlined, text: 'No students in this subject.');
    }
    double sum = 0;
    for (final s in _students) {
      final roll = s['roll']!;
      final p = _records.where((r) => r.status[roll] == 'P').length;
      sum += (p / _records.length) * 100;
    }
    final avg = sum / _students.length;
    final monthKey = DateFormat('yyyy-MM').format(_month);

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            '${_records.length} session${_records.length == 1 ? '' : 's'} • average ${avg.toStringAsFixed(1)}%',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 13),
          ),
        ),
        for (final s in _students)
          buildStudentStatCard(s, _records,
              key: ValueKey('$monthKey-${s['roll']}')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_month);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subjectName} - Monthly'),
        actions: [
          IconButton(
            tooltip: 'Download month as Excel',
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            onPressed: (_records.isEmpty || _exporting) ? null : _exportExcel,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                  onPressed: () =>
                      _setMonth(DateTime(_month.year, _month.month - 1)),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickMonth,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(monthLabel,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, color: kAccent),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                  onPressed: () =>
                      _setMonth(DateTime(_month.year, _month.month + 1)),
                ),
              ],
            ),
          ),
          if (_syncing)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? EmptyState(
                        icon: Icons.event_busy,
                        text: 'No attendance recorded in $monthLabel.')
                    : _buildList(),
          ),
        ],
      ),
    );f
  }
}
