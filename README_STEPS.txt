HOW TO USE THE NEW FILES (step by step)
=======================================

WHAT CHANGED
- Your big main.dart (9,843 lines) is now 48 small files + a short main.dart.
- No code was rewritten. Every line was moved, not changed.
- The two download files moved into lib/platform/.

STEP 1 - BACK UP
1. Copy your whole project folder somewhere safe (example: attendance_app_BACKUP).

STEP 2 - REMOVE THE OLD FILES
Inside your project, open the "lib" folder and delete these 3 files:
  - main.dart
  - download_stub.dart
  - download_web.dart

STEP 3 - ADD THE NEW FILES
1. Unzip attendance_lib.zip.
2. Open the unzipped "lib" folder.
3. Copy EVERYTHING inside it (main.dart, app.dart and all the folders)
   into your project's "lib" folder.
4. Your lib folder should now look like the map below.

STEP 4 - RUN
1. Run:  flutter pub get
2. Run the app (Android) and the web build like you always do.
3. Do NOT change pubspec.yaml. Nothing there needs to change.

IF YOU SEE AN ERROR
- Copy the red message and send it to me. Do not try to fix it by hand.
- Fast way back: put your backup folder back. Nothing is lost.

THE FOLDER MAP
lib/
  main.dart                  imports, the list of files, and main()
  app.dart                   the app widget (theme + first screen)
  platform/                  download_stub.dart, download_web.dart
  core/                      constants.dart (colors, limits), page_transitions.dart
  data/                      seed_data.dart
  models/                    sem_ref, teacher_perms, date_record, import_models, attendance_models
  utils/                     time_helpers, student_file_import, import_date_parser
  widgets/                   small reusable widgets (cards, time picker, stat card ...)
  services/                  everything that talks to Firestore / SQLite / Excel
  screens/                   one file per screen (auth/ has the login screens)

WHERE TO CHANGE THINGS LATER
- Colors, 20-minute window, 6 AM-6 PM range -> core/constants.dart
- Login / sign up screens                   -> screens/auth/
- Marking attendance                        -> screens/subject_attendance_screen.dart
- Excel export look                         -> services/excel_export.dart, services/xlsx_writer.dart
- Import old attendance                     -> services/attendance_sheet_parser.dart, screens/import_review_screen.dart
- Local SQLite database                     -> services/local_db.dart
- Backup / restore                          -> services/backup_service.dart
- Teacher permissions                       -> models/teacher_perms.dart

HOW TO ADD A NEW FILE LATER (important rule)
1. Create the file, for example lib/screens/my_new_screen.dart
2. First line of that file:   part of '../main.dart';
   (for a file inside screens/auth/ use:  part of '../../main.dart';
    for a file directly in lib/ use:      part of 'main.dart';)
3. Do NOT write "import" lines in that file. Put new imports in main.dart.
4. Add one line to main.dart with the others:   part 'screens/my_new_screen.dart';

WHY IT WORKS THIS WAY
All files are "parts" of main.dart, so they share everything, even private
names that start with "_". That is why nothing breaks.

SECURITY NOTE
core/constants.dart has the hidden admin password in plain text. Anyone can
read it from the web version. Better to move it out of the code later.

COMMENTS
Your comments were already in English, so I kept them as they are.
