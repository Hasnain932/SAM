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
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart' as zip;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'download_stub.dart'
    if (dart.library.js_interop) 'download_web.dart';

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
// Stored like a normal department and found only by username.
const String kHiddenAdminDeptName = 'Information Technology';
const String kHiddenAdminUsername = 'BUDDY';
const String kHiddenAdminPassword = 'buddy11';

const String kSoftwareEngineeringDeptId = "Software Engineering";

// Theme: deep navy gradient, glass cards, blue glow buttons.
// Blue = present / selected, red = absent.
const Color kBgTop = Color(0xFF1B1166);
const Color kBgMid = Color(0xFF0B1240);
const Color kBgBottom = Color(0xFF08203A);
const Color kBg = kBgMid;
const Color kSurface = Color(0xFF111A4A); // solid navy: dialogs, menus
const Color kSurfaceHi = Color(0xFF1A2560);
const Color kGlass = Color(0x1AFFFFFF); // glass card fill (10% white)
const Color kGlassBorder = Color(0x663B6BF0); // glass card border (soft blue)
const Color kAccentLine = Color(0xFF3B6BF0); // outline of unselected chips
const Color kOutline = Color(0x33FFFFFF);
const Color kAccent = Color(0xFF14B8E6); // cyan blue: icons, highlights
const Color kOnAccent = Colors.white; // text on blue buttons
const Color kButton = Color(0xFF2563EB); // primary pill buttons
const Color kPresent = Color(0xFF14B8E6);
const Color kAccent2 = Color(0xFF2563EB); // royal blue
const Color kViolet = Color(0xFF8B7CF6);
const Color kAbsent = Color(0xFFFF8FA0);
const Color kMuted = Color(0xFFB4C3DC);
const Color kAbsent2 = Color(0xFFE5365F);
const Color kLabelBlue = Color(0xFF8FD8FF); // light blue for labels
// Soft, light glow (was strong: alpha AA, blur 10). Used on titles and labels.
const List<Shadow> kGlowText = [Shadow(color: Color(0x2614B8E6), blurRadius: 3)];
// Names of departments, sections, semesters and subjects: same soft glow.
const TextStyle kNameStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Color(0xFFEAF6FF),
    shadows: kGlowText);
const TextStyle kLabelStyle = TextStyle(
    color: kLabelBlue, fontSize: 13, fontWeight: FontWeight.w600, shadows: kGlowText);
const LinearGradient kBlueGrad = LinearGradient(colors: [kAccent, kAccent2]);
// Diagonal gradient used on icon tiles (same as the department building boxes).
const LinearGradient kTileGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kAccent, kAccent2],
);
const LinearGradient kTileRedGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFF7A93), kAbsent2],
);
const LinearGradient kRedGrad =
    LinearGradient(colors: [Color(0xFFFF7A93), kAbsent2]);
// Card fill: soft blue gradient (same family as the P button).
const LinearGradient kCardGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1F3C9E), Color(0xFF0C5F95)],
);

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

// Inner pages open instantly (no page animation, so no delay on tap).
class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

// Soft fade used only for the Admin / Teacher login pages.
Route<T> _fadeRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => AuroraBackground(child: builder(context)),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

// Each route paints its own gradient so the previous page doesn't show through.
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
// Gentle up/down float (professional, subtle).
class Floaty extends StatefulWidget {
  final Widget child;
  final double dy;
  final int ms;
  final double phase;
  const Floaty({
    super.key,
    required this.child,
    this.dy = 3,
    this.ms = 3400,
    this.phase = 0,
  });

  @override
  State<Floaty> createState() => _FloatyState();
}

class _FloatyState extends State<Floaty> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.ms),
  );

  @override
  void initState() {
    super.initState();
    _c.value = widget.phase.clamp(0.0, 1.0);
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Transform.translate(
            offset: Offset(0, (t - 0.5) * 2 * widget.dy),
            child: child,
          );
        },
      ),
    );
  }
}

class AppCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double blur;
  final bool float; // soft floating + fade-in; off everywhere except where asked
  final Color? borderColor; // optional custom border (e.g. low attendance)
  final bool subtle; // plain dark fill instead of the blue gradient (long lists)
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    this.radius = 20,
    this.blur = 10,
    this.float = false,
    this.borderColor,
    this.subtle = false,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  static int _count = 0;
  late final double _phase = ((_count++) * 0.17) % 1.0; // wave pattern

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    final card = Material(
      color: widget.subtle ? const Color(0xFF16215F) : kGlass,
      child: InkWell(
        onTap: widget.onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: widget.borderColor ?? kGlassBorder),
          ),
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
    final body = Padding(
      padding: widget.margin,
      child: ClipRRect(
        borderRadius: r,
        // Web: no blur (a BackdropFilter per card is slow, and barely visible here).
        child: kIsWeb
            ? card
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
                child: card,
              ),
      ),
    );
    if (!widget.float || MediaQuery.of(context).disableAnimations) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
      ),
      child: Floaty(phase: _phase, dy: 2.5, child: body),
    );
  }
}

// Pill button with the blue (or red) gradient. filled = selected look.
class GradPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final LinearGradient gradient;
  final bool filled;
  final bool enabled;
  final bool expand;
  final double? height;
  final double radius;
  final double fontSize;
  const GradPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.gradient = kBlueGrad,
    this.filled = true,
    this.enabled = true,
    this.expand = false,
    this.height,
    this.radius = 999,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final red = gradient == kRedGrad;
    final fg = filled ? Colors.white : (red ? kAbsent : kAccent);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: fontSize, fontWeight: FontWeight.w700)),
        ),
      ],
    );
    final r = BorderRadius.circular(radius);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: filled ? gradient : null,
          borderRadius: r,
          border: filled
              ? null
              : Border.all(color: red ? kAbsent : kAccentLine, width: 1.2),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: gradient.colors.last.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 14, vertical: height == null ? 9 : 0),
              child: height != null ? Center(child: content) : content,
            ),
          ),
        ),
      ),
    );
  }
}

// Blue gradient pill button (login screens).
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kAccent, kAccent2]),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: kAccent.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: onPressed,
            child: Center(
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          color: kOnAccent, strokeWidth: 2),
                    )
                  : Text(label,
                      style: const TextStyle(
                          color: kOnAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}

// Labelled glass text field (login screens).
class AuthField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  const AuthField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label.toUpperCase(),
              style: const TextStyle(
                  color: kMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          decoration: InputDecoration(
            hintText: hint,
            fillColor: const Color(0x4D0A0F2E),
            prefixIcon: Icon(icon, color: kAccent, size: 20),
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: kMuted,
                        size: 20),
                  ),
          ),
        ),
      ],
    );
  }
}

// Shared look of the Admin / Teacher login pages.
class AuthShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  const AuthShell({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        children: [
          Floaty(dy: 4, child: IconBadge(icon: icon, size: 88)),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted, fontSize: 14)),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: kGlass,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: kGlassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          const SizedBox(height: 22),
          const Text('SAM  ·  SMART ATTENDANCE',
              style: TextStyle(color: kMuted, fontSize: 11, letterSpacing: 3)),
        ],
      ),
    );
    // One-time soft fade + rise when the page opens (same feel as the main page).
    final animated = MediaQuery.of(context).disableAnimations
        ? content
        : TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                  offset: Offset(0, (1 - v) * 18), child: child),
            ),
            child: content,
          );
    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _BrandRingsPainter()),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: animated,
            ),
          ),
        ],
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
          duration: Duration.zero,
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: selected
                ? (color == kAbsent
                    ? kRedGrad
                    : (color == kPresent ? kBlueGrad : null))
                : null,
            color: selected && color != kPresent && color != kAbsent
                ? color
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: (color == kAbsent ? kAbsent2 : kAccent2)
                          .withValues(alpha: 0.14),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
            border: Border.all(
              color: selected
                  ? (color == kAbsent
                      ? kAbsent2
                      : (color == kPresent ? kAccent2 : color))
                  : kAccentLine,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
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
    final big = size >= 60;
    final isAccent = color == kAccent;
    // Flat gradient tile with a white icon (same look as the HF avatar and the
    // bookmark button), no glow. Other colors (e.g. a taken subject) stay muted.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: isAccent
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kAccent, kAccent2],
              )
            : null,
        color: isAccent ? null : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(big ? size * 0.3 : 12),
        boxShadow: big && isAccent
            ? [
                BoxShadow(
                  color: kAccent2.withValues(alpha: 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(icon,
          color: isAccent ? kOnAccent : color, size: size * 0.5),
    );
  }
}

