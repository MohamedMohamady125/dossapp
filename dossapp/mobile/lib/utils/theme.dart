import '../widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ── Core Palette ──
  static const primary = Color(0xFF1A3A6B);
  static const primaryLight = Color(0xFF2D5FAA);
  static const primarySurface = Color(0xFFE8F0FE);

  // Navy is the only brand colour on screen. Orange is used for one thing:
  // a payment that is due. Aqua is kept for charts only.
  static const secondary = Color(0xFF0891B2);
  static const secondaryLight = Color(0xFFCFFAFE);
  static const accent = Color(0xFFF97316);
  static const accentLight = Color(0xFFFFF7ED);

  // Surfaces
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  static const surfaceVariant = Color(0xFFF1F5F9);
  static const surfaceElevated = Color(0xFFFAFBFC);

  // Borders
  static const border = Color(0xFFE2E8F0);
  static const borderLight = Color(0xFFF1F5F9);
  static const fieldBorder = Color(0xFFCBD5E1);

  // Text
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textMuted = Color(0xFF94A3B8);

  // Semantic
  static const success = Color(0xFF059669);
  static const successLight = Color(0xFFD1FAE5);
  static const error = Color(0xFFDC2626);
  static const errorLight = Color(0xFFFEE2E2);
  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFEF3C7);
  static const warningDark = Color(0xFF92400E);

  // Data visualization
  static const genderMale = Color(0xFF3B82F6);
  static const genderFemale = Color(0xFFEC4899);

  // Flat fills. They keep the gradient type so every screen that paints
  // with them went flat in one place.
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF1A3A6B), Color(0xFF1A3A6B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const accentGradient = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFF97316)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const successGradient = LinearGradient(
    colors: [Color(0xFF059669), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Standard animation curves and durations
class AppAnimation {
  static const fastDuration = Duration(milliseconds: 150);
  static const normalDuration = Duration(milliseconds: 250);
  static const slowDuration = Duration(milliseconds: 400);
  static const staggerDelay = Duration(milliseconds: 50);

  static const enterCurve = Motion.enter;
  static const exitCurve = Motion.exit;
  static const bounceCurve = Curves.easeOutCubic;
}

ThemeData appTheme() {
  final baseTextTheme = GoogleFonts.barlowTextTheme();
  final headlineTextTheme = GoogleFonts.barlowTextTheme();

  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.primary,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: baseTextTheme.copyWith(
      displayLarge: headlineTextTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.textPrimary,
      ),
      displayMedium: headlineTextTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.textPrimary,
      ),
      headlineLarge: headlineTextTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
      ),
      headlineMedium: headlineTextTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: AppColors.textPrimary),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
      bodySmall: baseTextTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      labelLarge: baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: baseTextTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
      labelSmall: baseTextTheme.labelSmall?.copyWith(color: AppColors.textMuted),
    ),
    // Navy bar with white text on every screen, the same navy as the login
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: GoogleFonts.barlow(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: AppColors.border),
        textStyle: GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    // White fields with a thin border, the same as the login
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hoverColor: Colors.transparent,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.fieldBorder),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      labelStyle: GoogleFonts.barlow(color: AppColors.textSecondary),
      floatingLabelStyle: GoogleFonts.barlow(color: AppColors.primary, fontWeight: FontWeight.w600),
      hintStyle: GoogleFonts.barlow(color: AppColors.textMuted),
      errorMaxLines: 2,
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 68,
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primary.withValues(alpha: 0.1),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.barlow(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary);
        }
        return GoogleFonts.barlow(fontSize: 12, color: AppColors.textMuted);
      }),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: SlideFadePageTransitionsBuilder(),
      },
    ),
  );
}
