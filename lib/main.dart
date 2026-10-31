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
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random, cos, sin;
import 'dart:ui' show ImageFilter;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart' as zip;
import 'package:mobile_scanner/mobile_scanner.dart' as scanner;
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'download_stub.dart'
    if (dart.library.js_interop) 'download_web.dart';
part 'theme_widgets.dart';
part 'auth_screens.dart';
part 'student_screens.dart';
part 'student_logins.dart';
part 'services.dart';
part 'excel_export.dart';
part 'local_db.dart';
part 'browse_screens.dart';
part 'students_manage.dart';
part 'attendance_import.dart';
part 'attendance_take.dart';
part 'stats_screens.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF08203A),
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

  // Keep a local copy of the data. Offline changes sync when back online.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await sessionReady;
  if (AppSession.kind == 'teacher' ||
      AppSession.kind == 'hidden' ||
      AppSession.kind == 'student') {
    unawaited(AppSession.ensureSignedIn());
  }
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

// Allows creating new admins from the Admin Login screen. Off, because teachers
// also sign up in this app. Create admins in the Firebase console.
const bool kAllowAdminSignUp = false;

// ---- Second (hidden) admin ----
// The username and password are NOT stored in the code or in Firebase, only
// a SHA-256 hash of 'sam|username|password' (so nobody can read them from the
// web files). To change them, compute the hash of the new 'sam|user|pass'.
const String kHiddenAdminDeptName = 'Information Technology';
const String kHiddenAdminHash =
    'f03f5a24ec11db894580dddbacab1c7ad267a803efe6b73df14fc600825328bc';

const List<int> _kSha256K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

// Small SHA-256 (works on Android, iOS and web builds, no extra package).
String _sha256Hex(String input) {
  const m = 0xFFFFFFFF;
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & m;
  final data = utf8.encode(input);
  final bitLen = data.length * 8;
  final bytes = <int>[...data, 0x80];
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    bytes.add((bitLen >> (i * 8)) & 0xFF);
  }
  var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
  final w = List<int>.filled(64, 0);
  for (var off = 0; off < bytes.length; off += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = (bytes[off + i * 4] << 24) |
          (bytes[off + i * 4 + 1] << 16) |
          (bytes[off + i * 4 + 2] << 8) |
          bytes[off + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & m;
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & m) & g);
      final t1 = (h + s1 + ch + _kSha256K[i] + w[i]) & m;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & m;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & m;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & m;
    }
    h0 = (h0 + a) & m;
    h1 = (h1 + b) & m;
    h2 = (h2 + c) & m;
    h3 = (h3 + d) & m;
    h4 = (h4 + e) & m;
    h5 = (h5 + f) & m;
    h6 = (h6 + g) & m;
    h7 = (h7 + h) & m;
  }
  return [h0, h1, h2, h3, h4, h5, h6, h7]
      .map((x) => x.toRadixString(16).padLeft(8, '0'))
      .join();
}

const String kSoftwareEngineeringDeptId = "Software Engineering";

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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _AuroraTransitions(_NoTransitions()),
            TargetPlatform.iOS: _AuroraTransitions(_NoTransitions()),
            TargetPlatform.macOS: _AuroraTransitions(_NoTransitions()),
            TargetPlatform.windows: _AuroraTransitions(_NoTransitions()),
            TargetPlatform.linux: _AuroraTransitions(_NoTransitions()),
            TargetPlatform.fuchsia: _AuroraTransitions(_NoTransitions()),
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
            shadows: kGlowText,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAccent,
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
            side: const BorderSide(color: kAccentLine),
            shape: pillShape,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kAccent),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kAccent,
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
          hintStyle: const TextStyle(color: Color(0x99FFFFFF)),
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