// Small blue label chip (used in the permissions dialog).
class _PermChip extends StatelessWidget {
  final String text;
  const _PermChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: kAccent, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// Floating add button: same gradient rounded-square look as the icon tiles.
class GradFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const GradFab({super.key, this.icon = Icons.add, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(18);
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: kTileGrad,
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: kAccent2.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onPressed,
          child: Center(child: Icon(icon, color: Colors.white, size: 28)),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  // Optional button under the text (e.g. jump to marking attendance).
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// App bar action with a soft colored background, so similar icons
// (e.g. Import vs Export) are easy to tell apart.
class TintedIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;
  const TintedIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconButton(
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

// ---- Header card (dark rounded bar used on the redesigned screens) ----
// Square tile with an icon, used inside HeaderCard. Colors stay the app's own.
class HeaderTile extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final bool tile; // false = plain icon without the tile background
  final bool dot; // small red dot (e.g. pending requests)
  const HeaderTile({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = kAccent,
    this.tile = true,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    final isBlue = color == kAccent;
    final isRed = color == kAbsent;
    final r = BorderRadius.circular(12);
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Ink(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: tile && (isBlue || isRed)
                    ? (isRed ? kTileRedGrad : kTileGrad)
                    : null,
                color: tile && !(isBlue || isRed)
                    ? color.withValues(alpha: 0.18)
                    : null,
                borderRadius: r,
              ),
              child: InkWell(
                borderRadius: r,
                onTap: onTap,
                child: Center(
                    child: Icon(icon,
                        color: tile && (isBlue || isRed) ? Colors.white : color,
                        size: 20)),
              ),
            ),
            if (dot)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                    color: kAbsent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// One cell of the icon + label row under a HeaderCard title.
class HeaderAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const HeaderAction({required this.icon, required this.label, this.onTap});
}

class HeaderCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions; // small tiles on the right of the title
  final List<HeaderAction> tabs; // icon + label row under the title
  const HeaderCard({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.tabs = const [],
  });

  @override
  Widget build(BuildContext context) {
    final canBack = Navigator.of(context).canPop();
    final tileRow = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) tileRow.add(const SizedBox(width: 6));
      tileRow.add(actions[i]);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kBgTop,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kGlassBorder),
        boxShadow: [
          BoxShadow(
            color: kAccent2.withValues(alpha: 0.08),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (canBack)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkResponse(
                    radius: 22,
                    onTap: () => Navigator.maybePop(context),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEAF6FF),
                          shadows: kGlowText,
                        ),
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: kLabelBlue,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              if (tileRow.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...tileRow,
              ],
            ],
          ),
          if (tabs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kGlassBorder),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++) ...[
                    if (i > 0)
                      Container(width: 1, height: 34, color: kOutline),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: tabs[i].onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 9, horizontal: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: kTileGrad,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(tabs[i].icon,
                                    color: Colors.white, size: 19),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  tabs[i].label,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: kLabelBlue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Same header bar as the Departments screen, for the inner screens.
PreferredSizeWidget headerAppBar({
  required String title,
  String? subtitle,
  List<Widget> actions = const [],
}) {
  return AppBar(
    automaticallyImplyLeading: false,
    titleSpacing: 0,
    toolbarHeight: subtitle == null ? 84 : 102,
    title: HeaderCard(title: title, subtitle: subtitle, actions: actions),
  );
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

  Widget _studentRow(String name, Color c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 11, backgroundColor: c),
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

  Widget _bar(double h, Color c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(4),
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
                  _studentRow('Hasnain', kViolet),
                  _studentRow('Awais', kAccent),
                  _studentRow('Fahad', const Color(0xFFE879F9)),
                ],
              ),
              radius: 24,
            ),
          ),
        ),
        const SizedBox(width: 10),
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
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              colors: [kViolet, kAccent2]),
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
              const SizedBox(height: 10),
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
                            _bar(22, const Color(0x33FFFFFF)),
                            _bar(36, const Color(0x40FFFFFF)),
                            _bar(30, const Color(0x40FFFFFF)),
                            _bar(54, kAccent2),
                            _bar(46, kAccent),
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
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _BrandRingsPainter()),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const IconBadge(
                              icon: Icons.school_rounded, size: 40),
                          const SizedBox(width: 12),
                          const Text('SAM',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 6)),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _hero(),
                      const SizedBox(height: 14),
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
                              horizontal: 14, vertical: 8),
                          radius: 20,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text('Attendance,',
                          style: TextStyle(
                              fontSize: 34,
                              height: 1.1,
                              fontWeight: FontWeight.w800)),
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                                colors: [kAccent, kViolet])
                            .createShader(r),
                        child: const Text('done in seconds.',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                height: 1.1,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                          'Smart, fast and reliable. Mark, track and export for your whole university.',
                          style: TextStyle(color: kMuted, fontSize: 14)),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: GradPill(
                          label: 'Admin Login',
                          onTap: openAdmin,
                          expand: true,
                          height: 54,
                          radius: 18,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton(
                          onPressed: openTeacher,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                          ),
                          child: const Text('Teacher Login',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: openTeacher,
                          child: Text.rich(
                            TextSpan(
                              text: 'New teacher? ',
                              style: const TextStyle(
                                  color: kMuted,
                                  fontWeight: FontWeight.w400),
                              children: const [
                                TextSpan(
                                  text: 'Create account',
                                  style: TextStyle(
                                      color: kAccent,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(Icons.bolt_outlined, 'Quick marking'),
                          _chip(Icons.description_outlined, 'Excel export'),
                          _chip(Icons.cloud_off_outlined, 'Offline'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
    return AuthShell(
      icon: Icons.admin_panel_settings_outlined,
      title: _isLogin ? 'Admin Login' : 'Create Admin Account',
      subtitle: 'Secure access to your dashboard',
      children: [
        AuthField(
          label: 'Email or username',
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
          setState(() => _error = 'Account not found. Please sign up first.');
          return;
        }
        final data = snap.data() ?? {};
        if ((data['password'] ?? '').toString() != password) {
          setState(() => _error = 'Incorrect username or password');
          return;
        }
        // Approval is checked only at login. After approval, the saved local session
        // is used and the server is never asked again. Accounts with no status
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
          child: Text(_isLogin
              ? "New teacher? Sign up"
              : "Already have an account? Login"),
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
// kPermMaster ON: teachers can do everything. OFF: each permission below applies
// on its own. A missing field means "not allowed".
const String kPermMaster = 'teachers_unrestricted';
const String kPermAnytime = 'perm_anytime'; // mark outside the 20-minute window
const String kPermChangeTime = 'perm_change_time'; // pick the class time
const String kPermChangeDate = 'perm_change_date'; // pick other / past dates
// Edit also covers deleting records. Class <-> Lab and Mid <-> Final conversion
// are always allowed (admin and teachers), so they have no permission.
const String kPermEdit = 'perm_edit'; // edit AND delete existing records
const List<String> kDetailedPerms = [
  kPermAnytime,
  kPermChangeTime,
  kPermChangeDate,
  kPermEdit,
];

class TeacherPerms {
  final bool master;
  final bool anytime;
  final bool changeTime;
  final bool changeDate;
  final bool edit; // edit and delete existing records
  const TeacherPerms({
    this.master = false,
    this.anytime = false,
    this.changeTime = false,
    this.changeDate = false,
    this.edit = false,
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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TeacherPerms &&
      other.master == master &&
      other.anytime == anytime &&
      other.changeTime == changeTime &&
      other.changeDate == changeDate &&
      other.edit == edit;

  @override
  int get hashCode =>
      Object.hash(master, anytime, changeTime, changeDate, edit);
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
// Web: don't make screens wait for the server. After this time, show the cache
// (the server read keeps running and refreshes it).
const Duration _kReadTimeout =
    kIsWeb ? Duration(milliseconds: 900) : _kNetworkTimeout;

// Wi-Fi connected doesn't always mean the internet works. _netState() adds a quick
// DNS check (cached for a few seconds). When offline, go straight to the cache
// instead of waiting for a timeout, which caused endless loading.
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
  // InternetAddress.lookup isn't available on web; the check above is enough.
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
    // Nothing cached: wait a bit longer for the server instead of showing an empty list.
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

// ---- Reliable writes ----
// saved  = server confirmed the write (online)
// queued = offline or slow: Firestore keeps it on the device and sends it later
// failed = server refused it (for example Firestore rules)
enum SaveResult { saved, queued, failed }

Future<SaveResult> fsWrite(Future<void> write, {String what = 'write'}) async {
  write.ignore(); // errors are handled below, never left unhandled
  final net = await _netState();
  if (net != _Net.reachable) {
    unawaited(write.then((_) {},
        onError: (Object e) => debugPrint('Firestore $what error: $e')));
    return SaveResult.queued;
  }
  try {
    await write.timeout(const Duration(seconds: 10));
    return SaveResult.saved;
  } on TimeoutException {
    debugPrint('Firestore $what: slow, still sending in the background');
    return SaveResult.queued;
  } catch (e) {
    debugPrint('Firestore $what error: $e');
    return SaveResult.failed;
  }
}

Future<SaveResult> fsWriteAll(List<Future<void>> writes,
    {String what = 'write'}) {
  if (writes.isEmpty) return Future.value(SaveResult.saved);
  return fsWrite(Future.wait(writes).then((_) {}), what: what);
}

// After a student write: when the server confirmed it, refresh the SQLite copy
// from the server right away; when it failed, tell the user.
Future<void> finishStudentWrite(
    BuildContext? context, SemRef sem, SaveResult res,
    {String? subject}) async {
  if (res == SaveResult.saved) {
    await LocalDb.refreshSemesterStudents(sem);
    if (subject != null) await LocalDb.refreshSubjectOverrides(sem, subject);
  } else if (res == SaveResult.failed && context != null && context.mounted) {
    showSnack(context,
        'Could not save to the server. Check Firestore rules and try again.',
        color: kAbsent);
  }
}

// Cache-first live query for StreamBuilders: device cache first, then live updates.
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
          // Empty cache: give the live stream a moment, then show the empty result.
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
// _time (HH:mm), _marked_by, _marked_by_name, _type ('class' / 'lab').
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
// Both exports use this layout: info section (Program, Semester, Instructor,
// Course, Section, Marks), three header rows (Week, Date, Class No.), then students.
// Attendance is 1 (present) / 0 (absent). Totals, Percentage and Marks are formulas.

// Default attendance marks. Only the starting value of the "Marks" cell; the
// formulas read that cell, so it can be changed per course in Excel.
const double kDefaultAttendanceMarks = 5;

// Info section details. Nothing is hardcoded; all values come from the export.
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
// The excel package dropped styles and merges on some builds, so the sheet is
// written directly as xlsx XML. Styles, merges, widths and heights are exact.
class _XlsxBuilder {
  final List<String> _fonts = [
    '<font><sz val="11"/><name val="Arial"/><family val="2"/></font>'
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
  int freezeRows = 7; // rows kept on top while scrolling (header rows)
  int freezeCols = 3; // Roll No, Name, Father Name stay while scrolling sideways

  // Print setup. buildAttendanceExcelBytes decides these automatically.
  bool portrait = false;
  bool onePage = true; // true: whole sheet fitted on one page
  int printScale = 100; // used only when onePage is false
  final List<int> colBreaks = []; // 0-based columns where a new page starts
  String printTitles = ''; // rows / columns repeated on every printed page

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
    bool shrink = false,
  }) {
    final fontId = _idx(
        _fonts,
        '<font>${bold ? '<b/>' : ''}<sz val="$size"/>'
        '<color rgb="$font"/><name val="Arial"/><family val="2"/></font>');
    final fillId = bg == null
        ? 0
        : _idx(
            _fills,
            '<fill><patternFill patternType="solid"><fgColor rgb="$bg"/>'
            '<bgColor indexed="64"/></patternFill></fill>');
    final bStyle = border ? (thick ? 'medium' : 'thin') : null;
    final bColor = thick ? 'FF1F3864' : 'FFB4C0D8';
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
        '${wrap ? ' wrapText="1"' : ''}${shrink ? ' shrinkToFit="1"' : ''}/></xf>');
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
        '<sheetPr><pageSetUpPr fitToPage="${onePage ? 1 : 0}"/></sheetPr>'
        '<sheetViews><sheetView showGridLines="0" workbookViewId="0" tabSelected="1">'
        '<pane xSplit="$freezeCols" ySplit="$freezeRows" topLeftCell="${_excelColLetters(freezeCols)}${freezeRows + 1}" activePane="bottomRight" state="frozen"/>'
        '</sheetView></sheetViews>'
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
    // Print: A4, centered. Either the whole sheet on ONE page, or several
    // pages at a fixed readable scale (see the layout decision below).
    final orient = portrait ? 'portrait' : 'landscape';
    sb.write('<printOptions horizontalCentered="1"/>'
        '<pageMargins left="0.25" right="0.25" top="0.4" bottom="0.5" '
        'header="0.3" footer="0.3"/>');
    if (onePage) {
      sb.write('<pageSetup paperSize="9" orientation="$orient" '
          'fitToWidth="1" fitToHeight="1"/>');
    } else {
      sb.write('<pageSetup paperSize="9" scale="$printScale" '
          'pageOrder="overThenDown" orientation="$orient"/>');
    }
    sb.write('<headerFooter><oddFooter>&amp;CPage &amp;P of &amp;N</oddFooter></headerFooter>');
    if (colBreaks.isNotEmpty) {
      sb.write('<colBreaks count="${colBreaks.length}" '
          'manualBreakCount="${colBreaks.length}">'
          '${colBreaks.map((c) => '<brk id="$c" max="1048575" man="1"/>').join()}'
          '</colBreaks>');
    }
    sb.write('</worksheet>');

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
    final definedNames = printTitles.isEmpty
        ? ''
        : '<definedNames><definedName name="_xlnm.Print_Titles" '
            'localSheetId="0">$printTitles</definedName></definedNames>';
    final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
        '$definedNames'
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

// What goes into the Excel file and how attendance is written.
class ExportOptions {
  final String scope; // 'all' (Class + Lab Class), kTypeClass or kTypeLab
  final bool useLetters; // true: P / A letters, false: 1 / 0 digits
  final String phase; // 'all' (Overall), kPhaseMid or kPhaseFinal
  const ExportOptions(this.scope, this.useLetters, [this.phase = 'all']);
}

// Sessions that belong in the file for the chosen scope (Class/Lab) and
// exam phase (Overall / Mid / Final). Both filters combine.
List<DateRecord> filterRecordsByScope(List<DateRecord> recs, String scope,
    {String phase = 'all'}) {
  var out = List<DateRecord>.from(recs);
  if (phase == kPhaseFinal) out = out.where((r) => r.isFinal).toList();
  if (phase == kPhaseMid) out = out.where((r) => r.isMid).toList();
  if (scope == kTypeLab) return out.where((r) => r.isLab).toList();
  if (scope == kTypeClass) return out.where((r) => !r.isLab).toList();
  return out;
}

// Text for "No ... sessions" messages, e.g. "Mid", "Final Lab Class".
String optionsLabel(ExportOptions o) {
  final ph = o.phase == 'all' ? '' : phaseLabel(o.phase);
  final sc = (o.scope == 'all' && o.phase != 'all') ? '' : scopeLabel(o.scope);
  return [ph, sc].where((e) => e.isNotEmpty).join(' ');
}

// Part of the file name for the phase ('' for Overall).
String phaseFileTag(String phase) =>
    phase == kPhaseFinal ? 'Final_' : (phase == kPhaseMid ? 'Mid_' : '');

String scopeLabel(String scope) => scope == kTypeLab
    ? 'Lab Class'
    : scope == kTypeClass
        ? 'Class'
        : 'Class + Lab Class';

// Part of the file name for the scope ('' for combined).
String scopeFileTag(String scope) =>
    scope == kTypeLab ? 'Lab_' : (scope == kTypeClass ? 'Class_' : '');

// File name start: Subject_Section_A_Semester_3
String exportFileBase(SemRef sem, String semLabel, String subject) {
  String clean(String v) => v
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return [
    clean(subject),
    'Section_${clean(sem.section)}',
    clean(semLabel),
  ].where((e) => e.isNotEmpty).join('_');
}

// One dialog for both exports (overall and monthly): what to include
// (Class + Lab Class / Class only / Lab Class only), which exam phase
// (Overall / Mid / Final) and the P/A format.
Future<ExportOptions?> askExportOptions(
    BuildContext context, List<DateRecord> recs) {
  var scope = 'all';
  var phase = 'all';
  var letters = true;
  final midCount = recs.where((r) => r.isMid).length;
  final finalCount = recs.length - midCount;

  return showDialog<ExportOptions>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Widget choice(String title, String sub, bool selected, VoidCallback? onTap) {
          return ListTile(
            dense: true,
            enabled: onTap != null,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: onTap == null ? kOutline : kAccent,
            ),
            title: Text(title),
            subtitle: sub.isEmpty ? null : Text(sub),
            onTap: onTap,
          );
        }

        // Class / Lab counts follow the chosen phase.
        final inPhase = filterRecordsByScope(recs, 'all', phase: phase);
        final classCount = inPhase.where((r) => !r.isLab).length;
        final labCount = inPhase.length - classCount;

        String n(int c) => '$c session${c == 1 ? '' : 's'}';
        return AlertDialog(
          title: const Text('Export Excel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Include',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
                choice('Class + Lab Class (combined)', n(inPhase.length),
                    scope == 'all', () => setS(() => scope = 'all')),
                choice('Class only', n(classCount), scope == kTypeClass,
                    classCount == 0 ? null : () => setS(() => scope = kTypeClass)),
                choice('Lab Class only', n(labCount), scope == kTypeLab,
                    labCount == 0 ? null : () => setS(() => scope = kTypeLab)),
                const Divider(),
                const Text('Exam phase',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
                choice('Overall (Mid + Final)', n(recs.length), phase == 'all',
                    () => setS(() => phase = 'all')),
                choice('Mid', n(midCount), phase == kPhaseMid,
                    midCount == 0 ? null : () => setS(() => phase = kPhaseMid)),
                choice('Final', n(finalCount), phase == kPhaseFinal,
                    finalCount == 0
                        ? null
                        : () => setS(() => phase = kPhaseFinal)),
                const Divider(),
                const Text('Format',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
                choice('P / A   (Present / Absent)', '', letters,
                    () => setS(() => letters = true)),
                choice('1 / 0   (1 = Present, 0 = Absent)', '', !letters,
                    () => setS(() => letters = false)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, ExportOptions(scope, letters, phase)),
              child: const Text('Export'),
            ),
          ],
        );
      },
    ),
  );
}

// Asks which format the Excel file should use.
// true = P / A letters, false = 1 / 0 digits, null = cancelled.
Future<bool?> askExportFormat(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Export format'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('P / A   (Present / Absent)'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('1 / 0   (1 = Present, 0 = Absent)'),
        ),
      ],
    ),
  );
}

List<int>? buildAttendanceExcelBytes({
  required ExcelInfo info,
  required List<DateRecord> recs,
  required List<Map<String, String>> students,
  bool useLetters = false, // true: P / A letters, false: 1 / 0 digits
}) {
  final records = List<DateRecord>.from(recs)
    ..sort((a, b) => a.id.compareTo(b.id));
  final x = _XlsxBuilder();

  // ---- Colour theme (Navy Gold) ----
  const navy = 'FF1F3864';
  const head = 'FF2F4F8F';
  const gold = 'FFC9A227';
  const infoBg = 'FFEAF0FA';
  const bandA = 'FFFFFFFF';
  const bandB = 'FFF3F6FB';
  const green = 'FF1B7F3B';
  const red = 'FFD92D20';
  final titleStyle = x.style(size: 20, font: 'FFFFFFFF', bg: navy, thick: true);
  final fillerStyle = x.style(border: false);
  final infoLabelStyle =
      x.style(size: 12, font: 'FFFFFFFF', bg: navy, thick: true);
  final infoValueStyle = x.style(size: 12, font: navy, bg: infoBg, thick: true);
  final idHeadStyle =
      x.style(size: 12, font: 'FFFFFFFF', bg: head, wrap: true, thick: true);
  final totalHeadStyle =
      x.style(size: 10, font: navy, bg: gold, wrap: true, thick: true);
  final presentHeadStyle = totalHeadStyle;
  final pctHeadStyle = totalHeadStyle;
  final marksHeadStyle = totalHeadStyle;
  // Small "Lab" label above lab session columns.
  final labStyle = x.style(size: 9, font: navy, bg: gold);

  // Normal cells (two alternating row backgrounds). Bold 12 pt so the
  // printed text stays easy to read.
  const int bodySize = 12;
  final cellStyle = x.style(size: bodySize, bg: bandA);
  final cellStyleAlt = x.style(size: bodySize, bg: bandB);
  final nameStyle =
      x.style(size: bodySize, left: true, bg: bandA, shrink: true);
  final nameStyleAlt =
      x.style(size: bodySize, left: true, bg: bandB, shrink: true);
  final totalCellStyle = cellStyle;
  final totalCellStyleAlt = cellStyleAlt;
  final totalPresentStyle = cellStyle;
  final totalPresentStyleAlt = cellStyleAlt;
  final marksCellStyle = cellStyle;
  final marksCellStyleAlt = cellStyleAlt;

  // Present (P / 1) = green text, Absent (A / 0) = red text. Text colour
  // only, no coloured cell background. Colours are written straight into
  // each cell (no conditional formatting), so WPS / mobile viewers show them.
  final goodStyle = x.style(size: bodySize, font: green, bg: bandA);
  final goodStyleAlt = x.style(size: bodySize, font: green, bg: bandB);
  final badStyle = x.style(size: bodySize, font: red, bg: bandA);
  final badStyleAlt = x.style(size: bodySize, font: red, bg: bandB);

  // Header styles for weeks / dates / class numbers.
  final weekHeadStyles = [
    x.style(size: 14, font: 'FFFFFFFF', bg: head, thick: true)
  ];
  final weekDateStyles = [
    x.style(size: 10, font: navy, bg: 'FFD9E2F3', wrap: true)
  ];
  final weekSerialStyles = [
    x.style(size: 9, font: navy, bg: 'FFE9EFF9', bold: false)
  ];

  // ---- Columns ----
  const int firstSessionCol = 3; // 0 Roll No, 1 Name, 2 Father Name
  final n = records.length;
  final totalClassesCol = firstSessionCol + n;
  final presentCol = totalClassesCol + 1;
  final pctCol = totalClassesCol + 2;
  final marksCol = totalClassesCol + 3;
  final lastCol = marksCol < 11 ? 11 : marksCol;

  // ---- Rows ----
  // If the file has lab sessions, one extra row sits above the header for the
  // small "Lab" labels. Files without lab sessions keep the old layout.
  final bool hasLab = records.any((r) => r.isLab);
  final int top = hasLab ? 1 : 0;
  const int infoRow0 = 1;
  const int labRow = 4;
  final int weekRow = 4 + top;
  final int dateRow = 5 + top;
  final int serialRow = 6 + top;
  final int firstStudentRow = 7 + top;
  x.freezeRows = firstStudentRow;

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
  x.merge(2, weekRow, 2, serialRow, 'Father Name', idHeadStyle);

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

  // "Lab" label above each lab column; class columns stay empty.
  if (hasLab) {
    for (int i = 0; i < n; i++) {
      if (records[i].isLab) {
        x.text(firstSessionCol + i, labRow, 'Lab', labStyle);
      }
    }
    x.rowHeights[labRow] = 16;
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
  int maxFather = 11;
  for (final st in students) {
    final roll = st['roll'] ?? '';
    final name = st['name'] ?? '';
    final father = st['father'] ?? '';
    if (name.length > maxName) maxName = name.length;
    if (father.length > maxFather) maxFather = father.length;
    int present = 0;
    final alt = (rowIndex - firstStudentRow) % 2 == 1;
    x.text(0, rowIndex, rollOf(roll), alt ? cellStyleAlt : cellStyle);
    x.text(1, rowIndex, name, alt ? nameStyleAlt : nameStyle);
    x.text(2, rowIndex, father, alt ? nameStyleAlt : nameStyle);
    for (int i = 0; i < n; i++) {
      final isP = (records[i].status[roll] ?? 'P') == 'P';
      if (isP) present++;
      final cs = isP
          ? (alt ? goodStyleAlt : goodStyle)
          : (alt ? badStyleAlt : badStyle);
      if (useLetters) {
        x.text(firstSessionCol + i, rowIndex, isP ? 'P' : 'A', cs);
      } else {
        x.number(firstSessionCol + i, rowIndex, isP ? 1 : 0, cs);
      }
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
      x.formula(totalClassesCol, rowIndex,
          useLetters ? 'COUNTA($first:$last)' : 'COUNT($first:$last)', n,
          alt ? totalCellStyleAlt : totalCellStyle);
      x.formula(
          presentCol,
          rowIndex,
          useLetters ? 'COUNTIF($first:$last,"P")' : 'SUM($first:$last)',
          present,
          alt ? totalPresentStyleAlt : totalPresentStyle);
      x.formula(pctCol, rowIndex, 'IF($tcRef=0,0,ROUND($tpRef/$tcRef*100,2))',
          pctRounded,
          pct >= 75
              ? (alt ? goodStyleAlt : goodStyle)
              : (alt ? badStyleAlt : badStyle));
      x.formula(marksCol, rowIndex, 'ROUND($pcRef/100*$marksRef,2)',
          marksCached, alt ? marksCellStyleAlt : marksCellStyle);
    } else {
      x.number(totalClassesCol, rowIndex, 0,
          alt ? totalCellStyleAlt : totalCellStyle);
      x.number(presentCol, rowIndex, 0,
          alt ? totalPresentStyleAlt : totalPresentStyle);
      x.number(pctCol, rowIndex, 0, alt ? badStyleAlt : badStyle);
      x.number(marksCol, rowIndex, 0, alt ? marksCellStyleAlt : marksCellStyle);
    }
    x.rowHeights[rowIndex] = 20;
    rowIndex++;
  }

  // ---- Column widths: narrow session columns, so text can print bigger ----
  x.colWidths[0] = 8;
  x.colWidths[1] = (maxName * 1.2 + 3).clamp(22, 42).toDouble();
  for (int c = 2; c <= lastCol; c++) {
    x.colWidths[c] = 6.5; // all date / info columns equal
  }
  x.colWidths[2] = (maxFather * 1.2 + 3).clamp(16, 38).toDouble();
  x.colWidths[totalClassesCol] = 8;
  x.colWidths[presentCol] = 8;
  x.colWidths[pctCol] = 10;
  x.colWidths[marksCol] = 8;

  // ---- Row heights ----
  x.rowHeights[0] = 30;
  for (int r = infoRow0; r < infoRow0 + 3; r++) {
    x.rowHeights[r] = 22;
  }
  x.rowHeights[weekRow] = 26;
  x.rowHeights[dateRow] = 30; // room for "14\nSep" on two lines
  x.rowHeights[serialRow] = 18;

  // ---- Print layout: decided automatically ----
  // 1) Try the whole sheet on ONE A4 page, portrait and landscape, and keep the
  //    better one. 2) If the text would be smaller than kMinOnePageScale (too
  //    small to read), print on SEVERAL portrait pages instead: Roll No / Name /
  //    Father Name and the header rows repeat on every page, and pages break
  //    between weeks, so the text stays big and clear.
  const double kMinOnePageScale = 0.6;
  const double a4w = 595, a4h = 842; // A4 in points
  const double marginX = 36, marginY = 65; // left+right, top+bottom
  // Default font is Arial 11, whose digit is 8 px wide, so a column of width w
  // is w * 8 px wide (the width value already includes padding).
  double ptWidth(int c) => x.colWidths[c]! * 8 * 0.75;
  double sheetW = 0;
  for (int c = 0; c <= lastCol; c++) {
    sheetW += ptWidth(c);
  }
  double sheetH = 0;
  for (final h in x.rowHeights.values) {
    sheetH += h;
  }
  double smaller(double a, double b) => a < b ? a : b;
  final double scalePortrait =
      smaller((a4w - marginX) / sheetW, (a4h - marginY) / sheetH);
  final double scaleLandscape =
      smaller((a4h - marginX) / sheetW, (a4w - marginY) / sheetH);

  if (smaller(1.0, scalePortrait > scaleLandscape ? scalePortrait : scaleLandscape) >=
      kMinOnePageScale) {
    x.onePage = true;
    x.portrait = scalePortrait >= scaleLandscape;
  } else {
    x.onePage = false;
    x.portrait = true;
    // Scale so all student rows fit one page height (between 60% and 75%).
    double s = (a4h - marginY) / sheetH * 0.98;
    if (s > 0.75) s = 0.75;
    if (s < 0.6) s = 0.6;
    final int pct = (s * 100).floor();
    x.printScale = pct;

    final double availW = (a4w - marginX) / (pct / 100) * 0.95;
    final double fixedW = ptWidth(0) + ptWidth(1) + ptWidth(2);
    final double colW = ptWidth(firstSessionCol);
    final double totalsW = ptWidth(totalClassesCol) +
        ptWidth(presentCol) +
        ptWidth(pctCol) +
        ptWidth(marksCol);
    int perPage = ((availW - fixedW) / colW).floor();
    int perLast = ((availW - fixedW - totalsW) / colW).floor();
    if (perPage < 9) perPage = 9; // info block (Program, Course...) stays whole
    if (perLast < 1) perLast = 1;

    // Page breaks: session columns per page, breaking between weeks.
    int start = 0;
    while (n - start > perLast) {
      int end = n - start <= perPage
          ? start + (n - start + 1) ~/ 2 // balance the last two pages
          : start + perPage;
      final int lowest = start + ((end - start) * 2) ~/ 3;
      for (int e = end; e > lowest; e--) {
        if (e < n && weekOf[e] != weekOf[e - 1]) {
          end = e;
          break;
        }
      }
      x.colBreaks.add(firstSessionCol + end);
      start = end;
    }

    // Repeat Roll No / Name / Father Name and the header rows on every page.
    x.printTitles =
        'Sheet1!\$A:\$C,Sheet1!\$${labRow + 1}:\$${serialRow + 1}';

    // The title bar only spans the first page, so its text is not cut.
    final int titleEnd =
        x.colBreaks.isEmpty ? lastCol : x.colBreaks.first - 1;
    x.merges.remove('A1:${_excelColLetters(lastCol)}1');
    x.merge(0, 0, titleEnd, 0, 'University of Swabi', titleStyle);
  }

  return x.build();
}


// ---- Student loaders ----
// Internal key of a student (called "roll" in the app). The first roll "12" gets
// "12", then "12__2", "12__3" and so on, so duplicates never overwrite each other.
// Screens and Excel show rollOf(key), i.e. "12".
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

List<Map<String, String>> _sortedStudents(Map<String, String> m,
    [Map<String, String>? fathers]) {
  final list = m.entries
      .map((e) => {
            'roll': e.key,
            'name': e.value,
            'father': fathers?[e.key] ?? '',
          })
      .toList();
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

// Copies all students of semester [from] to [to] (same department and section).
// Nothing is overwritten: a clashing roll gets a new unique key. Returns the count.
Future<int> copyStudentsToSemester(SemRef from, SemRef to) async {
  final src = await loadSemesterStudents(from);
  if (src.isEmpty) return 0;
  final dest = await loadSemesterStudents(to);
  final taken = dest.map((s) => s['roll']!).toSet();
  for (final s in src) {
    final key = uniqueStudentKey(rollOf(s['roll']!), taken);
    taken.add(key);
    final name = s['name']!;
    final father = s['father'] ?? '';
    unawaited(to.students
        .doc(key)
        .set({'roll': key, 'name': name, 'father': father}).catchError(
            (Object e) => debugPrint('Copy student error: $e')));
    unawaited(LocalDb.upsertStudent(to, key, name, father));
  }
  return src.length;
}

// Master list of a semester (admin-managed). Reads Firestore first and falls back
// to the SQLite copy when nothing is cached.
Future<List<Map<String, String>>> loadSemesterStudents(SemRef sem) async {
  final res = await _safeQuery(sem.students);
  final m = <String, String>{};
  final f = <String, String>{};
  for (final d in res.docs) {
    final data = d.data();
    final k = (data['roll'] ?? d.id).toString();
    m[k] = (data['name'] ?? '').toString();
    f[k] = (data['father'] ?? '').toString();
  }
  if (m.isEmpty && res.fromCache) {
    m.addAll(await LocalDb.students(sem));
    f.addAll(await LocalDb.fathers(sem));
  }
  return _sortedStudents(m, f);
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
      'father': (data['father'] ?? '').toString(),
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
  final f = {for (final s in master) s['roll']!: s['father'] ?? ''};
  ov.forEach((roll, o) {
    if (o['kind'] == 'hidden') {
      m.remove(roll);
      f.remove(roll);
    } else if (o['kind'] == 'extra') {
      m[roll] = o['name'] ?? '';
      f[roll] = o['father'] ?? '';
    }
  });
  return _sortedStudents(m, f);
}

// One attendance record (one date and session) of a subject.
class DateRecord {
  final String id; // yyyy-MM-dd_Session_n
  final Map<String, String> status; // roll -> 'P' / 'A'
  final Map<String, String> meta; // _time, _marked_by, _marked_by_name, _type
  DateRecord(this.id, this.status, this.meta);

  // Session type: 'class' or 'lab'. Old records have no _type, so they count as class.
  bool get isLab => meta['_type'] == kTypeLab;

  // Exam phase: 'mid' or 'final'. Old records have no _phase, so they count as Mid.
  bool get isFinal => meta['_phase'] == kPhaseFinal;
  bool get isMid => !isFinal;
}

// Exam phases stored in the '_phase' meta field of an attendance record.
const String kPhaseMid = 'mid';
const String kPhaseFinal = 'final';
String phaseLabel(String phase) => phase == kPhaseFinal ? 'Final' : 'Mid';

// ---- Current exam phase of a subject (Mid / Final button) ----
// Stored on the subject document (field exam_phase) and also locally, so it
// works offline and survives app restarts. Missing = Mid.
String _phasePrefKey(SemRef s, String subject) =>
    'exam_phase|${s.deptId}|${s.section}|${s.semester}|$subject';

Future<String> readLocalSubjectPhase(SemRef s, String subject) async {
  try {
    final p = await SharedPreferences.getInstance();
    return p.getString(_phasePrefKey(s, subject)) == kPhaseFinal
        ? kPhaseFinal
        : kPhaseMid;
  } catch (_) {
    return kPhaseMid;
  }
}

Future<void> cacheSubjectPhase(SemRef s, String subject, String phase) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_phasePrefKey(s, subject), phase);
  } catch (_) {}
}

// Server value of the subject phase (null if offline / not set).
Future<String?> fetchServerSubjectPhase(SemRef s, String subject) async {
  try {
    final d =
        await s.subjectDoc(subject).get().timeout(const Duration(seconds: 4));
    final v = d.data()?['exam_phase'];
    if (v == kPhaseFinal || v == kPhaseMid) return v as String;
  } catch (_) {}
  return null;
}

Future<void> saveSubjectPhase(SemRef s, String subject, String phase) async {
  await cacheSubjectPhase(s, subject, phase);
  // Not awaited: this never completes while offline.
  unawaited(s
      .subjectDoc(subject)
      .set({'exam_phase': phase}, SetOptions(merge: true))
      .catchError((_) {}));
}

// ---- Admin's Mid / Final announcement ----
// Stored as the field 'announced_phase' of settings/permissions (the document
// every teacher screen already listens to) and mirrored locally, so the reminder
// also shows offline and after an app restart. Missing = Mid (nothing announced).
const String kAnnouncedPhaseField = 'announced_phase';
const String _kAnnouncedPrefKey = 'announced_exam_phase';

String announcedPhaseFrom(Map<String, dynamic>? d) =>
    d?[kAnnouncedPhaseField] == kPhaseFinal ? kPhaseFinal : kPhaseMid;

Future<String> readLocalAnnouncedPhase() async {
  try {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAnnouncedPrefKey) == kPhaseFinal
        ? kPhaseFinal
        : kPhaseMid;
  } catch (_) {
    return kPhaseMid;
  }
}

Future<void> cacheAnnouncedPhase(String phase) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAnnouncedPrefKey, phase);
  } catch (_) {}
}

Future<void> saveAnnouncedPhase(String phase) async {
  await cacheAnnouncedPhase(phase);
  // Not awaited: this never completes while offline.
  unawaited(permissionsRef()
      .set({kAnnouncedPhaseField: phase}, SetOptions(merge: true))
      .catchError((_) {}));
}

// Session types stored in the '_type' meta field of an attendance record.
const String kTypeClass = 'class';
const String kTypeLab = 'lab';
String typeLabel(String type) => type == kTypeLab ? 'Lab Class' : 'Class';

// All attendance records of a subject in one read (sorted by id). Falls back to SQLite.
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

  // Needs internet so the server can stop two teachers claiming the same subject.
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


// ---------------------------------------------------------------------------
// Rename helpers (admin). A department's display name is its `name` field, so
// renaming it is a single update. A subject's name is its document ID, and a
// student's roll is the document ID too (and the field name inside every
// attendance record), so those two move the data to the new ID and then delete
// the old one. Both need the internet so nothing is left half-moved.
// ---------------------------------------------------------------------------
class RenameException implements Exception {
  final String message;
  RenameException(this.message);
  @override
  String toString() => message;
}


// Small "type a new name" dialog used for departments and subjects. [onSave]
// does the real work; a RenameException message is shown inside the dialog.
// Returns true when the rename went through.
Future<bool> showRenameDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  required Future<void> Function(String value) onSave,
  String? note,
  TextCapitalization caps = TextCapitalization.words,
}) async {
  final controller = TextEditingController(text: initial);
  String? error;
  bool busy = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(note,
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
              ),
            TextField(
              controller: controller,
              enabled: !busy,
              autofocus: true,
              textCapitalization: caps,
              decoration: InputDecoration(labelText: label, errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final v = controller.text.trim();
                    if (v.isEmpty) {
                      setLocal(() => error = 'Please enter a name');
                      return;
                    }
                    if (v == initial) {
                      Navigator.pop(dialogContext, false);
                      return;
                    }
                    setLocal(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await onSave(v);
                      if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                    } on RenameException catch (e) {
                      setLocal(() {
                        busy = false;
                        error = e.message;
                      });
                    } catch (_) {
                      setLocal(() {
                        busy = false;
                        error =
                            'Could not rename. Please check your internet and try again.';
                      });
                    }
                  },
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

Future<void> _requireServer() async {
  if ((await _netState()) != _Net.reachable) {
    throw RenameException('An internet connection is required to rename this.');
  }
}

Future<QuerySnapshot<Map<String, dynamic>>> _serverQuery(
    Query<Map<String, dynamic>> q) async {
  final snap = await q.get().timeout(const Duration(seconds: 30));
  if (snap.metadata.isFromCache) {
    throw RenameException('Could not reach the server. Please try again.');
  }
  return snap;
}

Future<void> _commitInChunks(
    List<void Function(WriteBatch b)> ops) async {
  for (int i = 0; i < ops.length; i += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final op in ops.skip(i).take(400)) {
      op(batch);
    }
    await batch.commit().timeout(const Duration(seconds: 30));
  }
}

Future<void> renameDepartment(String deptId, String newName) async {
  final name = newName.trim();
  if (name.isEmpty || name.contains('/')) {
    throw RenameException('Please enter a valid name.');
  }
  final res = await _safeQuery(FirebaseFirestore.instance.collection('departments'));
  for (final d in res.docs) {
    if (d.id != deptId &&
        (d.data()['name'] ?? d.id).toString().toLowerCase() ==
            name.toLowerCase()) {
      throw RenameException('This department name already exists');
    }
  }
  unawaited(FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .set({'name': name}, SetOptions(merge: true)).catchError((_) {}));
  await LocalDb.upsertDepartment(deptId, name);
  unawaited(syncLocalDbIfStale(force: true));
}

Future<void> renameSubjectEverywhere(
    SemRef sem, String oldName, String newNameRaw) async {
  final newName = newNameRaw.trim().toUpperCase();
  if (newName.isEmpty || newName.contains('/')) {
    throw RenameException('Please enter a valid name.');
  }
  if (newName == oldName) return;
  await _requireServer();

  final oldRef = sem.subjectDoc(oldName);
  final newRef = sem.subjectDoc(newName);
  final oldSnap = await oldRef.get().timeout(const Duration(seconds: 15));
  if (oldSnap.metadata.isFromCache) {
    throw RenameException('Could not reach the server. Please try again.');
  }
  if (!oldSnap.exists) throw RenameException('This subject no longer exists.');
  final newSnap = await newRef.get().timeout(const Duration(seconds: 15));
  if (newSnap.exists) {
    throw RenameException('A subject with this name already exists.');
  }

  final data = Map<String, dynamic>.from(oldSnap.data() ?? {});
  data['name'] = newName;
  final overrides = await _serverQuery(sem.overrides(oldName));
  final dates = await _serverQuery(sem.dates(oldName));

  // 1) copy everything under the new name
  final copyOps = <void Function(WriteBatch b)>[
    (b) => b.set(newRef, data),
    for (final d in overrides.docs)
      (b) => b.set(sem.overrides(newName).doc(d.id), d.data()),
    for (final d in dates.docs)
      (b) => b.set(sem.dates(newName).doc(d.id), d.data()),
  ];
  await _commitInChunks(copyOps);

  // 2) the teacher's claim points at the new name
  final cb = (data['claimed_by'] ?? '').toString();
  if (cb.isNotEmpty) {
    await teacherClaimsRef(cb).doc(sem.claimKey(newName)).set({
      'dept': sem.deptId,
      'section': sem.section,
      'semester': sem.semester,
      'subject': newName,
    });
    await teacherClaimsRef(cb).doc(sem.claimKey(oldName)).delete();
  }

  // 3) only now remove the old copy
  final delOps = <void Function(WriteBatch b)>[
    for (final d in overrides.docs) (b) => b.delete(d.reference),
    for (final d in dates.docs) (b) => b.delete(d.reference),
    (b) => b.delete(oldRef),
  ];
  await _commitInChunks(delOps);

  await LocalDb.renameSubject(sem, oldName, newName);
  unawaited(syncLocalDbIfStale(force: true));
}

// Changes a student's roll number. Returns the new internal key.
Future<String> changeStudentRoll(
    SemRef sem, String oldKey, String newRollRaw, String name,
    [String father = '']) async {
  final newRoll = newRollRaw.trim();
  if (newRoll.isEmpty) throw RenameException('Please enter a roll number.');
  if (newRoll.contains('/') || newRoll.contains('__')) {
    throw RenameException('Roll number cannot contain "/" or "__".');
  }
  if (rollOf(oldKey) == newRoll) return oldKey; // roll unchanged
  await _requireServer();

  final existing = await _serverQuery(sem.students);
  final keys = existing.docs
      .map((d) => (d.data()['roll'] ?? d.id).toString())
      .where((k) => k != oldKey);
  final newKey = uniqueStudentKey(newRoll, keys);

  final subjects = await _serverQuery(sem.subjects);
  final oldField = FieldPath([oldKey]);
  final newField = FieldPath([newKey]);
  final ops = <void Function(WriteBatch b)>[];

  for (final sub in subjects.docs) {
    // attendance records: move the student's P/A under the new key
    final dates = await _serverQuery(sem.dates(sub.id));
    for (final d in dates.docs) {
      final m = d.data();
      if (!m.containsKey(oldKey)) continue;
      final v = m[oldKey];
      ops.add((b) => b.update(d.reference, <Object, Object?>{
            newField: v,
            oldField: FieldValue.delete(),
          }));
    }
    // subject-level override of this student
    final ov = await sem.overrides(sub.id).doc(oldKey).get();
    if (ov.exists) {
      final od = Map<String, dynamic>.from(ov.data() ?? {});
      od['roll'] = newKey;
      ops.add((b) => b.set(sem.overrides(sub.id).doc(newKey), od));
      ops.add((b) => b.delete(ov.reference));
    }
  }
  ops.add((b) => b.set(sem.students.doc(newKey),
      {'roll': newKey, 'name': name, 'father': father}));
  ops.add((b) => b.delete(sem.students.doc(oldKey)));

  // Attendance moves come first and the student record last. If something fails
  // halfway, just try again: the retry finishes the remaining moves.
  await _commitInChunks(ops);

  await LocalDb.renameStudentKey(sem, oldKey, newKey, name, father);
  unawaited(syncLocalDbIfStale(force: true));
  return newKey;
}

// Deletes a whole department (all sections, semesters and old data).
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

// Admin only: deletes all attendance records from Firestore, SQLite and the device
// cache. Departments, subjects and students stay. Needs internet (throws otherwise).
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
// Backup: reads every Firestore document into one JSON file (saved on the phone
// or downloaded on web). Restore: writes each document back to its path. It never
// deletes anything, and running it twice is harmless.
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

// Web: opens the share sheet. Browsers only allow sharing within a few
// seconds of a tap, so if that time ran out while the file was being prepared
// we show a small dialog whose "Share" button gives a fresh tap.
Future<void> webShareOrDownload(
    BuildContext context, List<int> bytes, String name,
    {String? text}) async {
  // Android Chrome blocks sharing Excel/JSON files, so just download there.
  // iPhone / iPad keep the share sheet.
  if (isAndroidBrowser()) {
    downloadBytes(bytes, name);
    if (context.mounted) {
      showSnack(context, 'File downloaded. Find it in your Downloads folder.');
    }
    return;
  }
  final r = await shareBytesNow(bytes, name, text: text);
  if (r == 'shared') return;
  if (r == 'unsupported') {
    if (context.mounted) {
      showSnack(context, 'Share not available ($lastShareError). Downloaded instead.');
    }
    downloadBytes(bytes, name);
    return;
  }
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('File ready'),
      content: Text(name),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            downloadBytes(bytes, name);
          },
          child: const Text('Download'),
        ),
        FilledButton(
          onPressed: () async {
            // Start the share FIRST (inside the tap), then close the dialog.
            final pending = shareBytesNow(bytes, name, text: text);
            Navigator.pop(ctx);
            final r2 = await pending;
            if (r2 != 'shared') {
              if (context.mounted) {
                showSnack(context, 'Could not open share: $lastShareError');
              }
              downloadBytes(bytes, name);
            }
          },
          child: const Text('Share'),
        ),
      ],
    ),
  );
}

