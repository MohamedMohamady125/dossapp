import 'motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';
import '../utils/translations.dart';
import 'language_toggle.dart';

/// The shell of every first-run screen: a flat navy top with the crest, the
/// title and the language switch, and a white sheet under it for the task.
///
/// One shell for all of them, so they read as one app (Similarity), and the
/// brand navy is on screen from the first second without any gradient.
class BrandPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onCrestTap;

  /// Shows a back arrow before the crest when set.
  final VoidCallback? onBack;

  /// What goes on the white sheet. A Column may use a Spacer to push its
  /// last item to the bottom of the screen.
  final Widget child;

  const BrandPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onCrestTap,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final arabic = S.of(context).isArabic;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (onBack != null)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(end: 8),
                                    child: IconButton(
                                      onPressed: onBack,
                                      // This icon flips by itself in Arabic
                                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                                        minimumSize: const Size(44, 44),
                                      ),
                                    ),
                                  ),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onCrestTap,
                                  child: Container(
                                    width: onBack != null ? 44 : 64,
                                    height: onBack != null ? 44 : 64,
                                    padding: EdgeInsets.all(onBack != null ? 6 : 9),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                // Same corner on every first screen (Jakob's Law)
                                const LanguageToggle(),
                              ],
                            ),
                            const SizedBox(height: 24),
                            // Title and line change together when a step changes
                            FadeThrough(
                              stateKey: '$title|$subtitle',
                              duration: Motion.base,
                              alignment: AlignmentDirectional.topStart,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: GoogleFonts.barlow(
                                      fontSize: 30,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: arabic ? 0 : -0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    subtitle,
                                    style: GoogleFonts.barlow(
                                      fontSize: 15,
                                      height: 1.4,
                                      color: Colors.white.withValues(alpha: 0.82),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      // The sheet slides up into place once, like a card
                      // being laid on the table
                      child: Appear(
                        rise: 36,
                        child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 420),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ),
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
