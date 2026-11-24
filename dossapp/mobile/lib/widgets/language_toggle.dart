import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/locale_provider.dart';

/// The language switch shown on every first-run screen (login, first-time
/// setup, forgot password, change password, choose a swimmer).
///
/// One widget, same look and same corner everywhere (Jakob's Law), so a
/// parent who cannot read the current language always knows where to tap.
/// It names the language it switches TO, in that language. Switching only
/// changes the locale, so whatever was typed stays in the fields.
class LanguageToggle extends StatelessWidget {
  /// True on a white page: a quiet outlined pill instead of the white one
  /// made for the navy headers.
  final bool onLight;

  const LanguageToggle({super.key, this.onLight = false});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    if (onLight) {
      return Semantics(
        button: true,
        label: locale.isArabic ? 'Switch to English' : 'التحويل للعربية',
        child: InkWell(
          onTap: locale.toggleLanguage,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language_rounded, size: 16, color: Color(0xFF334155)),
                    const SizedBox(width: 6),
                    Text(
                      locale.isArabic ? 'English' : 'العربية',
                      style: GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: locale.isArabic ? 'Switch to English' : 'التحويل للعربية',
      child: InkWell(
        onTap: locale.toggleLanguage,
        borderRadius: BorderRadius.circular(22),
        child: ConstrainedBox(
          // At least 44px to tap (Fitts's Law), though the pill looks small
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Text(
                locale.isArabic ? 'EN' : 'عربي',
                style: GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
