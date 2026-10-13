part of '../main.dart';

// Colors, limits and other app-wide settings.

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
// Stored like a normal department and found only by username.
const String kHiddenAdminDeptName = 'Information Technology';
const String kHiddenAdminUsername = 'BUDDY';
const String kHiddenAdminPassword = 'buddy11';

const String kSoftwareEngineeringDeptId = "Software Engineering";

// Theme: deep navy-to-teal gradient, frosted glass cards, white pill buttons.
// Green = present, red = absent.
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