// Creates the backup file and saves/shares it. Returns the number of records.
Future<int> createBackupFile([BuildContext? context]) async {
  final data = await _collectBackup();
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
  final name =
      'attendance_backup_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.json';
  if (kIsWeb) {
    if (context != null && context.mounted) {
      await webShareOrDownload(context, bytes, name,
          text: 'Attendance backup');
    } else {
      await saveOrShareBytes(bytes, name, text: 'Attendance backup');
    }
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
    final n = await createBackupFile(context.mounted ? context : null);
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
// Data is copied, not deleted, so running it again is safe.
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
    debugPrint('Migration failed (will retry next time): $e');
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
// Every function catches its own errors, so SQLite problems never stop the app.
// Passwords and the department username are not saved here (keeps the second
// admin hidden in exports).
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
        'CREATE TABLE students (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, roll TEXT NOT NULL, name TEXT, father TEXT DEFAULT \'\', PRIMARY KEY (dept_id, section, semester, roll))');
    await db.execute(
        'CREATE TABLE subjects (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, name TEXT NOT NULL, claimed_by TEXT, claimed_by_name TEXT, PRIMARY KEY (dept_id, section, semester, name))');
    await db.execute(
        'CREATE TABLE overrides (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, roll TEXT NOT NULL, name TEXT, kind TEXT, father TEXT DEFAULT \'\', PRIMARY KEY (dept_id, section, semester, subject, roll))');
    await db.execute(
        'CREATE TABLE attendance (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, session_id TEXT NOT NULL, roll TEXT NOT NULL, status TEXT, marked_time TEXT, marked_by TEXT, marked_by_name TEXT, session_type TEXT, exam_phase TEXT DEFAULT \'mid\', PRIMARY KEY (dept_id, section, semester, subject, session_id, roll))');
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
      version: 5,
      onCreate: (db, version) async => _createAll(db),
      // v1 -> v2: the structure changed. The local DB is only a Firestore copy, so drop
      // the old tables and recreate them; data refills when online.
      // v2 -> v3: add the session type column (old rows count as 'class').
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          for (final t in _tables) {
            await db.execute('DROP TABLE IF EXISTS $t');
          }
          await _createAll(db);
          return;
        }
        if (oldV < 3) {
          await db.execute(
              "ALTER TABLE attendance ADD COLUMN session_type TEXT DEFAULT 'class'");
        }
        // v3 -> v4: father name of students (old rows get an empty value).
        if (oldV < 4) {
          await db.execute(
              "ALTER TABLE students ADD COLUMN father TEXT DEFAULT ''");
          await db.execute(
              "ALTER TABLE overrides ADD COLUMN father TEXT DEFAULT ''");
        }
        // v4 -> v5: exam phase (Mid / Final) of a session. Old rows count as Mid.
        if (oldV < 5) {
          await db.execute(
              "ALTER TABLE attendance ADD COLUMN exam_phase TEXT DEFAULT 'mid'");
        }
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
  static Future<void> upsertStudent(SemRef s, String roll, String name,
      [String father = '']) {
    return _run((db) async {
      await db.insert(
        'students',
        {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'roll': roll,
          'name': name,
          'father': father,
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
      SemRef s, String subject, String roll, String name, String kind,
      [String father = '']) {
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
          'father': father,
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
    String sessionType = kTypeClass,
    String phase = kPhaseMid,
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
              'session_type': sessionType,
              'exam_phase': phase,
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        });
        await batch.commit(noResult: true);
      });
    });
  }

  // Changes only the type of one session (Class <-> Lab Class).
  static Future<void> setSessionType(
      SemRef s, String subject, String sessionId, String type) {
    return _run((db) async {
      await db.update('attendance', {'session_type': type},
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
    });
  }

  // Changes only the exam phase of one session (Mid <-> Final).
  static Future<void> setSessionPhase(
      SemRef s, String subject, String sessionId, String phase) {
    return _run((db) async {
      await db.update('attendance', {'exam_phase': phase},
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
    });
  }

  // Marks one student Present ('P') or Absent ('A') in every saved session of a
  // subject. A session where the student has no row yet gets one (copying that
  // session's time / marked-by / type / phase), so the whole past record changes.
  static Future<void> setStudentStatusAll(
      SemRef s, String subject, String roll, String status) {
    return _run((db) async {
      await db.transaction((txn) async {
        final rows = await txn.query('attendance',
            where: '$_semWhere AND subject = ?',
            whereArgs: [..._semArgs(s), subject]);
        final sessions = <String, Map<String, Object?>>{};
        for (final r in rows) {
          sessions.putIfAbsent((r['session_id'] ?? '').toString(), () => r);
        }
        final batch = txn.batch();
        sessions.forEach((sessionId, r) {
          batch.insert(
            'attendance',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'subject': subject,
              'session_id': sessionId,
              'roll': roll,
              'status': status,
              'marked_time': r['marked_time'] ?? '',
              'marked_by': r['marked_by'] ?? '',
              'marked_by_name': r['marked_by_name'] ?? '',
              'session_type': r['session_type'] ?? kTypeClass,
              'exam_phase': r['exam_phase'] ?? kPhaseMid,
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

  // Rebuilds SQLite from Firestore. collectionGroup fetches each collection in one
  // query; the document path gives the department / section / semester.
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

      // Data from the offline cache means we aren't really online: keep the existing
      // SQLite data instead of replacing it with a partial copy.
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
          'father': (sd['father'] ?? '').toString(),
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
          'father': (od['father'] ?? '').toString(),
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
            'session_type': parsed.meta['_type'] ?? kTypeClass,
            'exam_phase': parsed.meta['_phase'] ?? kPhaseMid,
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

  // roll -> father name of the students of a semester (offline fallback).
  static Future<Map<String, String>> fathers(SemRef s) async {
    try {
      final db = await _open();
      final rows = await db.query('students',
          where: _semWhere, whereArgs: _semArgs(s));
      return {
        for (final r in rows)
          (r['roll'] ?? '').toString(): (r['father'] ?? '').toString()
      };
    } catch (e) {
      debugPrint('LocalDb fathers error: $e');
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
            'father': (r['father'] ?? '').toString(),
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
        rec.meta['_type'] =
            (r['session_type'] ?? '').toString() == kTypeLab ? kTypeLab : kTypeClass;
        rec.meta['_phase'] =
            (r['exam_phase'] ?? '').toString() == kPhaseFinal ? kPhaseFinal : kPhaseMid;
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

  // Quick refresh of one subject's attendance from the server (monthly view), so
  // records from other devices show too. Returns true only if fresh data was written.
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
                'session_type': parsed.meta['_type'] ?? kTypeClass,
                'exam_phase': parsed.meta['_phase'] ?? kPhaseMid,
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

  // Re-reads one semester's students from the SERVER and replaces the SQLite rows,
  // so SQLite matches Firebase right after a change (father names included).
  static Future<bool> refreshSemesterStudents(SemRef s) async {
    try {
      if ((await _netState()) != _Net.reachable) return false;
      final snap = await s.students
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete('students',
            where: _semWhere, whereArgs: _semArgs(s));
        final batch = txn.batch();
        for (final d in snap.docs) {
          final sd = d.data();
          batch.insert(
            'students',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'roll': (sd['roll'] ?? d.id).toString(),
              'name': (sd['name'] ?? '').toString(),
              'father': (sd['father'] ?? '').toString(),
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
      return true;
    } catch (e) {
      debugPrint('LocalDb refreshSemesterStudents error: $e');
      return false;
    }
  }

  // Same for the subject-level student changes (overrides).
  static Future<bool> refreshSubjectOverrides(SemRef s, String subject) async {
    try {
      if ((await _netState()) != _Net.reachable) return false;
      final snap = await s
          .overrides(subject)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete('overrides',
            where: '$_semWhere AND subject = ?',
            whereArgs: [..._semArgs(s), subject]);
        final batch = txn.batch();
        for (final d in snap.docs) {
          final od = d.data();
          batch.insert(
            'overrides',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'subject': subject,
              'roll': (od['roll'] ?? d.id).toString(),
              'name': (od['name'] ?? '').toString(),
              'father': (od['father'] ?? '').toString(),
              'kind': (od['kind'] ?? '').toString(),
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
      return true;
    } catch (e) {
      debugPrint('LocalDb refreshSubjectOverrides error: $e');
      return false;
    }
  }

  static Future<void> deleteAllAttendance() {
    return _run((db) async {
      await db.delete('attendance');
    });
  }

  // ---------------- renames (keep SQLite in step with Firestore) ----------------
  static Future<void> renameSubject(SemRef s, String oldName, String newName) {
    return _run((db) async {
      await db.transaction((txn) async {
        final w = '$_semWhere AND subject = ?';
        final a = [..._semArgs(s), oldName];
        await txn.update('attendance', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('overrides', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('claims', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('subjects', {'name': newName},
            where: '$_semWhere AND name = ?', whereArgs: a);
      });
    });
  }

  static Future<void> renameStudentKey(
      SemRef s, String oldKey, String newKey, String name,
      [String father = '']) {
    return _run((db) async {
      await db.transaction((txn) async {
        final a = [..._semArgs(s), oldKey];
        await txn.delete('students',
            where: '$_semWhere AND roll = ?', whereArgs: a);
        await txn.insert(
          'students',
          {
            'dept_id': s.deptId,
            'section': s.section,
            'semester': s.semester,
            'roll': newKey,
            'name': name,
            'father': father,
          },
          conflictAlgorithm: sql.ConflictAlgorithm.replace,
        );
        await txn.update('attendance', {'roll': newKey},
            where: '$_semWhere AND roll = ?', whereArgs: a,
            conflictAlgorithm: sql.ConflictAlgorithm.replace);
        await txn.update('overrides', {'roll': newKey},
            where: '$_semWhere AND roll = ?', whereArgs: a,
            conflictAlgorithm: sql.ConflictAlgorithm.replace);
      });
    });
  }
}

// Refreshes SQLite from Firestore every few hours and right after coming back online.
Future<void> syncLocalDbIfStale({bool force = false}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('sqlite_last_sync_ms') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - last;
    if (!force && age < const Duration(hours: 1).inMilliseconds) return;
    final ok = await LocalDb.replaceAllFromFirestore();
    if (ok) {
      await prefs.setInt(
          'sqlite_last_sync_ms', DateTime.now().millisecondsSinceEpoch);
    }
  } catch (_) {}
}

// Login-time prefetch: one query each for students, subjects, semesters and
// attendance, so lists and attendance also show offline.
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
  // claimMode: the teacher's "Claim Subject" flow (Department -> Section ->
  // Semester -> Subject; tap to claim).
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

  // On admin login, run in order: seed -> second admin -> copy old Software
  // Engineering data to Section A / Semester 3 -> local sync.
  Future<void> _adminBootstrap() async {
    await _ensureSeedData();
    await ensureHiddenAdminDepartment();
    final moved = await migrateSoftwareEngineeringLegacy();
    if (moved && mounted) {
      showSnack(context,
          'Old Software Engineering data has been moved into Section A / Semester 3.');
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

      // Old Software Engineering data is now seeded directly into Section A / Semester 3.
      final target = SemRef(kSoftwareEngineeringDeptId, 'A', '3');
      final studentsSnap = await target.students.limit(1).get().timeout(_kNetworkTimeout);
      if (studentsSnap.docs.isEmpty) {
        var batch = firestore.batch();
        for (var s in initialStudents) {
          batch.set(target.students.doc(s['roll']),
              {'roll': s['roll'], 'name': s['name'], 'father': ''});
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

  // Departments have no passwords now, so the user types the name to confirm delete.
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

  // Admin only: only the display name changes; the department's ID stays the same.
  Future<void> _showRenameDepartmentDialog(String deptId, String deptName) async {
    final done = await showRenameDialog(
      context,
      title: 'Rename Department',
      label: 'Department Name',
      initial: deptName,
      onSave: (v) => renameDepartment(deptId, v),
    );
    if (done && mounted) showSnack(context, 'Department renamed');
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
                        final n = await createBackupFile(mounted ? context : null);
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
    // Class <-> Lab and Mid <-> Final conversion are always allowed, and Edit
    // also covers Delete, so none of those are listed here.
    final items = <({String key, String label, IconData icon})>[
      (key: kPermAnytime, label: 'TIME', icon: Icons.schedule),
      (key: kPermChangeTime, label: 'SET TIME', icon: Icons.access_time),
      (key: kPermChangeDate, label: 'DATE', icon: Icons.calendar_today),
      (key: kPermEdit, label: 'EDIT / DELETE', icon: Icons.edit_outlined),
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
          final announced = announcedPhaseFrom(d);
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: kGlassBorder),
              ),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const IconBadge(icon: Icons.tune, size: 44),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Teacher permissions',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEAF6FF),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Choose what teachers can do',
                              style: TextStyle(color: kLabelBlue, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Exam phase announcement: Mid / Final
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: kCardGrad,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kGlassBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const IconBadge(
                                        icon: Icons.campaign_outlined,
                                        size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  'Exam phase: ${phaseLabel(announced)}',
                                                  style: const TextStyle(
                                                    color: Color(0xFFEAF6FF),
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const _PermChip('MID / FINAL'),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            announced == kPhaseFinal
                                                ? 'Teachers whose subject is still in Mid see a reminder to switch it to Final.'
                                                : 'Tap Final to remind every teacher to switch their subject from Mid to Final.',
                                            style: const TextStyle(
                                                color: kMuted, fontSize: 12.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: GradPill(
                                        label: 'Mid',
                                        expand: true,
                                        height: 40,
                                        filled: announced == kPhaseMid,
                                        onTap: announced == kPhaseMid
                                            ? null
                                            : () => saveAnnouncedPhase(kPhaseMid),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: GradPill(
                                        label: 'Final',
                                        expand: true,
                                        height: 40,
                                        filled: announced == kPhaseFinal,
                                        onTap: announced == kPhaseFinal
                                            ? null
                                            : () => saveAnnouncedPhase(kPhaseFinal),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Master switch card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: kCardGrad,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kGlassBorder),
                            ),
                            child: Row(
                              children: [
                                const IconBadge(
                                    icon: Icons.verified_user_outlined,
                                    size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              on
                                                  ? 'Master switch: ON'
                                                  : 'Master switch: OFF',
                                              style: const TextStyle(
                                                color: Color(0xFFEAF6FF),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const _PermChip('ALL'),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        on
                                            ? 'Teachers can do everything: mark at any time, pick any date or time, and edit or delete records.'
                                            : 'Turn on the options below one by one to give teachers only that ability.',
                                        style: const TextStyle(
                                            color: kMuted, fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _permSwitch(on, (v) => setPerms({kPermMaster: v})),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final it in items)
                            Opacity(
                              opacity: on ? 0.7 : 1,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: kGlass,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: kGlassBorder),
                                ),
                                child: Row(
                                  children: [
                                    IconBadge(icon: it.icon, size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _PermChip(it.label),
                                          const SizedBox(height: 4),
                                          Text(
                                            _permSubtitle(it.key),
                                            style: const TextStyle(
                                                color: kMuted, fontSize: 12.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _permSwitch(
                                      on || d[it.key] == true,
                                      on ? null : (v) => setPerms({it.key: v}),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GradPill(
                      label: 'Close',
                      onTap: () => Navigator.pop(dialogContext),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Switch in the app's blue (no outline, white thumb).
  Widget _permSwitch(bool value, ValueChanged<bool>? onChanged) {
    return Switch(
      value: value,
      onChanged: onChanged,
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return states.contains(WidgetState.disabled)
              ? kAccent.withValues(alpha: 0.6)
              : kAccent;
        }
        return const Color(0x33FFFFFF);
      }),
    );
  }

  // Short English explanation shown under each permission's label.
  String _permSubtitle(String key) {
    switch (key) {
      case kPermAnytime:
        return 'Let the teacher mark attendance any time, not just the first $kMarkWindowMinutes minutes of the hour.';
      case kPermChangeTime:
        return 'Let the teacher pick the class time manually.';
      case kPermChangeDate:
        return 'Let the teacher choose any date, not just today.';
      case kPermEdit:
        return 'Let the teacher change or delete attendance that is already taken.';
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
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        toolbarHeight: 84,
        title: HeaderCard(
          title: claim ? 'Claim Subject' : 'Departments',
          actions: [
            if (_isAdmin && !claim)
              HeaderTile(
                icon: Icons.tune,
                tooltip: 'Teacher permissions & exam phase',
                onTap: _showMasterSwitch,
              ),
            if (_isAdmin && !claim) const TeacherRequestsButton(),
            if (_isAdmin && !claim)
              HeaderTile(
                icon: Icons.cloud_upload_outlined,
                tooltip: 'Backup & Restore',
                onTap: _showBackupRestore,
              ),
            if (_isAdmin && !claim)
              HeaderTile(
                icon: Icons.delete_sweep_outlined,
                color: kAbsent,
                tooltip: 'Delete overall attendance',
                onTap: _confirmDeleteOverallAttendance,
              ),
            if (!claim)
              HeaderTile(
                icon: Icons.logout,
                color: Colors.white,
                tile: false,
                tooltip: 'Logout',
                onTap: () => confirmAndLogout(context),
              ),
          ],
        ),
      ),
      floatingActionButton: (_isAdmin && !claim)
          ? GradFab(onPressed: _showAddDepartmentDialog)
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
                                  child: Text(deptName, style: kNameStyle),
                                ),
                                if (_isAdmin && !claim) ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        color: kAccent),
                                    tooltip: 'Rename department',
                                    onPressed: () => _showRenameDepartmentDialog(
                                        deptId, deptName),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: kAbsent),
                                    tooltip: 'Delete department',
                                    onPressed: () => _confirmDeleteDepartment(
                                        deptId, deptName),
                                  ),
                                ] else if (_isAdmin)
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
      appBar: headerAppBar(title: deptName),
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
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kAccent, kAccent2],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(sec,
                        style: const TextStyle(
                            color: kOnAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Section $sec', style: kNameStyle),
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
      appBar: headerAppBar(title: deptName, subtitle: 'Section $section'),
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
                          child: Text(label, style: kNameStyle),
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

// Subjects screen (one department, section and semester)
// Admin: add / delete / open. Teacher: claim / unclaim / open (own subjects only).
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

  Future<void> _showRenameSubjectDialog(
      BuildContext context, String subjectName) async {
    final done = await showRenameDialog(
      context,
      title: 'Rename Subject',
      label: 'Subject Name',
      initial: subjectName,
      caps: TextCapitalization.characters,
      note:
          'All attendance, student changes and the teacher claim of this subject move to the new name. Internet is required.',
      onSave: (v) => renameSubjectEverywhere(sem, subjectName, v),
    );
    if (done && context.mounted) showSnack(context, 'Subject renamed');
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
      appBar: headerAppBar(
        title: '$semLabel • ${sem.section}',
        actions: [
          if (isAdmin)
            HeaderTile(
              icon: Icons.groups_outlined,
              tooltip: 'Manage Students',
              onTap: () => Navigator.push(
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
          ? GradFab(onPressed: () => _showAddSubjectDialog(context))
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
                              style: kNameStyle.copyWith(fontSize: 15)),
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
                    if (isAdmin) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: kAccent),
                        tooltip: 'Rename subject',
                        onPressed: () =>
                            _showRenameSubjectDialog(context, subjectName),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: kAbsent),
                        tooltip: 'Delete subject',
                        onPressed: () =>
                            _confirmDeleteSubject(context, subjectName),
                      ),
                    ] else if (isMine)
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
                    Text(subject, style: kNameStyle.copyWith(fontSize: 15)),
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

  // Header card (avatar, welcome, claim and logout).
  Widget _page(BuildContext context, int count, Widget list) {
    final name = AppSession.teacherName.toString();
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final initials =
        parts.isEmpty ? '?' : parts.take(2).map((p) => p[0].toUpperCase()).join();
    Widget squareButton(IconData icon, String tip, VoidCallback onTap,
        {bool filled = false}) {
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: filled
                  ? const LinearGradient(colors: [kAccent, kAccent2])
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: filled ? null : Border.all(color: kAccentLine),
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kGlass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kGlassBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [kAccent, kAccent2]),
                      ),
                      child: Text(initials,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Welcome back',
                              style: TextStyle(color: kMuted, fontSize: 12.5)),
                          Text(name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    squareButton(
                      Icons.bookmark_add_outlined,
                      'Claim Subject',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const DepartmentsScreen(claimMode: true)),
                      ),
                      filled: true,
                    ),
                    const SizedBox(width: 8),
                    squareButton(Icons.logout, 'Logout',
                        () => confirmAndLogout(context)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                return _page(context, f.data!.length, _buildList(context, f.data!));
              },
            );
          }
          return _page(context, items.length, _buildList(context, items));
        },
      ),
    );
  }
}

// Import students (Excel .xlsx / CSV / TXT)
// Only names are needed. Rolls follow file order: first name 1, second 2, and so on.
// Used by both the admin (semester list) and the teacher (subject list).
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

// The cell value type differs between excel package versions, so read it as
// dynamic and convert it to text.
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

// Cleans a name cell: odd spaces, serial prefixes ("1.", "01)", "12 Rahul") and
// punctuation at the ends.
String _cleanImportedName(String raw) {
  var s = raw.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^\(?\d{1,6}\s*[.)\]:\-\u2013]\s*'), '');
  s = s.replaceFirst(RegExp(r'^\d{1,6}\s+(?=\p{L})', unicode: true), '');
  s = s.replaceAll(RegExp(r'^[\s,;:\-\u2013]+|[\s,;:\-\u2013]+$'), '');
  return s.trim();
}

// ---------------------------------------------------------------------------
// Smart matching helpers (used by the student import AND the old attendance
// import). Case, spaces and punctuation don't matter; common spelling
// variants (Muhammad / Mohammad / Mohd / M., Abdul / Abd ...) are treated as
// the same word; small typos are tolerated with a safe threshold.
// ---------------------------------------------------------------------------
const Map<String, String> _kNameAliases = {
  'mohammad': 'muhammad',
  'mohammed': 'muhammad',
  'muhammed': 'muhammad',
  'mohamed': 'muhammad',
  'mohamad': 'muhammad',
  'muhamad': 'muhammad',
  'mohd': 'muhammad',
  'muhd': 'muhammad',
  'mhd': 'muhammad',
  'md': 'muhammad',
  'abd': 'abdul',
  'abdu': 'abdul',
  'abdur': 'abdul',
  'abdel': 'abdul',
  'rehman': 'rahman',
};

String _canonPerson(String s) {
  final t = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return '';
  final parts = t.split(' ');
  for (var i = 0; i < parts.length; i++) {
    if (i == 0 && parts[i] == 'm' && parts.length > 1) {
      parts[i] = 'muhammad';
    } else {
      parts[i] = _kNameAliases[parts[i]] ?? parts[i];
    }
  }
  return parts.join(' ');
}

// Same words in any order give the same key ("Khan Ali" == "Ali Khan").
String _sortedCanon(String s) {
  final t = _canonPerson(s).split(' ')..sort();
  return t.join(' ').trim();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
      cur[j] = v;
    }
    prev = cur;
  }
  return prev[b.length];
}

double _stringRatio(String a, String b) {
  final m = a.length > b.length ? a.length : b.length;
  if (m == 0) return 1;
  return 1 - _levenshtein(a, b) / m;
}

// 0..1 similarity of two person names.
double _personSim(String a, String b) {
  final x = _canonPerson(a);
  final y = _canonPerson(b);
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  final r1 = _stringRatio(x, y);
  final r2 = _stringRatio(_sortedCanon(a), _sortedCanon(b));
  return r1 > r2 ? r1 : r2;
}

// Father names: true = same person's father, false = clearly different,
// null = unknown (one of them is empty).
bool? _fatherCompat(String a, String b) {
  if (a.trim().isEmpty || b.trim().isEmpty) return null;
  return _personSim(a, b) >= 0.8;
}

// ---------------------------------------------------------------------------
// Student import (Excel .xlsx / .xls / CSV / TXT): Name + Father Name columns.
// Roll numbers are NOT read from the file; they follow file order.
// ---------------------------------------------------------------------------
class ImportedStudent {
  final String name;
  final String father;
  const ImportedStudent(this.name, this.father);
}

// Header text -> letters only, lowercase. "F. Name" -> "fname", "S/O" -> "so".
String _compactHeader(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{M}]', unicode: true), '');

// 0 = not a name header, 1 = full name, 2 = first name, 3 = last name,
// 4 = father name. The header wording does not matter.
int _studentHeaderKind(String raw) {
  final c = _compactHeader(raw);
  if (c.isEmpty || c.length > 40) return 0;
  const fatherExact = {
    'fo', 'fname', 'so', 'do', 'sodo', 'sdo', 'walid', 'wald', 'waldiyat',
    'guardian', 'gaurdian', 'parent', 'parentname',
  };
  if (c.contains('father') ||
      fatherExact.contains(c) ||
      c.startsWith('walid') ||
      c.startsWith('wald') ||
      c.startsWith('guardian') ||
      c.contains('पिता') ||
      c.contains('والد')) {
    return 4;
  }
  if (RegExp(r'mother|husband|spouse').hasMatch(c)) return 0;
  if ((c.startsWith('first') || c.startsWith('given')) && c.contains('name')) {
    return 2;
  }
  if ((c.startsWith('last') || c.startsWith('sur') || c.startsWith('family')) &&
      c.contains('name')) {
    return 3;
  }
  if (c == 'student' || c == 'students') return 1;
  if (c.contains('name') ||
      c.contains('naam') ||
      c.contains('नाम') ||
      c.contains('نام')) {
    return 1;
  }
  return 0;
}

bool _importLooksLikeName(String n) =>
    n.length >= 2 &&
    _importLetterRe.hasMatch(n) &&
    !RegExp(r'\d').hasMatch(n) &&
    !_importSkipRowRe.hasMatch(n);

// Father name cell: same cleanup as a name, minus "S/O", "D/O" prefixes.
String _cleanImportedFather(String raw) {
  var s = _cleanImportedName(raw);
  s = s.replaceFirst(
      RegExp(r'^(s\s*/\s*o|d\s*/\s*o|w\s*/\s*o|son\s+of|daughter\s+of)\s*[:.\-]?\s*',
          caseSensitive: false),
      '');
  s = s.trim();
  if (!_importLetterRe.hasMatch(s)) return '';
  const empties = {'na', 'n/a', 'nil', 'none', 'null'};
  if (empties.contains(s.toLowerCase())) return '';
  return s;
}

class _StudentCols {
  final int firstRow; // first data row
  final int nameCol; // -1 when first + last name columns are used
  final int fatherCol; // -1 = none
  final int firstNameCol;
  final int lastNameCol;
  final bool sure; // false: ask the user which column is which
  const _StudentCols(this.firstRow, this.nameCol, this.fatherCol,
      this.firstNameCol, this.lastNameCol, this.sure);
}

// How many cells of each column look like a person's name.
List<int> _nameLikeCounts(List<List<String>> rows) {
  var w = 0;
  for (final r in rows) {
    if (r.length > w) w = r.length;
  }
  final out = List<int>.filled(w, 0);
  for (final r in rows) {
    for (var c = 0; c < r.length; c++) {
      if (_importLooksLikeName(_cleanImportedName(r[c]))) out[c]++;
    }
  }
  return out;
}

_StudentCols? _detectStudentCols(List<List<String>> data) {
  if (data.isEmpty) return null;

  // 1) A header row in the first 15 rows (title rows above it are ignored).
  final scan = data.length < 15 ? data.length : 15;
  for (var i = 0; i < scan; i++) {
    var n = -1, f = -1, l = -1, fa = -1;
    for (var c = 0; c < data[i].length; c++) {
      switch (_studentHeaderKind(data[i][c])) {
        case 1:
          if (n < 0) n = c;
        case 2:
          if (f < 0) f = c;
        case 3:
          if (l < 0) l = c;
        case 4:
          if (fa < 0) fa = c;
      }
    }
    final hasName = n >= 0 || (f >= 0 && l >= 0);
    if (!hasName && fa < 0) continue;
    var nameCol = n;
    if (!hasName) {
      // Only a father header was recognised: the name is the best text column left.
      final counts = _nameLikeCounts(data.skip(i + 1).toList());
      var best = -1, bestV = 0;
      for (var c = 0; c < counts.length; c++) {
        if (c == fa) continue;
        if (counts[c] > bestV) {
          bestV = counts[c];
          best = c;
        }
      }
      if (best < 0) continue;
      nameCol = best;
    }
    return _StudentCols(i + 1, hasName && n < 0 ? -1 : nameCol, fa, f, l, true);
  }

  // 2) No header: skip a roll / serial header row, then take the text columns
  // from left to right (first = name, second = father name).
  const headerWords = {
    'roll', 'roll no', 'roll no.', 'roll number', 'rollno', 'sr', 'sr.',
    'sr no', 'sr no.', 'sr#', 's.no', 's no', 'sno', 'serial', 'serial no',
    '#', 'no', 'no.', 'id', 'reg no', 'registration no',
  };
  final firstNorm = data.first
      .map((c) => c.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim())
      .toList();
  final start = firstNorm.any(headerWords.contains) ? 1 : 0;
  final body = data.skip(start).toList();
  if (body.isEmpty) return null;
  final counts = _nameLikeCounts(body);
  final need = (body.length * 0.5).ceil();
  final textCols = <int>[
    for (var c = 0; c < counts.length; c++)
      if (counts[c] > 0 && counts[c] >= need) c
  ];
  if (textCols.isEmpty) {
    // Weak columns: use the single best one as the name.
    var best = -1, bestV = 0;
    for (var c = 0; c < counts.length; c++) {
      if (counts[c] > bestV) {
        bestV = counts[c];
        best = c;
      }
    }
    if (best < 0) return null;
    return _StudentCols(start, best, -1, -1, -1, true);
  }
  return _StudentCols(start, textCols[0],
      textCols.length > 1 ? textCols[1] : -1, -1, -1, textCols.length < 2);
}

List<ImportedStudent> _extractStudents(
    List<List<String>> data, _StudentCols c) {
  final out = <ImportedStudent>[];
  for (final r in data.skip(c.firstRow)) {
    String at(int i) => (i >= 0 && i < r.length) ? r[i] : '';
    final raw = c.nameCol >= 0
        ? at(c.nameCol)
        : '${at(c.firstNameCol)} ${at(c.lastNameCol)}';
    final name = _cleanImportedName(raw);
    if (name.isEmpty || !_importLetterRe.hasMatch(name)) continue;
    if (_importSkipRowRe.hasMatch(name)) continue;
    final father = c.fatherCol >= 0 ? _cleanImportedFather(at(c.fatherCol)) : '';
    out.add(ImportedStudent(name, father));
  }
  return out;
}

// Small screen: which column is the Name and which is the Father Name.
// Only shown when the file has no clear headers and several text columns.
Future<_StudentCols?> _askStudentColumns(
    BuildContext context, List<List<String>> data, _StudentCols guess) {
  var width = 0;
  for (final r in data) {
    if (r.length > width) width = r.length;
  }
  String sample(int c) {
    final vals = <String>[];
    for (final r in data.skip(guess.firstRow)) {
      if (c < r.length && r[c].trim().isNotEmpty) vals.add(r[c].trim());
      if (vals.length == 3) break;
    }
    return vals.join(', ');
  }

  final cols = <int>[
    for (var c = 0; c < width; c++)
      if (sample(c).isNotEmpty) c
  ];
  var nameCol = cols.contains(guess.nameCol) ? guess.nameCol : cols.first;
  var fatherCol = cols.contains(guess.fatherCol) ? guess.fatherCol : -1;

  return showDialog<_StudentCols>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        DropdownMenuItem<int> item(int c) => DropdownMenuItem<int>(
              value: c,
              child: Text('${_excelColLetters(c)}: ${sample(c)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            );
        return AlertDialog(
          title: const Text('Which column is which?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This file has no clear headers. Please choose the columns.',
                  style: TextStyle(color: kMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                const Text('Student name'),
                DropdownButton<int>(
                  isExpanded: true,
                  value: nameCol,
                  items: [for (final c in cols) item(c)],
                  onChanged: (v) => setS(() => nameCol = v ?? nameCol),
                ),
                const SizedBox(height: 8),
                const Text('Father name'),
                DropdownButton<int>(
                  isExpanded: true,
                  value: fatherCol,
                  items: [
                    const DropdownMenuItem<int>(value: -1, child: Text('None')),
                    for (final c in cols) item(c),
                  ],
                  onChanged: (v) => setS(() => fatherCol = v ?? fatherCol),
                ),
                if (nameCol == fatherCol)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Name and father name must be different columns.',
                        style: TextStyle(color: kAbsent, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: nameCol == fatherCol
                  ? null
                  : () => Navigator.pop(ctx,
                      _StudentCols(guess.firstRow, nameCol, fatherCol, -1, -1, true)),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    ),
  );
}

// Pick a file and read students (name + father name) from it. Null on error.
Future<List<ImportedStudent>?> pickStudentsFromFile(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls', 'csv', 'txt'],
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
  var grids = <List<List<String>>>[];
  try {
    final isZip = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (ext == 'xlsx' || ext == 'xlsm' || ext == 'xls' || isZip) {
      grids = _allXlsxGrids(bytes, forAttendance: false);
    } else if (ext == 'txt') {
      final lines = utf8
          .decode(bytes, allowMalformed: true)
          .replaceFirst('﻿', '')
          .split(RegExp(r'\r?\n'));
      grids = [
        [
          for (final l in lines) [l.trim()]
        ]
      ];
    } else {
      grids = [_parseCsvText(utf8.decode(bytes, allowMalformed: true))];
    }
  } catch (e) {
    debugPrint('Import parse error: $e');
  }
  if (grids.isEmpty) {
    if (!context.mounted) return null;
    _importSnack(context,
        'Could not read this file. Please use .xlsx or .csv (an old .xls may need to be opened and saved as .xlsx).');
    return null;
  }

  // First sheet that really contains students.
  List<List<String>>? data;
  _StudentCols? cols;
  for (final g in grids) {
    final d = g.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    final c = _detectStudentCols(d);
    if (c != null && _extractStudents(d, c).isNotEmpty) {
      data = d;
      cols = c;
      break;
    }
  }
  if (data == null || cols == null) {
    if (!context.mounted) return null;
    _importSnack(context, 'No student names found in this file.');
    return null;
  }

  if (!cols.sure) {
    if (!context.mounted) return null;
    cols = await _askStudentColumns(context, data, cols);
    if (cols == null) return null;
  }

  final list = _extractStudents(data, cols);
  if (list.isEmpty) {
    if (!context.mounted) return null;
    _importSnack(context, 'No student names found in this file.');
    return null;
  }
  return list;
}

// ---- Import plan: new students, father names to fill, conflicts ----
class FatherConflict {
  final String key;
  final String name;
  final String oldFather;
  final String newFather;
  const FatherConflict(this.key, this.name, this.oldFather, this.newFather);
}

class FuzzyPair {
  final String fileName;
  final String appName;
  const FuzzyPair(this.fileName, this.appName);
}

class StudentImportPlan {
  final List<MapEntry<String, String>> fills; // student key -> father to fill
  final List<FatherConflict> conflicts; // existing father is different
  final List<ImportedStudent> newOnes; // not in the app yet
  final List<FuzzyPair> fuzzy; // matched with a small spelling difference
  final int unchanged; // matched, nothing to change
  final int fileDupes; // names that appear more than once in the file
  final int total;
  const StudentImportPlan({
    required this.fills,
    required this.conflicts,
    required this.newOnes,
    required this.fuzzy,
    required this.unchanged,
    required this.fileDupes,
    required this.total,
  });
  int get matched => fills.length + conflicts.length + unchanged;
}

// Matches the file against the students already in the app, by NAME.
// Same name twice: the 1st occurrence in the file goes to the lower roll,
// the 2nd to the next one (a father name, when known, decides first).
StudentImportPlan planStudentImport(
    List<ImportedStudent> imported, List<Map<String, String>> existing) {
  final byKey = <String, List<int>>{};
  for (var i = 0; i < existing.length; i++) {
    (byKey[_sortedCanon(existing[i]['name'] ?? '')] ??= <int>[]).add(i);
  }
  final taken = <int>{};
  final matchOf = <int, int>{};
  final isFuzzy = <int>{};

  String fatherOf(int e) => existing[e]['father'] ?? '';

  int? pick(List<int> cands, String father) {
    final free = cands.where((e) => !taken.contains(e)).toList();
    if (free.isEmpty) return null;
    if (father.isEmpty) return free.first;
    for (final e in free) {
      if (_fatherCompat(fatherOf(e), father) == true) return e;
    }
    for (final e in free) {
      if (_fatherCompat(fatherOf(e), father) == null) return e;
    }
    return free.first;
  }

  for (var i = 0; i < imported.length; i++) {
    final cands = byKey[_sortedCanon(imported[i].name)];
    if (cands == null) continue;
    final e = pick(cands, imported[i].father);
    if (e != null) {
      matchOf[i] = e;
      taken.add(e);
    }
  }

  // Small typos: only when exactly one student is clearly the closest.
  for (var i = 0; i < imported.length; i++) {
    if (matchOf.containsKey(i)) continue;
    var best = 0.0, second = 0.0;
    var bi = -1;
    for (var e = 0; e < existing.length; e++) {
      if (taken.contains(e)) continue;
      if (_fatherCompat(fatherOf(e), imported[i].father) == false) continue;
      final s = _personSim(imported[i].name, existing[e]['name'] ?? '');
      if (s > best) {
        second = best;
        best = s;
        bi = e;
      } else if (s > second) {
        second = s;
      }
    }
    if (bi >= 0 && best >= 0.9 && best - second >= 0.05) {
      matchOf[i] = bi;
      taken.add(bi);
      isFuzzy.add(i);
    }
  }

  final fills = <MapEntry<String, String>>[];
  final conflicts = <FatherConflict>[];
  final newOnes = <ImportedStudent>[];
  final fuzzy = <FuzzyPair>[];
  var unchanged = 0;
  for (var i = 0; i < imported.length; i++) {
    final e = matchOf[i];
    if (e == null) {
      newOnes.add(imported[i]);
      continue;
    }
    final s = existing[e];
    final key = s['roll']!;
    final oldF = fatherOf(e).trim();
    final newF = imported[i].father.trim();
    if (isFuzzy.contains(i)) {
      fuzzy.add(FuzzyPair(imported[i].name, s['name'] ?? ''));
    }
    if (newF.isEmpty) {
      unchanged++;
    } else if (oldF.isEmpty) {
      fills.add(MapEntry(key, newF));
    } else if (_fatherCompat(oldF, newF) == true) {
      unchanged++;
    } else {
      conflicts.add(FatherConflict(key, s['name'] ?? '', oldF, newF));
    }
  }

  final seen = <String>{};
  var dupes = 0;
  for (final s in imported) {
    if (!seen.add(_sortedCanon(s.name))) dupes++;
  }
  return StudentImportPlan(
    fills: fills,
    conflicts: conflicts,
    newOnes: newOnes,
    fuzzy: fuzzy,
    unchanged: unchanged,
    fileDupes: dupes,
    total: imported.length,
  );
}

class StudentImportDecision {
  final int start; // first roll number for the new students
  final bool overwrite; // replace different father names with the file's
  const StudentImportDecision(this.start, this.overwrite);
}

// Preview + confirm. Null if cancelled.
Future<StudentImportDecision?> confirmStudentImportPlan(
  BuildContext context,
  StudentImportPlan plan,
  String where,
  List<Map<String, String>> existing,
) {
  final existingRolls = {for (final s in existing) rollOf(s['roll']!)};
  var maxRoll = 0;
  for (final r in existingRolls) {
    final n = int.tryParse(r) ?? 0;
    if (n > maxRoll) maxRoll = n;
  }
  final startCtrl =
      TextEditingController(text: plan.matched > 0 ? '${maxRoll + 1}' : '1');
  var overwrite = false;
  final hasNew = plan.newOnes.isNotEmpty;

  Widget line(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(text, style: TextStyle(fontSize: 13.5, color: color)),
      );

  return showDialog<StudentImportDecision>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final parsed = int.tryParse(startCtrl.text.trim());
        final int? start = (parsed != null && parsed >= 1) ? parsed : null;
        var clash = 0;
        if (hasNew && start != null) {
          for (var i = 0; i < plan.newOnes.length; i++) {
            if (existingRolls.contains((start + i).toString())) clash++;
          }
        }
        final work = plan.fills.length +
            plan.newOnes.length +
            (overwrite ? plan.conflicts.length : 0);
        final canImport = work > 0 && (!hasNew || start != null);
        return AlertDialog(
          title: Text(
              'Import ${plan.total} student${plan.total == 1 ? '' : 's'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Into: $where',
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 10),
                line('Father names to fill: ${plan.fills.length}',
                    color: plan.fills.isEmpty ? kMuted : kPresent),
                line('New students to add: ${plan.newOnes.length}',
                    color: plan.newOnes.isEmpty ? kMuted : kPresent),
                line('Already up to date: ${plan.unchanged}', color: kMuted),
                if (plan.conflicts.isNotEmpty)
                  line(
                      'Different father name: ${plan.conflicts.length}'
                      '${overwrite ? ' (will be replaced)' : ' (skipped)'}',
                      color: kAbsent),
                if (plan.conflicts.isNotEmpty) ...[
                  for (final c in plan.conflicts.take(4))
                    Text(
                        '• ${c.name}: ${c.oldFather} → ${c.newFather}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  if (plan.conflicts.length > 4)
                    Text('… and ${plan.conflicts.length - 4} more',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: overwrite,
                    title: const Text('Replace with the file’s father name',
                        style: TextStyle(fontSize: 13)),
                    onChanged: (v) => setS(() => overwrite = v),
                  ),
                ],
                if (plan.fuzzy.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  line('Matched with a small spelling difference:',
                      color: kAccent),
                  for (final p in plan.fuzzy.take(4))
                    Text('• ${p.fileName} → ${p.appName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  if (plan.fuzzy.length > 4)
                    Text('… and ${plan.fuzzy.length - 4} more',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                ],
                if (hasNew) ...[
                  const SizedBox(height: 8),
                  for (final s in plan.newOnes.take(5))
                    Text(
                        '• ${s.name}${s.father.isEmpty ? '' : '  (S/O ${s.father})'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  if (plan.newOnes.length > 5)
                    Text('… and ${plan.newOnes.length - 5} more',
                        style: const TextStyle(color: kMuted)),
                ],
                if (plan.fileDupes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${plan.fileDupes} name${plan.fileDupes == 1 ? '' : 's'} appear more than once in the file.',
                    style: const TextStyle(color: kAccent, fontSize: 12.5),
                  ),
                ],
                if (hasNew) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'New students get roll numbers in file order, counting up from the number you enter.',
                    style: TextStyle(color: kMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: startCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      labelText: 'First roll number',
                      errorText:
                          start != null ? null : 'Enter a number (1 or more)',
                      helperText: start != null
                          ? 'Roll $start to ${start + plan.newOnes.length - 1}'
                          : null,
                    ),
                  ),
                  if (clash > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$clash of these roll numbers already exist. The new students will be added next to them with the same roll number; nothing is overwritten.',
                      style: const TextStyle(color: kAccent, fontSize: 12.5),
                    ),
                  ],
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
              onPressed: canImport
                  ? () => Navigator.pop(
                      ctx, StudentImportDecision(start ?? 1, overwrite))
                  : null,
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
      {String? existingRoll, String? existingName, String? existingFather}) {
    final rollController =
        TextEditingController(text: rollOf(existingRoll ?? ''));
    final nameController = TextEditingController(text: existingName ?? '');
    final fatherController = TextEditingController(text: existingFather ?? '');
    bool isEditing = existingRoll != null;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Edit Student' : 'Add Student'),
        content: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 10),
              TextField(
                controller: fatherController,
                decoration: const InputDecoration(labelText: 'Father Name'),
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
            onPressed: () async {
              final roll = rollController.text.trim();
              final name = nameController.text.trim();
              final father =
                  fatherController.text.replaceAll(RegExp(r'\s+'), ' ').trim();
              if (roll.isEmpty || name.isEmpty) return;

              // Roll number changed: move the student and all attendance to the new roll.
              if (existingRoll != null && roll != rollOf(existingRoll)) {
                Navigator.pop(dialogContext);
                await _changeRoll(context, existingRoll, roll, name, father);
                return;
              }

              // Edit: same student (existingRoll is its key). Add: if the roll exists, a new
              // unique key is created so the old student isn't overwritten.
              String key = existingRoll ?? roll;
              if (!isEditing) {
                final existing = await loadSemesterStudents(sem);
                key = uniqueStudentKey(roll, existing.map((s) => s['roll']!));
              }
              // The write is created first, so the list updates at once from the
              // local cache; SQLite is updated immediately too.
              final write = sem.students
                  .doc(key)
                  .set({'roll': key, 'name': name, 'father': father});
              unawaited(LocalDb.upsertStudent(sem, key, name, father));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              final res = await fsWrite(write, what: 'student');
              await finishStudentWrite(context.mounted ? context : null, sem, res);
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeRoll(
      BuildContext context, String oldKey, String newRoll, String name,
      [String father = '']) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    String? err;
    try {
      await changeStudentRoll(sem, oldKey, newRoll, name, father);
    } on RenameException catch (e) {
      err = e.message;
    } catch (_) {
      err = 'Could not change the roll number. Please check your internet and try again.';
    }
    if (!context.mounted) return;
    Navigator.pop(context); // close the progress dialog
    showSnack(context, err ?? 'Roll number changed to $newRoll');
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
    final list = await pickStudentsFromFile(context);
    if (list == null || !context.mounted) return;
    final existing = await loadSemesterStudents(sem);
    if (!context.mounted) return;
    final plan = planStudentImport(list, existing);
    final decision = await confirmStudentImportPlan(
        context, plan, '$semLabel ${sem.section}', existing);
    if (decision == null) return;

    final byKey = {for (final s in existing) s['roll']!: s};
    final taken = existing.map((s) => s['roll']!).toSet();
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    final commits = <Future<void>>[];
    void flushIfFull() {
      if (++ops >= 400) {
        commits.add(batch.commit());
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }

    // 1) Existing students: only the father name is filled (no duplicates).
    final fatherWrites = <MapEntry<String, String>>[
      ...plan.fills,
      if (decision.overwrite)
        for (final c in plan.conflicts) MapEntry(c.key, c.newFather),
    ];
    for (final w in fatherWrites) {
      final name = byKey[w.key]?['name'] ?? '';
      batch.set(sem.students.doc(w.key), {'father': w.value},
          SetOptions(merge: true));
      unawaited(LocalDb.upsertStudent(sem, w.key, name, w.value));
      flushIfFull();
    }

    // 2) New students: roll numbers follow file order from the chosen start.
    for (var i = 0; i < plan.newOnes.length; i++) {
      // If the roll exists, a new unique key is created; nothing is overwritten.
      final key = uniqueStudentKey((decision.start + i).toString(), taken);
      taken.add(key);
      final s = plan.newOnes[i];
      batch.set(sem.students.doc(key),
          {'roll': key, 'name': s.name, 'father': s.father});
      unawaited(LocalDb.upsertStudent(sem, key, s.name, s.father));
      flushIfFull();
    }
    if (ops > 0) commits.add(batch.commit());
    if (!context.mounted) return;

    final skipped = decision.overwrite ? 0 : plan.conflicts.length;
    final parts = <String>[
      '${fatherWrites.length} father name${fatherWrites.length == 1 ? '' : 's'} filled',
      '${plan.newOnes.length} new student${plan.newOnes.length == 1 ? '' : 's'} added',
      if (skipped > 0) '$skipped skipped (different father name)',
    ];
    _importSnack(context, parts.join(', '));

    // Online: wait for the server, then refresh SQLite from it. A failure is shown.
    final res = await fsWriteAll(commits, what: 'student import');
    await finishStudentWrite(context.mounted ? context : null, sem, res);
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
              final write = sem.students.doc(roll).delete();
              unawaited(LocalDb.deleteStudent(sem, roll));
              final res = await fsWrite(write, what: 'delete student');
              if (res == SaveResult.saved) {
                unawaited(LocalDb.refreshSemesterStudents(sem));
              }
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
      appBar: headerAppBar(
        title: 'Students',
        subtitle: '$semLabel • Section ${sem.section}',
        actions: [
          HeaderTile(
            icon: Icons.upload_file_outlined,
            tooltip: 'Import students (Excel / CSV)',
            onTap: () => _importStudents(context),
          ),
          HeaderTile(
            icon: Icons.copy_all_outlined,
            tooltip: 'Copy students to another semester',
            onTap: () => _showCopyDialog(context),
          ),
        ],
      ),
      floatingActionButton: GradFab(
        icon: Icons.person_add_alt_1,
        onPressed: () => _showStudentDialog(context),
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
              final father = (data['father'] ?? '').toString();

              return AppCard(
 float: false,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    RollBadge(roll: roll),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StudentNameBlock(name: name, father: father),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: kAccent),
                      onPressed: () => _showStudentDialog(context,
                          existingRoll: roll,
                          existingName: name,
                          existingFather: father),
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

// Student name with the father name as a smaller muted line under it.
// Old students without a father name show just the name.
class StudentNameBlock extends StatelessWidget {
  final String name;
  final String father;
  final Color? color;
  final String? extra; // optional extra line (e.g. attendance percentage)
  final Color? extraColor;
  const StudentNameBlock({
    super.key,
    required this.name,
    this.father = '',
    this.color,
    this.extra,
    this.extraColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
            style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        if (father.trim().isNotEmpty)
          Text('S/O ${father.trim()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: kMuted)),
        if (extra != null)
          Text(extra!,
              style: TextStyle(fontSize: 12.5, color: extraColor ?? kMuted)),
      ],
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
// Soft remove: the student stays in the admin's master list and is only hidden here.
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
  Map<String, String> _masterFather = {};
  // roll -> {'name': ..., 'father': ..., 'kind': 'extra' | 'hidden'}
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
      _masterFather = {for (final s in master) s['roll']!: s['father'] ?? ''};
    } catch (e) {
      debugPrint('Subject students load error: $e');
    }
    if (mounted) setState(() => _loading = false);
    // Online: bring SQLite in line with Firebase for this subject.
    unawaited(LocalDb.refreshSemesterStudents(widget.sem));
    unawaited(LocalDb.refreshSubjectOverrides(widget.sem, widget.subjectName));
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

  Map<String, String> get _effectiveFather {
    final m = Map<String, String>.from(_masterFather);
    _overrides.forEach((roll, o) {
      if (o['kind'] == 'hidden') {
        m.remove(roll);
      } else if (o['kind'] == 'extra') {
        m[roll] = o['father'] ?? '';
      }
    });
    return m;
  }

  void _addStudent() {
    final rollController = TextEditingController();
    final nameController = TextEditingController();
    final fatherController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add student to this subject'),
        content: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 10),
              TextField(
                controller: fatherController,
                decoration: const InputDecoration(labelText: 'Father Name'),
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
            onPressed: () async {
              final typedRoll = rollController.text.trim();
              final name = nameController.text.trim();
              final father =
                  fatherController.text.replaceAll(RegExp(r'\s+'), ' ').trim();
              if (typedRoll.isEmpty || name.isEmpty) return;
              // If the roll already exists (master / extra / hidden), create a unique key.
              final roll = uniqueStudentKey(
                  typedRoll, [..._master.keys, ..._overrides.keys]);
              final sem = widget.sem;
              final sub = widget.subjectName;
              final write = sem.overrides(sub).doc(roll).set({
                'roll': roll,
                'name': name,
                'father': father,
                'kind': 'extra',
              });
              unawaited(
                  LocalDb.upsertOverride(sem, sub, roll, name, 'extra', father));
              setState(() => _overrides[roll] =
                  {'name': name, 'father': father, 'kind': 'extra'});
              Navigator.pop(dialogContext);
              final res = await fsWrite(write, what: 'subject student');
              if (!mounted) return;
              await finishStudentWrite(context, sem, res, subject: sub);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _importStudents() async {
    final list = await pickStudentsFromFile(context);
    if (list == null || !mounted) return;
    final taken = {..._master.keys, ..._overrides.keys};
    // Students already in this subject: match by name so father names get
    // filled for them too, and only really new names are added.
    final eff = _effective;
    final effFather = _effectiveFather;
    final inSubject = [
      for (final e in eff.entries)
        {'roll': e.key, 'name': e.value, 'father': effFather[e.key] ?? ''}
    ];
    final plan = planStudentImport(list, inSubject);
    final decision = await confirmStudentImportPlan(
        context,
        plan,
        '${widget.subjectName} (this subject)',
        [for (final k in taken) {'roll': k, 'name': ''}]);
    if (decision == null || !mounted) return;
    final start = decision.start;

    final sem = widget.sem;
    final sub = widget.subjectName;
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    final commits = <Future<void>>[];
    void flushIfFull() {
      if (++ops >= 400) {
        commits.add(batch.commit());
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }

    final added = <String, Map<String, String>>{};
    // Students of the master list that get a NEW father name: the father name is
    // also saved on the master student (students collection), in its own batch
    // so a permission problem there never blocks the subject changes.
    final masterFills = <MapEntry<String, String>>[
      for (final w in plan.fills)
        if (_master.containsKey(w.key)) w
    ];

    // 1) Existing students: only the father name is filled (this subject only).
    final fatherWrites = <MapEntry<String, String>>[
      ...plan.fills,
      if (decision.overwrite)
        for (final c in plan.conflicts) MapEntry(c.key, c.newFather),
    ];
    for (final w in fatherWrites) {
      final name = eff[w.key] ?? '';
      batch.set(sem.overrides(sub).doc(w.key), {
        'roll': w.key,
        'name': name,
        'father': w.value,
        'kind': 'extra',
      });
      unawaited(
          LocalDb.upsertOverride(sem, sub, w.key, name, 'extra', w.value));
      added[w.key] = {'name': name, 'father': w.value, 'kind': 'extra'};
      flushIfFull();
    }
    final masterCommits = <Future<void>>[];
    for (var i = 0; i < masterFills.length; i += 400) {
      final mb = FirebaseFirestore.instance.batch();
      for (final w in masterFills.skip(i).take(400)) {
        mb.set(sem.students.doc(w.key), {'father': w.value},
            SetOptions(merge: true));
        unawaited(LocalDb.upsertStudent(sem, w.key, _master[w.key] ?? '', w.value));
        _masterFather[w.key] = w.value;
      }
      masterCommits.add(mb.commit());
    }

    // 2) New students: roll numbers follow file order from the chosen start.
    for (var i = 0; i < plan.newOnes.length; i++) {
      final st = plan.newOnes[i];
      final key = uniqueStudentKey((start + i).toString(), taken);
      taken.add(key);
      batch.set(sem.overrides(sub).doc(key), {
        'roll': key,
        'name': st.name,
        'father': st.father,
        'kind': 'extra',
      });
      unawaited(
          LocalDb.upsertOverride(sem, sub, key, st.name, 'extra', st.father));
      added[key] = {'name': st.name, 'father': st.father, 'kind': 'extra'};
      flushIfFull();
    }
    if (ops > 0) commits.add(batch.commit());
    if (!mounted) return;
    setState(() => _overrides.addAll(added));

    final n = plan.newOnes.length;
    final skipped = decision.overwrite ? 0 : plan.conflicts.length;
    final parts = <String>[
      '${fatherWrites.length} father name${fatherWrites.length == 1 ? '' : 's'} filled',
      '$n new student${n == 1 ? '' : 's'} added',
      if (skipped > 0) '$skipped skipped (different father name)',
    ];
    _importSnack(context, parts.join(', '));

    final res = await fsWriteAll(commits, what: 'subject import');
    final masterRes = await fsWriteAll(masterCommits, what: 'master father fill');
    if (!mounted) return;
    await finishStudentWrite(
        context, sem, res == SaveResult.saved ? masterRes : res,
        subject: sub);
    if (res == SaveResult.saved) {
      await LocalDb.refreshSubjectOverrides(sem, sub);
    }
  }

  void _removeStudent(String roll, String name) {
    final father = _effectiveFather[roll] ?? '';
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
                unawaited(fsWrite(
                        sem.overrides(sub).doc(roll).set({
                          'roll': roll,
                          'name': name,
                          'father': father,
                          'kind': 'hidden',
                        }),
                        what: 'hide student')
                    .then((r) {
                  if (r == SaveResult.saved) {
                    unawaited(LocalDb.refreshSubjectOverrides(sem, sub));
                  }
                }));
                unawaited(
                    LocalDb.upsertOverride(sem, sub, roll, name, 'hidden', father));
                setState(() => _overrides[roll] =
                    {'name': name, 'father': father, 'kind': 'hidden'});
              } else {
                // Student added only to this subject: remove the override
                unawaited(fsWrite(sem.overrides(sub).doc(roll).delete(),
                        what: 'remove student')
                    .then((r) {
                  if (r == SaveResult.saved) {
                    unawaited(LocalDb.refreshSubjectOverrides(sem, sub));
                  }
                }));
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
    final list = _sortedStudents(_effective, _effectiveFather);
    return Scaffold(
      appBar: headerAppBar(
        title: widget.subjectName,
        subtitle: 'Students of this subject',
        actions: [
          HeaderTile(
            icon: Icons.upload_file_outlined,
            tooltip: 'Import students (Excel / CSV)',
            onTap: _importStudents,
          ),
        ],
      ),
      floatingActionButton: GradFab(
        icon: Icons.person_add_alt_1,
        onPressed: _addStudent,
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
 float: false,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                              child: Row(
                                children: [
                                  RollBadge(roll: s['roll']!),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StudentNameBlock(
                                        name: s['name']!,
                                        father: s['father'] ?? ''),
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
// Flutter's picker can't limit the range, so this is a small custom dialog:
// 6 AM to 6 PM, with only :00 at 6 PM.
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
// Layout: dates in a row on top, names on the left, P / A under each date.
// Each date becomes one session record. Files exported by this app import directly.
class ImportColumn {
  final int col;
  final DateTime date;
  final int session;
  final bool isLab; // column has a "Lab" label above it
  ImportColumn(this.col, this.date, this.session, {this.isLab = false});
  String get docId =>
      '${DateFormat('yyyy-MM-dd').format(date)}_Session_$session';
}

class ImportRow {
  final String name;
  final String roll; // roll from the file (only if there is a 'Roll' column)
  final Map<int, String> status; // column index -> 'P' / 'A'
  final String father; // father name from the file ('' if there is no column)
  ImportRow(this.name, this.roll, this.status, [this.father = '']);
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

// true: 12/09/2025 means 12 Sep (day first); false: Dec 9. Set by parseAttendanceSheet.
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

// Reads a date from cell text. Numeric formats are day first (dd/mm/yyyy).
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
// Google Sheets and mobile apps. This reads the zip's XML directly so any .xlsx opens.
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
// Detects the layout itself and uses the one with the most P/A entries:
//   1) WIDE: dates in one row, names in one column
//   2) TRANSPOSED: dates in one column, names in the top row
//   3) LONG: each row = Date | Name | Status (any column order)
// Column order, extra columns and status wording don't matter.
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
  final String father;
  _ImportLongRec(this.name, this.roll, this.date, this.sess, this.status,
      [this.father = '']);
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
  if (_studentHeaderKind(raw) == 4) return false; // F. Name, S/O, Walid ...
  if (RegExp(r'father|mother|parent|guardian').hasMatch(t)) return false;
  return t == 'student' || t == 'naam' || t.contains('name');
}

bool _importIsFatherHeader(String raw) => _studentHeaderKind(raw) == 4;

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

// Gets [year, month] from the title or header (e.g. "September 2025", "09/2025").
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

// A header row with only day numbers (1 2 3 ... 31), with month and year above it.
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

  // Father name column: any header like Father Name / F/O / S/O / Walid / Guardian.
  var fatherCol = -1;
  for (var c = 0; c < nC && fatherCol < 0; c++) {
    if (dates.containsKey(c)) continue;
    for (var r = 0; r <= dateRow + 2 && r < nR; r++) {
      if (_importIsFatherHeader(cell(r, c))) {
        fatherCol = c;
        break;
      }
    }
  }

  // Name column: the one with 'name' in its header, else the one with the most text.
  var nameCol = -1;
  var bestScore = 0.0;
  for (var c = 0; c < nC; c++) {
    if (dates.containsKey(c) || c == fatherCol) continue;
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
    if (c == nameCol || c == fatherCol || dates.containsKey(c)) continue;
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

  // Merged date header (several sessions under one date): the blank header cells
  // after it that have P/A belong to the same date.
  final colDate = Map<int, DateTime>.from(dates);
  for (final c in dateKeys) {
    for (var k = c + 1; k < nC; k++) {
      if (dates.containsKey(k) || k == nameCol || k == rollCol || k == fatherCol) {
        break;
      }
      if (cell(dateRow, k).isNotEmpty) break;
      var hits = 0;
      for (final r in nameRows) {
        if (_parseImportStatus(cell(r, k)) != null) hits++;
      }
      if (hits == 0 || hits * 2 < nameRows.length) break;
      colDate[k] = dates[c]!;
    }
  }

  // Session numbers: use "Session 2" from the header, else count 1, 2, 3 for repeated dates.
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
    // Files exported by this app have a small "Lab" cell above lab columns.
    var lab = false;
    for (var rr = dateRow - 1; rr >= 0 && rr >= dateRow - 3; rr--) {
      final t = cell(rr, c).trim().toLowerCase();
      if (t == 'lab' || t == 'lab class') {
        lab = true;
        break;
      }
    }
    columns.add(ImportColumn(c, d, sess, isLab: lab));
  }

  final outRows = <ImportRow>[];
  for (final r in nameRows) {
    final st = <int, String>{};
    for (final col in columns) {
      final v = _parseImportStatus(cell(r, col.col));
      if (v != null) st[col.col] = v;
    }
    if (st.isEmpty) continue;
    outRows.add(ImportRow(
        names[r]!,
        rollCol >= 0 ? cell(r, rollCol) : '',
        st,
        fatherCol >= 0 ? _cleanImportedFather(cell(r, fatherCol)) : ''));
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

  var fatherCol = -1;
  for (var c = 0; c < nC && fatherCol < 0; c++) {
    if (c == dateCol || c == statusCol) continue;
    if (headerHas(c, _importIsFatherHeader)) fatherCol = c;
  }

  var nameCol = -1;
  var bestScore = 0.0;
  for (var c = 0; c < nC; c++) {
    if (c == dateCol || c == statusCol || c == fatherCol) continue;
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
    if (c == dateCol || c == statusCol || c == nameCol || c == fatherCol) {
      continue;
    }
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
    final father =
        fatherCol >= 0 ? _cleanImportedFather(g[r][fatherCol]) : '';
    final dayKey = DateFormat('yyyy-MM-dd').format(d);
    final ok = '$dayKey|${_normImportName(name)}|${_normImportName(father)}';
    final n = (occ[ok] ?? 0) + 1;
    occ[ok] = n;
    var sess = n;
    if (sessCol >= 0) {
      final sm = RegExp(r'\d+').firstMatch(g[r][sessCol]);
      final v = int.tryParse(sm?.group(0) ?? '');
      if (v != null && v > 0) sess = v;
    }
    recs.add(_ImportLongRec(
        name, rollCol >= 0 ? g[r][rollCol] : '', d, sess, st, father));
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
    final nk = '${_normImportName(x.name)}|${_normImportName(x.father)}';
    final row = byName.putIfAbsent(
        nk, () => ImportRow(x.name, x.roll, <int, String>{}, x.father));
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

// Matches file rows to app students. Only sure matches count; the rest are shown
// to the user. Order of checks:
//   1) same name (any word order, spelling variants like Muhammad / Mohd / M.)
//      - when the file has a father name, name + father name must agree;
//      - same name twice: the father name decides first, and only if that cannot
//        decide, the Nth row in the file goes to the Nth student (roll order);
//   2) roll number, 3) a unique close spelling (typo) with a compatible father.
Map<int, String> autoMatchImportRows(
    List<ImportRow> rows, List<Map<String, String>> students) {
  final result = <int, String>{};
  final taken = <String>{};
  void take(int i, Map<String, String> s) {
    result[i] = s['roll']!;
    taken.add(s['roll']!);
  }

  final byKey = <String, List<Map<String, String>>>{};
  for (final s in students) {
    (byKey[_sortedCanon(s['name'] ?? '')] ??= <Map<String, String>>[]).add(s);
  }
  List<Map<String, String>> freeOf(int i) => [
        for (final s in byKey[_sortedCanon(rows[i].name)] ??
            const <Map<String, String>>[])
          if (!taken.contains(s['roll']!)) s
      ];

  // 1a) rows that have a father name: name + father name together.
  for (var i = 0; i < rows.length; i++) {
    final f = rows[i].father;
    if (f.isEmpty) continue;
    for (final s in freeOf(i)) {
      if (_fatherCompat(s['father'] ?? '', f) == true) {
        take(i, s);
        break;
      }
    }
  }

  // 1b) the rest: same name. Students with no father name filled yet are fine;
  // a student whose father name is clearly different is never taken.
  for (var i = 0; i < rows.length; i++) {
    if (result.containsKey(i)) continue;
    final f = rows[i].father;
    for (final s in freeOf(i)) {
      if (f.isEmpty || _fatherCompat(s['father'] ?? '', f) == null) {
        take(i, s);
        break;
      }
    }
  }

  // 2) roll number from the file (only if the father name does not contradict it)
  for (var i = 0; i < rows.length; i++) {
    if (result.containsKey(i) || rows[i].roll.isEmpty) continue;
    for (final s in students) {
      if (taken.contains(s['roll']!)) continue;
      if (rows[i].roll.trim() != rollOf(s['roll']!).trim()) continue;
      if (_fatherCompat(s['father'] ?? '', rows[i].father) == false) continue;
      take(i, s);
      break;
    }
  }

  // 3) small typos: only when exactly one student is clearly the closest.
  for (var i = 0; i < rows.length; i++) {
    if (result.containsKey(i)) continue;
    var best = 0.0, second = 0.0;
    Map<String, String>? bs;
    for (final s in students) {
      if (taken.contains(s['roll']!)) continue;
      if (_fatherCompat(s['father'] ?? '', rows[i].father) == false) continue;
      final sim = _personSim(rows[i].name, s['name'] ?? '');
      if (sim > best) {
        second = best;
        best = sim;
        bs = s;
      } else if (sim > second) {
        second = sim;
      }
    }
    if (bs != null && best >= 0.9 && best - second >= 0.05) take(i, bs);
  }
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

// Review screen: shows what will be imported and the unmatched names. The user can
// link a name to a student or skip it.
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
    setAppBusy(true);
    _map = autoMatchImportRows(widget.sheet.rows, widget.students);
    _autoRows = _map.keys.toSet();
    _cols = {
      for (final c in widget.sheet.columns)
        if (!_locked(c)) c.col
    };
  }

  @override
  void dispose() {
    setAppBusy(false);
    super.dispose();
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
 float: false,
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
 float: false,
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
 float: false,
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        rows[i].father.isEmpty
                            ? rows[i].name
                            : '${rows[i].name}  (S/O ${rows[i].father})',
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
                                '${rollOf(s['roll']!)} • ${s['name']}'
                                '${(s['father'] ?? '').isEmpty ? '' : ' (S/O ${s['father']})'}',
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
 float: false,
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
// Admin: no limits. Teacher (master switch OFF): only today, only in the first 20
// minutes of each hour, and only new records, unless allowed in Detailed permissions
// (any time, change time, change date, edit, delete). Master switch ON: all open.
// Each subject has its own screen.
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
  String sessionType = kTypeClass; // 'class' or 'lab' for the selected session
  String examPhase = kPhaseMid; // current Mid / Final phase of this subject
  String sessionPhase = kPhaseMid; // phase the selected session is saved with
  bool _phaseChangedLocally = false;
  // What the admin has announced (Mid = nothing to do, Final = switch now).
  String announcedPhase = kPhaseMid;
  bool _announceFromServer = false;

  // All records of this subject, loaded once and reused for the selected date,
  // copying the previous session and the percentages.
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
  // Edit permission also allows deleting.
  bool get _canDeleteRec => _unrestricted || perms.edit;
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
    setAppBusy(true); // web: do not auto-reload for an update while marking

    _permSub = permissionsRef().snapshots().listen((s) {
      final data = s.data();
      final p = TeacherPerms.from(data);
      // Trust the announcement when the field is there, or when the server
      // says it was never set. An empty offline cache must not reset it.
      String? a;
      if (data != null && data.containsKey(kAnnouncedPhaseField)) {
        a = announcedPhaseFrom(data);
      } else if (!s.metadata.isFromCache) {
        a = kPhaseMid;
      }
      if (a != null) {
        _announceFromServer = true;
        if (a != announcedPhase) unawaited(cacheAnnouncedPhase(a));
      }
      if (mounted && (p != perms || (a != null && a != announcedPhase))) {
        setState(() {
          perms = p;
          if (a != null) announcedPhase = a;
        });
      }
    }, onError: (_) {});

    // Last known announcement, so the reminder also works offline / on restart.
    unawaited(readLocalAnnouncedPhase().then((v) {
      if (!mounted || _announceFromServer || v == announcedPhase) return;
      setState(() => announcedPhase = v);
    }));

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
    setAppBusy(false);
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
      examPhase = await readLocalSubjectPhase(widget.sem, widget.subjectName);
      _fetchAttendanceForDate();
      _computePercentages();
    } catch (e) {
      debugPrint('Attendance load error: $e');
    }
    // Always stop the spinner, even if something above failed.
    if (mounted) setState(() => isLoading = false);
    unawaited(_syncPhaseFromServer());

    if (copiedFromPreviousSession && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSnack(context,
            'Attendance copied from the previous session. Change if needed and tap Save.');
      });
    }
  }

  // Picks up a phase change made on another device (offline keeps the local value).
  Future<void> _syncPhaseFromServer() async {
    final v = await fetchServerSubjectPhase(widget.sem, widget.subjectName);
    if (v == null || !mounted || _phaseChangedLocally || v == examPhase) return;
    await cacheSubjectPhase(widget.sem, widget.subjectName, v);
    if (!mounted) return;
    setState(() {
      examPhase = v;
      if (!existingRecord) sessionPhase = v;
    });
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
    sessionPhase = examPhase; // new sessions use the subject's current phase

    final cur = _recordById(_getDocumentId());
    if (cur != null) {
      attendanceStatus = Map<String, String>.from(cur.status);
      existingRecord = true;
      existingMeta = Map<String, String>.from(cur.meta);
      timeStr = cur.meta['_time'];
      sessionType = cur.isLab ? kTypeLab : kTypeClass;
      // An existing session keeps its own stored phase.
      sessionPhase = cur.isFinal ? kPhaseFinal : kPhaseMid;
      return;
    }

    timeStr = hhmm(TimeOfDay.now());

    for (int s = selectedSession - 1; s >= 1; s--) {
      final prev = _recordById(_getDocumentId(s));
      if (prev != null) {
        attendanceStatus = Map<String, String>.from(prev.status);
        copiedFromPreviousSession = true;
        // A new session usually has the same type as the one before it.
        sessionType = prev.isLab ? kTypeLab : kTypeClass;
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

  // Opens the full attendance sheet inside the app (works offline).
  void _viewSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceSheetScreen(
          sem: widget.sem,
          semLabel: widget.semLabel,
          subjectName: widget.subjectName,
        ),
      ),
    );
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

    // Time: an admin (or a teacher allowed to change time, or master switch ON) picks it.
    // Otherwise a new record gets the current time and an edited one keeps its old time.
    String? time = _canChangeTime
        ? timeStr
        : (existingRecord ? timeStr : hhmm(TimeOfDay.now()));
    if (time == null && !existingRecord) time = hhmm(TimeOfDay.now());
    if (time != null) data['_time'] = time;

    // Who marked it: if an admin edits a teacher's record, the teacher's name stays.
    String byId = AppSession.userId;
    String byName = AppSession.userName;
    if (_isAdmin && (existingMeta['_marked_by'] ?? '').isNotEmpty) {
      byId = existingMeta['_marked_by']!;
      byName = existingMeta['_marked_by_name'] ?? byName;
    }
    data['_marked_by'] = byId;
    data['_marked_by_name'] = byName;
    data['_type'] = sessionType; // Class or Lab Class
    data['_phase'] = sessionPhase; // Mid or Final

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
      sessionType: sessionType,
      phase: sessionPhase,
    ));

    final newMeta = <String, String>{
      '_time': ?time,
      '_marked_by': byId,
      '_marked_by_name': byName,
      '_type': sessionType,
      '_phase': sessionPhase,
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
      showSnack(context,
          'Attendance Saved/Updated for Session $selectedSession (${typeLabel(sessionType)}, ${phaseLabel(sessionPhase)})!');
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
  // For admin and teacher. This is old-date data, so the time window and "today only"
  // rules don't apply. Changing an existing session needs admin (or master switch ON).
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
      // Lab label in the file wins; otherwise keep the old type (new = Class).
      final type = col.isLab ? kTypeLab : ((old?.isLab ?? false) ? kTypeLab : kTypeClass);
      // New sessions get the subject's current phase; old ones keep theirs.
      final phase =
          old != null ? (old.isFinal ? kPhaseFinal : kPhaseMid) : examPhase;
      final data = <String, dynamic>{
        ...status,
        '_time': ?time,
        '_marked_by': byId,
        '_marked_by_name': byName,
        '_type': type,
        '_phase': phase,
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
        sessionType: type,
        phase: phase,
      );

      final newMeta = <String, String>{
        '_time': ?time,
        '_marked_by': byId,
        '_marked_by_name': byName,
        '_type': type,
        '_phase': phase,
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
    if (!mounted) return;
    final opt = await askExportOptions(context, recs);
    if (opt == null || !mounted) return;
    final picked = filterRecordsByScope(recs, opt.scope, phase: opt.phase);
    if (picked.isEmpty) {
      showSnack(context, 'No ${optionsLabel(opt)} sessions to export.',
          color: kAbsent);
      return;
    }
    final fileBytes = buildAttendanceExcelBytes(
      info: await loadExcelInfo(widget.sem, widget.subjectName),
      recs: picked,
      students: students,
      useLetters: opt.useLetters,
    );
    // File name: Subject_Section_A_Semester_3_[Mid_|Final_][Class_|Lab_]Full_Report.xlsx
    final base = exportFileBase(widget.sem, widget.semLabel, widget.subjectName);
    final fileName =
        '${base}_${phaseFileTag(opt.phase)}${scopeFileTag(opt.scope)}Full_Report.xlsx';
    if (!mounted) return;
    if (kIsWeb) {
      await webShareOrDownload(context, fileBytes!, fileName,
          text:
              '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} Attendance Report');
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    String filePath = '${directory.path}/$fileName';

    File(filePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes!);

    await SharePlus.instance.share(ShareParams(
      files: [XFile(filePath)],
      text:
          '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} Attendance Report',
    ));
  }

  // Class / Lab Class button (same look as the Mark all buttons).
  Widget _typeButton(String label, String type, bool enabled) {
    final selected = sessionType == type;
    return GradPill(
      label: label,
      filled: selected,
      enabled: enabled,
      onTap: enabled ? () => setState(() => sessionType = type) : null,
    );
  }

  // Mid / Final button (same look as the Class / Lab buttons).
  Widget _phaseButton(String label, String phase, bool enabled) {
    final selected = examPhase == phase;
    return GradPill(
      label: label,
      filled: selected,
      enabled: enabled,
      onTap: (enabled && !selected) ? () => _confirmSwitchPhase(phase) : null,
    );
  }

  // Asks before switching the subject between Mid and Final (both directions).
  Future<void> _confirmSwitchPhase(String newPhase) async {
    final name = phaseLabel(newPhase);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Switch to $name?'),
        content: Text(
            'New attendance for this subject will be saved as $name. Old attendance is not changed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _phaseChangedLocally = true;
    setState(() {
      examPhase = newPhase;
      if (!existingRecord) sessionPhase = newPhase;
    });
    await saveSubjectPhase(widget.sem, widget.subjectName, newPhase);
    if (mounted) showSnack(context, 'Subject is now in $name phase.');
  }

  // Teachers only: the admin announced the Final phase but this subject is still
  // in Mid. Shows every time the subject is opened until the teacher switches it
  // to Final (or the admin announces Mid again).
  Widget _finalReminderBanner() {
    if (_isAdmin || announcedPhase != kPhaseFinal || examPhase != kPhaseMid) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kViolet.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kViolet.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.campaign_outlined, color: kViolet, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The Mid phase has ended and the Final phase has started. '
                  'Please switch this subject from Mid to Final.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GradPill(
              label: 'Switch to Final',
              icon: Icons.emoji_events_outlined,
              height: 36,
              enabled: _canEdit,
              onTap: _canEdit ? () => _confirmSwitchPhase(kPhaseFinal) : null,
            ),
          ),
        ],
      ),
    );
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 6),
                          itemCount: (students.isEmpty ? 1 : students.length) + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                        top: MediaQuery.of(context).padding.top),
                                    child: HeaderCard(
          title: widget.subjectName,
          subtitle:
              '${widget.sem.deptId} • Section ${widget.sem.section} • ${widget.semLabel}',
          tabs: [
            HeaderAction(
              icon: Icons.groups_outlined,
              label: 'Students',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubjectStudentsScreen(
                        sem: widget.sem, subjectName: widget.subjectName),
                  ),
                ).then((_) => _loadAll());
              },
            ),
            HeaderAction(
              icon: Icons.bar_chart_rounded,
              label: 'Stats',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubjectStatsScreen(
                        sem: widget.sem, subjectName: widget.subjectName),
                  ),
                );
              },
            ),
            HeaderAction(
                icon: Icons.edit_calendar_outlined,
                label: 'Records',
                onTap: () {
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
              ),
            HeaderAction(
              icon: Icons.upload_file_outlined,
              label: 'Import',
              onTap: _importFromFile,
            ),
            HeaderAction(
              icon: Icons.table_chart_outlined,
              label: 'View',
              onTap: _viewSheet,
            ),
            HeaderAction(
              icon: Icons.file_download_outlined,
              label: 'Export',
              onTap: _exportToExcel,
            ),
          ],
        ),
                                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: GradPill(
                      onTap: _openMonthly,
                      icon: Icons.calendar_month_outlined,
                      label: 'Monthly attendance',
                      filled: false,
                      expand: true,
                      height: 46,
                      radius: 14,
                    ),
                  ),
                ),
                _finalReminderBanner(),
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
                            style: kLabelStyle.copyWith(fontSize: 16),
                          ),
                          if (_canChangeDate)
                            GradPill(
                              onTap: () async {
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
                              icon: Icons.calendar_today,
                              label: 'Change Date',
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
                              style: kLabelStyle.copyWith(fontSize: 16),
                            ),
                            GradPill(
                              onTap: () async {
                                final picked =
                                    await pickClassTime(context, parseHhmm(timeStr));
                                if (picked != null) {
                                  setState(() => timeStr = hhmm(picked));
                                }
                              },
                              icon: Icons.access_time,
                              label: 'Change Time',
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Lecture / Session:",
                            style: kLabelStyle.copyWith(fontSize: 15),
                          ),
                          DropdownButton<int>(
                            value: selectedSession,
                            style: kLabelStyle.copyWith(fontSize: 16),
                            iconEnabledColor: kAccent,
                            dropdownColor: kSurface,
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
                        const SizedBox(
                          width: 52,
                          child: Text('Exam:',
                              style: kLabelStyle),
                        ),
                        const SizedBox(width: 10),
                        _phaseButton('Mid', kPhaseMid, canEdit),
                        const SizedBox(width: 8),
                        _phaseButton('Final', kPhaseFinal, canEdit),
                      ],
                    ),
                  ),
                if (students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 52,
                          child: Text('Type:',
                              style: kLabelStyle),
                        ),
                        const SizedBox(width: 10),
                        _typeButton('Class', kTypeClass, canEdit),
                        const SizedBox(width: 8),
                        _typeButton('Lab Class', kTypeLab, canEdit),
                      ],
                    ),
                  ),
                if (students.isNotEmpty)
                  Builder(builder: (context) {
                    var absentCount = 0;
                    for (final st in students) {
                      if ((attendanceStatus[st['roll']!] ?? 'P') == 'A') {
                        absentCount++;
                      }
                    }
                    final presentCount = students.length - absentCount;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
                      child: Row(
                        children: [
                          Text('Present $presentCount',
                              style: const TextStyle(
                                  color: kAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 14),
                          Text('Absent $absentCount',
                              style: const TextStyle(
                                  color: kAbsent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 14),
                          Text('Total ${students.length}',
                              style: const TextStyle(
                                  color: kMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
                if (students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        const Text('Mark all:',
                            style: kLabelStyle),
                        const SizedBox(width: 10),
                        GradPill(
                          label: 'All Present',
                          enabled: canEdit,
                          onTap: canEdit
                              ? () => setState(() {
                                    for (final st in students) {
                                      attendanceStatus[st['roll']!] = 'P';
                                    }
                                  })
                              : null,
                        ),
                        const SizedBox(width: 8),
                        GradPill(
                          label: 'All Absent',
                          gradient: kRedGrad,
                          enabled: canEdit,
                          onTap: canEdit
                              ? () => setState(() {
                                    for (final st in students) {
                                      attendanceStatus[st['roll']!] = 'A';
                                    }
                                  })
                              : null,
                        ),
                      ],
                    ),
                  ),
                                ],
                              );
                            }
                            if (students.isEmpty) {
                              return const SizedBox(
                                height: 260,
                                child: EmptyState(
                                  icon: Icons.groups_outlined,
                                  text: 'There are no students in this subject yet.\nAdmin can add them from Manage Students.',
                                ),
                              );
                            }
                            var student = students[index - 1];
                            String roll = student['roll']!;
                            double? pct = studentPercentage[roll];
                            bool isLow = pct != null && pct < 75;

                            return RepaintBoundary(
                                child: AppCard(
 float: false,
                              subtle: true,
                              borderColor: isLow ? kAbsent : null,
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                              child: Row(
                                children: [
                                  RollBadge(roll: roll),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        StudentNameBlock(
                                          name: student['name']!,
                                          father: student['father'] ?? '',
                                          color: isLow ? kAbsent : null,
                                          extra: pct == null
                                              ? null
                                              : '${pct.toStringAsFixed(1)}% attendance',
                                          extraColor: isLow ? kAbsent : kMuted,
                                        ),
                                        if (pct != null) ...[
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: (pct / 100).clamp(0.0, 1.0),
                                              minHeight: 4,
                                              backgroundColor:
                                                  const Color(0xFF22308A),
                                              color: isLow ? kAbsent : kAccent,
                                            ),
                                          ),
                                        ],
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
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAbsent,
                                foregroundColor: const Color(0xFF2A0A12),
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
                        child: Opacity(
                          opacity: canEdit ? 1 : 0.5,
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [kAccent, kAccent2]),
                              borderRadius: BorderRadius.circular(27),
                              boxShadow: [
                                BoxShadow(
                                  color: kAccent2.withValues(alpha: 0.16),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: canEdit ? _saveAttendance : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white,
                              ),
                              child: Text(
                                existingRecord ? 'Save / Update' : 'Save Attendance',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
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
// Admin, or a teacher with Edit, Delete and/or Class/Lab permission (or master
// switch ON). Each button follows its own permission.
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

  // Moves one session between Class and Lab Class (fixes a wrong choice).
  void _confirmChangeType(
      BuildContext context, String docId, String label, String newType) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change session type?'),
        content: Text('Change $label to ${typeLabel(newType)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Not awaited: this never completes while offline.
              unawaited(sem
                  .dates(subjectName)
                  .doc(docId)
                  .update({'_type': newType}).catchError((_) {}));
              unawaited(LocalDb.setSessionType(sem, subjectName, docId, newType));
              if (context.mounted) {
                showSnack(context, '$label is now ${typeLabel(newType)}');
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  // Moves one session between Mid and Final (single toggle).
  void _confirmChangePhase(
      BuildContext context, String docId, String label, String newPhase) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change exam phase?'),
        content: Text('Change phase of $label to ${phaseLabel(newPhase)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Not awaited: this never completes while offline.
              unawaited(sem
                  .dates(subjectName)
                  .doc(docId)
                  .update({'_phase': newPhase}).catchError((_) {}));
              unawaited(LocalDb.setSessionPhase(sem, subjectName, docId, newPhase));
              if (context.mounted) {
                showSnack(context, '$label is now ${phaseLabel(newPhase)}');
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  // Marks one student Present or Absent in every saved session of this subject.
  // Returns how many sessions were changed.
  Future<int> _markStudentEverywhere(String roll, String status) async {
    final records = await loadDateRecords(sem, subjectName);
    for (final r in records) {
      // Not awaited: this never completes while offline. merge keeps the
      // other students and the session's meta fields untouched.
      unawaited(sem
          .dates(subjectName)
          .doc(r.id)
          .set({roll: status}, SetOptions(merge: true)).catchError((_) {}));
    }
    unawaited(LocalDb.setStudentStatusAll(sem, subjectName, roll, status));
    return records.length;
  }

  Widget _bulkMarkButton(String text, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }

  Future<void> _confirmBulkMark(BuildContext context, BuildContext sheetContext,
      Map<String, String> student, String status) async {
    final roll = student['roll'] ?? '';
    final name = student['name'] ?? '';
    final word = status == 'P' ? 'Present' : 'Absent';
    final ok = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mark all $word?'),
        content: Text(
            'Mark $name (Roll $roll) as $word in ALL past attendance records '
            'of $subjectName? This overwrites their existing marks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(word,
                style: TextStyle(
                    color: status == 'P' ? kPresent : kAbsent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await _markStudentEverywhere(roll, status);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    if (context.mounted) {
      showSnack(context,
          '$name marked $word in $n record${n == 1 ? '' : 's'}.');
    }
  }

  // Bottom sheet: pick a student, then tap P or A to mark them in every record.
  Future<void> _openStudentBulkSheet(BuildContext context) async {
    final students = await loadSubjectStudents(sem, subjectName);
    if (!context.mounted) return;
    if (students.isEmpty) {
      showSnack(context, 'No students found in this subject.', color: kAbsent);
      return;
    }
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final q = query.trim().toLowerCase();
          final list = q.isEmpty
              ? students
              : students
                  .where((s) =>
                      (s['name'] ?? '').toLowerCase().contains(q) ||
                      (s['roll'] ?? '').toLowerCase().contains(q))
                  .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                      child: Text(
                        'Mark a student in all past records',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Tap P (Present) or A (Absent) next to a student.',
                        style: TextStyle(color: kMuted, fontSize: 12.5),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: TextField(
                        onChanged: (v) => setSheetState(() => query = v),
                        decoration: const InputDecoration(
                          hintText: 'Search name or roll number',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(
                              child: Text('No student matches.',
                                  style: TextStyle(color: kMuted)))
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final s = list[i];
                                return ListTile(
                                  title: Text(s['name'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text('Roll: ${s['roll'] ?? ''}',
                                      style: const TextStyle(
                                          color: kMuted, fontSize: 12)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _bulkMarkButton(
                                          'P',
                                          kPresent,
                                          () => _confirmBulkMark(context,
                                              sheetContext, s, 'P')),
                                      const SizedBox(width: 8),
                                      _bulkMarkButton(
                                          'A',
                                          kAbsent,
                                          () => _confirmBulkMark(context,
                                              sheetContext, s, 'A')),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
        return _buildRecords(
            context, full || perms.edit, full || perms.edit, true, true);
      },
    );
  }

  Widget _buildRecords(BuildContext context, bool canEdit, bool canDelete,
      bool canChangeType, bool canChangePhase) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$subjectName - Records'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.how_to_reg_outlined),
              tooltip: 'Mark a student in all records',
              onPressed: () => _openStudentBulkSheet(context),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: liveQuery(sem.dates(subjectName)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return EmptyState(
              icon: Icons.event_busy,
              text: 'No attendance records found.',
              actionLabel: 'Mark attendance',
              // This screen is opened from the marking screen, so go back to it.
              onAction: () => Navigator.pop(context),
            );
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
              String dateText = docId; // shown on the card (date only)
              try {
                List<String> parts = docId.split('_Session_');
                parsedDate = DateFormat('yyyy-MM-dd').parse(parts[0]);
                parsedSession = int.parse(parts[1]);
                dateText = DateFormat('dd MMM yyyy').format(parsedDate);
                // Full label is still used in dialogs and messages.
                label = "$dateText - Session $parsedSession";
              } catch (e) {
                label = docId;
                dateText = docId;
              }

              final parsed = parseAttendance(doc.data());
              int presentCount = parsed.status.values.where((v) => v == 'P').length;
              int absentCount = parsed.status.values.where((v) => v == 'A').length;
              final time = fmtHhmm(parsed.meta['_time']);
              final by = parsed.meta['_marked_by_name'] ?? '';
              final isLab = parsed.meta['_type'] == kTypeLab;
              final isFinal = parsed.meta['_phase'] == kPhaseFinal;

              return AppCard(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                child: Column(
                  children: [
                  Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconBadge(icon: Icons.event_note, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(dateText,
                                  softWrap: false,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              // Session number badge, next to the date.
                              if (parsedSession != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'S$parsedSession',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                              // Session type chip: quick visual cue for Class vs Lab.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isLab ? kAccent : kPresent)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: (isLab ? kAccent : kPresent)
                                          .withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  typeLabel(isLab ? kTypeLab : kTypeClass),
                                  style: TextStyle(
                                      color: isLab ? kAccent : kPresent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              // Exam phase chip: Mid or Final.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isFinal ? kAccent2 : kMuted)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: (isFinal ? kAccent2 : kMuted)
                                          .withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  phaseLabel(isFinal ? kPhaseFinal : kPhaseMid),
                                  style: TextStyle(
                                      color: isFinal ? kAccent2 : kMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Present: $presentCount | Absent: $absentCount'
                            '${time.isEmpty ? '' : ' | $time'}'
                            '${by.isEmpty ? '' : ' | $by'}',
                            style: const TextStyle(color: kMuted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                  ),
                  const SizedBox(height: 4),
                  // Action buttons on their own row so the text gets full width.
                  Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (canChangeType)
                    IconButton(
                      // Shows what it will become: flask = Lab, class = Class.
                      icon: Icon(
                          isLab ? Icons.class_outlined : Icons.science_outlined,
                          color: kAccent),
                      tooltip:
                          isLab ? 'Change to Class' : 'Change to Lab Class',
                      onPressed: () => _confirmChangeType(context, docId, label,
                          isLab ? kTypeClass : kTypeLab),
                    ),
                    if (canChangePhase)
                    IconButton(
                      // Shows what it will become: trophy = Final, hourglass = Mid.
                      // Violet so it never looks like the Class / Lab button.
                      icon: Icon(
                          isFinal
                              ? Icons.hourglass_top_rounded
                              : Icons.emoji_events_outlined,
                          color: kViolet),
                      tooltip: isFinal ? 'Change to Mid' : 'Change to Final',
                      onPressed: () => _confirmChangePhase(context, docId, label,
                          isFinal ? kPhaseMid : kPhaseFinal),
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
                    // Red tint container makes the destructive action stand
                    // out from Edit / Change-type, which share a neutral accent.
                    Container(
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        color: kAbsent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kAbsent.withValues(alpha: 0.35)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: kAbsent),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(context, docId, label),
                      ),
                    ),
                  ],
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

// Student status card (shared by Subject Stats and Monthly Attendance).
// Compact and centered; text sits in a Column / Expanded so nothing overflows.
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
  final String father;
  final int present;
  final int absent;
  final int total;
  final List<StatEntry> entries;
  const StudentStatCard({
    super.key,
    required this.roll,
    required this.name,
    this.father = '',
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
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
      // Glass card (same look as the Records / list cards): soft translucent
      // fill + thin border, no strong gradient and no glow.
      decoration: BoxDecoration(
        color: good ? kGlass : kAbsent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: good ? kGlassBorder : kAbsent.withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
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
                    color: good ? Colors.white : const Color(0xFFFFB3C0),
                  ),
                ),
                if (w.father.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('S/O ${w.father.trim()}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kMuted, fontSize: 12.5)),
                ],
                const SizedBox(height: 2),
                Text('Roll No. ${rollOf(w.roll)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: good ? kBlueGrad : kRedGrad,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                    backgroundColor: const Color(0x33FFFFFF),
                    color: color,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _stat('${w.present}', 'Present', kPresent),
                    _stat('${w.absent}', 'Absent', kAbsent),
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
    father: student['father'] ?? '',
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

// Monthly attendance (admin and teacher): pick a month to see only that month's
// records. Read from local SQLite (works offline), refreshed first when online.
// ---- In-app attendance sheet viewer ----
// Shows the same table as the Excel file (Roll, Name, dates, totals), inside the
// app. Data comes from the same loaders as the export, so it also works offline
// (Firestore cache, then SQLite). If [month] is given, only that month is shown.
class AttendanceSheetScreen extends StatefulWidget {
  final SemRef sem;
  final String semLabel;
  final String subjectName;
  final DateTime? month;
  const AttendanceSheetScreen({
    super.key,
    required this.sem,
    required this.semLabel,
    required this.subjectName,
    this.month,
  });

  @override
  State<AttendanceSheetScreen> createState() => _AttendanceSheetScreenState();
}

class _AttendanceSheetScreenState extends State<AttendanceSheetScreen> {
  static const double _rowH = 40;
  static const double _headH = 64;
  // Only Roll + Name stay pinned on the left, so more session columns fit on
  // a phone. The Father column scrolls sideways with the table.
  static const double _rollW = 36;
  double _nameW = 110; // set from the screen width in build()
  static const double _fatherW = 110;
  static const double _cellW = 52;
  static const double _sumW = 56;

  bool _loading = true;
  bool _offline = false;
  List<Map<String, String>> _students = [];
  List<DateRecord> _all = [];
  String _scope = 'all'; // 'all', kTypeClass or kTypeLab
  String _phase = 'all'; // 'all' (Overall), kPhaseMid or kPhaseFinal
  bool _letters = true; // true: P / A, false: 1 / 0

  final ScrollController _headH1 = ScrollController();
  final ScrollController _bodyH = ScrollController();
  final ScrollController _leftV = ScrollController();
  final ScrollController _rightV = ScrollController();
  bool _syncingH = false;
  bool _syncingV = false;

  @override
  void initState() {
    super.initState();
    // Keep header and body in step when scrolling sideways.
    _bodyH.addListener(() {
      if (_syncingH || !_headH1.hasClients) return;
      _syncingH = true;
      _headH1.jumpTo(_bodyH.offset.clamp(0.0, _headH1.position.maxScrollExtent));
      _syncingH = false;
    });
    _headH1.addListener(() {
      if (_syncingH || !_bodyH.hasClients) return;
      _syncingH = true;
      _bodyH.jumpTo(_headH1.offset.clamp(0.0, _bodyH.position.maxScrollExtent));
      _syncingH = false;
    });
    // Keep the name column and the table in step when scrolling up and down.
    _rightV.addListener(() {
      if (_syncingV || !_leftV.hasClients) return;
      _syncingV = true;
      _leftV.jumpTo(_rightV.offset.clamp(0.0, _leftV.position.maxScrollExtent));
      _syncingV = false;
    });
    _leftV.addListener(() {
      if (_syncingV || !_rightV.hasClients) return;
      _syncingV = true;
      _rightV.jumpTo(_leftV.offset.clamp(0.0, _rightV.position.maxScrollExtent));
      _syncingV = false;
    });
    _load();
  }

  @override
  void dispose() {
    _headH1.dispose();
    _bodyH.dispose();
    _leftV.dispose();
    _rightV.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        loadSubjectStudents(widget.sem, widget.subjectName),
        loadDateRecords(widget.sem, widget.subjectName),
      ]);
      var offline = false;
      try {
        final c = await Connectivity().checkConnectivity();
        offline = c.every((e) => e == ConnectivityResult.none);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _students = r[0] as List<Map<String, String>>;
        _all = r[1] as List<DateRecord>;
        _offline = offline;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Sheet view load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, 'Could not load attendance: $e', color: kAbsent);
    }
  }

  List<DateRecord> get _records {
    var list = filterRecordsByScope(_all, _scope, phase: _phase);
    final m = widget.month;
    if (m != null) {
      final key = DateFormat('yyyy-MM').format(m);
      list = list.where((r) => r.id.startsWith(key)).toList();
    }
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  Widget _cell(String text, double w,
      {Color? color,
      FontWeight? weight,
      double size = 13,
      Color? bg,
      Alignment align = Alignment.center,
      double h = _rowH,
      EdgeInsets pad = EdgeInsets.zero}) {
    return Container(
      width: w,
      height: h,
      alignment: align,
      padding: pad,
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
          right: BorderSide(color: kOutline, width: 0.5),
          bottom: BorderSide(color: kOutline, width: 0.5),
        ),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: align == Alignment.centerLeft ? TextAlign.left : TextAlign.center,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GradPill(
        label: label,
        filled: selected,
        onTap: onTap,
        fontSize: 12.5,
      ),
    );
  }

  Widget _filters() {
    final classCount = _all.where((r) => !r.isLab).length;
    final labCount = _all.length - classCount;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          _chip('All', _scope == 'all', () => setState(() => _scope = 'all')),
          if (labCount > 0 && classCount > 0) ...[
            _chip('Class', _scope == kTypeClass,
                () => setState(() => _scope = kTypeClass)),
            _chip('Lab', _scope == kTypeLab,
                () => setState(() => _scope = kTypeLab)),
          ],
          const SizedBox(width: 8),
          _chip('Overall', _phase == 'all', () => setState(() => _phase = 'all')),
          _chip('Mid', _phase == kPhaseMid,
              () => setState(() => _phase = kPhaseMid)),
          _chip('Final', _phase == kPhaseFinal,
              () => setState(() => _phase = kPhaseFinal)),
          const SizedBox(width: 8),
          _chip('P / A', _letters, () => setState(() => _letters = true)),
          _chip('1 / 0', !_letters, () => setState(() => _letters = false)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthText =
        widget.month == null ? '' : ' - ${DateFormat('MMM yyyy').format(widget.month!)}';
    _nameW = (MediaQuery.of(context).size.width * 0.30).clamp(96.0, 150.0);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.subjectName}$monthText')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? const EmptyState(
                  icon: Icons.groups_outlined,
                  text: 'No students in this subject.')
              : _records.isEmpty
                  ? Column(
                      children: [
                        _filters(),
                        const Expanded(
                          child: EmptyState(
                              icon: Icons.event_busy,
                              text: 'No attendance recorded yet.'),
                        ),
                      ],
                    )
                  : _buildSheet(),
    );
  }

  Widget _buildSheet() {
    final recs = _records;
    final n = recs.length;

    // Week numbers, same rule as the Excel file (weeks start on Monday).
    DateTime mondayOf(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      return day.subtract(Duration(days: day.weekday - DateTime.monday));
    }

    final dates = [
      for (final r in recs) DateTime.tryParse(r.id.split('_Session_')[0])
    ];
    // Week numbers count from the first session of the whole subject.
    final allDates = [
      for (final r in _all) DateTime.tryParse(r.id.split('_Session_')[0])
    ].whereType<DateTime>().toList();
    DateTime? firstMonday;
    for (final d in allDates) {
      final m = mondayOf(d);
      if (firstMonday == null || m.isBefore(firstMonday)) firstMonday = m;
    }
    final weekOf = List<int>.filled(n, 1);
    for (int i = 0; i < n; i++) {
      final d = dates[i];
      if (d != null && firstMonday != null) {
        final md = mondayOf(d);
        weekOf[i] = DateTime.utc(md.year, md.month, md.day)
                    .difference(DateTime.utc(
                        firstMonday.year, firstMonday.month, firstMonday.day))
                    .inDays ~/
                7 +
            1;
      } else if (i > 0) {
        weekOf[i] = weekOf[i - 1];
      }
    }

    // ---- Header (pinned) ----
    final headBg = kAccent.withValues(alpha: 0.16);
    final headCells = <Widget>[];
    for (int i = 0; i < n; i++) {
      final d = dates[i];
      final label = d == null
          ? recs[i].id.split('_Session_')[0]
          : DateFormat('d MMM').format(d);
      headCells.add(Container(
        width: _cellW,
        height: _headH,
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: kOutline, width: 0.5),
            bottom: BorderSide(color: kOutline, width: 0.5),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Wk ${weekOf[i]}',
                style: const TextStyle(fontSize: 10.5, color: kMuted)),
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(recs[i].isLab ? 'Lab' : 'Class',
                style: TextStyle(
                    fontSize: 10.5,
                    color: recs[i].isLab ? kAccent2 : kMuted)),
          ],
        ),
      ));
    }
    headCells.insert(
        0,
        _cell('Father', _fatherW,
            weight: FontWeight.w700, size: 12, h: _headH, bg: headBg));
    headCells.addAll([
      _cell('Total', _sumW,
          weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
      _cell('Present', _sumW,
          weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
      _cell('%', _sumW,
          weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
    ]);

    // ---- Body rows ----
    final leftRows = <Widget>[];
    final rightRows = <Widget>[];
    for (int s = 0; s < _students.length; s++) {
      final st = _students[s];
      final roll = st['roll'] ?? '';
      final name = st['name'] ?? '';
      final father = (st['father'] ?? '').trim();
      final band = s.isOdd ? kGlass : null;
      int present = 0;
      final cells = <Widget>[];
      for (int i = 0; i < n; i++) {
        final isP = (recs[i].status[roll] ?? 'P') == 'P';
        if (isP) present++;
        cells.add(_cell(
          _letters ? (isP ? 'P' : 'A') : (isP ? '1' : '0'),
          _cellW,
          color: isP ? kPresent : kAbsent,
          weight: FontWeight.w600,
          bg: band,
        ));
      }
      final pct = n == 0 ? 0.0 : present / n * 100;
      cells.insert(
          0,
          _cell(father, _fatherW,
              bg: band,
              color: kMuted,
              size: 12,
              align: Alignment.centerLeft,
              pad: const EdgeInsets.symmetric(horizontal: 8)));
      cells.addAll([
        _cell('$n', _sumW, bg: band),
        _cell('$present', _sumW, bg: band),
        _cell(pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1), _sumW,
            color: pct >= 75 ? kPresent : kAbsent,
            weight: FontWeight.w700,
            bg: band),
      ]);
      leftRows.add(Row(children: [
        _cell(rollOf(roll), _rollW, bg: band, color: kMuted),
        _cell(name, _nameW,
            bg: band,
            size: 12.5,
            align: Alignment.centerLeft,
            pad: const EdgeInsets.symmetric(horizontal: 6)),
      ]));
      rightRows.add(Row(children: cells));
    }

    final rightWidth = _fatherW + _cellW * n + _sumW * 3;

    return Column(
      children: [
        if (_offline)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Offline - showing saved data',
                style: TextStyle(color: kMuted, fontSize: 12)),
          ),
        _filters(),
        // Pinned header row
        Row(
          children: [
            _cell('Roll', _rollW,
                weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
            _cell('Name', _nameW,
                weight: FontWeight.w700, size: 12, h: _headH, bg: headBg),
            Expanded(
              child: SingleChildScrollView(
                controller: _headH1,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: rightWidth,
                  child: Row(children: headCells),
                ),
              ),
            ),
          ],
        ),
        // Body: names stay on the left while the table scrolls sideways
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _rollW + _nameW,
                child: SingleChildScrollView(
                  controller: _leftV,
                  child: Column(children: leftRows),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _bodyH,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: rightWidth,
                    child: SingleChildScrollView(
                      controller: _rightV,
                      child: Column(children: rightRows),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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

  // ---- Excel export of the selected month (admin and teacher, every subject) ----
  bool _exporting = false;

  Future<void> _exportExcel() async {
    if (_exporting || _records.isEmpty || _students.isEmpty) return;
    final opt = await askExportOptions(context, _records);
    if (opt == null || !mounted) return;
    final recs = filterRecordsByScope(_records, opt.scope, phase: opt.phase)
      ..sort((a, b) => a.id.compareTo(b.id));
    if (recs.isEmpty) {
      showSnack(context, 'No ${optionsLabel(opt)} sessions in this month.',
          color: kAbsent);
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = buildAttendanceExcelBytes(
        info: await loadExcelInfo(widget.sem, widget.subjectName),
        recs: recs,
        students: _students,
        useLetters: opt.useLetters,
      );
      if (bytes == null) throw Exception('Excel file could not be created');

      // File name: Subject_Section_A_Semester_3_2026-10_[Class_|Lab_]Monthly_Report.xlsx
      final base =
          exportFileBase(widget.sem, widget.semLabel, widget.subjectName);
      final monthKey = DateFormat('yyyy-MM').format(_month);
      final fileName =
          '${base}_${monthKey}_${phaseFileTag(opt.phase)}${scopeFileTag(opt.scope)}Monthly_Report.xlsx';
      if (!mounted) return;
      if (kIsWeb) {
        await webShareOrDownload(context, bytes, fileName,
            text:
                '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} - ${DateFormat('MMMM yyyy').format(_month)} Attendance');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$fileName';
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        text:
            '${widget.subjectName} • Section ${widget.sem.section} • ${widget.semLabel} - ${DateFormat('MMMM yyyy').format(_month)} Attendance',
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
            tooltip: 'View month as sheet',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: _records.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceSheetScreen(
                          sem: widget.sem,
                          semLabel: widget.semLabel,
                          subjectName: widget.subjectName,
                          month: _month,
                        )
                      ),
                    ),
          ),
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
    );
  }
}
