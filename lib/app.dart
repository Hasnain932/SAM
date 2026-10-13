part of 'main.dart';

// The root app widget: theme and first screen.

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
