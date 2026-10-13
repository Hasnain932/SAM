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
import 'platform/download_stub.dart'
    if (dart.library.html) 'platform/download_web.dart';

// All the files below are part of this one library, so they can share
// everything (even private names that start with _).
part 'core/constants.dart';
part 'widgets/aurora_background.dart';
part 'core/page_transitions.dart';
part 'app.dart';
part 'widgets/common_widgets.dart';
part 'services/app_session.dart';
part 'screens/auth/root_gate.dart';
part 'screens/auth/welcome_screen.dart';
part 'screens/auth/admin_login_screen.dart';
part 'screens/auth/teacher_auth_screen.dart';
part 'screens/auth/teacher_requests_screen.dart';
part 'data/seed_data.dart';
part 'models/sem_ref.dart';
part 'models/teacher_perms.dart';
part 'services/legacy_paths.dart';
part 'services/offline_reads.dart';
part 'models/attendance_models.dart';
part 'utils/time_helpers.dart';
part 'services/xlsx_writer.dart';
part 'services/excel_export.dart';
part 'services/student_loaders.dart';
part 'models/date_record.dart';
part 'services/subject_claims.dart';
part 'services/firestore_delete.dart';
part 'services/rename_service.dart';
part 'services/backup_service.dart';
part 'services/migration_service.dart';
part 'services/local_db.dart';
part 'screens/departments_screen.dart';
part 'screens/sections_screen.dart';
part 'screens/semesters_screen.dart';
part 'screens/subjects_screen.dart';
part 'widgets/sem_label_text.dart';
part 'screens/teacher_home_screen.dart';
part 'utils/student_file_import.dart';
part 'screens/manage_students_screen.dart';
part 'screens/subject_students_screen.dart';
part 'widgets/class_time_picker.dart';
part 'models/import_models.dart';
part 'utils/import_date_parser.dart';
part 'services/xlsx_fallback_reader.dart';
part 'services/attendance_sheet_parser.dart';
part 'screens/import_review_screen.dart';
part 'screens/subject_attendance_screen.dart';
part 'screens/manage_attendance_screen.dart';
part 'widgets/student_stat_card.dart';
part 'screens/subject_stats_screen.dart';
part 'screens/monthly_attendance_screen.dart';

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

  // Keep a local copy of the data. Offline changes sync when back online.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await sessionReady;
  runApp(const AttendanceApp());
}
