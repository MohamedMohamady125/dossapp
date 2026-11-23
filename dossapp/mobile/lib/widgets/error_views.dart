import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/app_error.dart';
import '../utils/theme.dart';

IconData _iconFor(ErrorKind kind) => switch (kind) {
      ErrorKind.offline => Icons.wifi_off_rounded,
      ErrorKind.timeout => Icons.hourglass_bottom_rounded,
      ErrorKind.server => Icons.cloud_off_rounded,
      ErrorKind.tooMany => Icons.timer_outlined,
      ErrorKind.signedOut => Icons.lock_outline_rounded,
      ErrorKind.notAllowed => Icons.block_rounded,
      ErrorKind.notFound => Icons.search_off_rounded,
      ErrorKind.rejected => Icons.info_outline_rounded,
      ErrorKind.unknown => Icons.error_outline_rounded,
    };

String _tryAgain() => AppLang.isArabic ? 'جرّب تاني' : 'Try again';

/// A whole screen or section could not load. Says what happened in plain
/// words, and offers the one thing that can help (Hick's Law: one button).
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  /// Extra way out under the retry button, for example "Log out".
  final Widget? secondary;

  const ErrorView({super.key, required this.error, this.onRetry, this.secondary});

  @override
  Widget build(BuildContext context) {
    final e = AppError.from(error);
    // Not the user's fault and not alarming: amber for connection trouble,
    // red only when something actually broke (colour is for status).
    final calm = e.kind == ErrorKind.offline || e.kind == ErrorKind.timeout || e.kind == ErrorKind.tooMany;
    final color = calm ? AppColors.warningDark : AppColors.error;
    final tint = calm ? AppColors.warningLight : AppColors.errorLight;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(_iconFor(e.kind), size: 36, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              e.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              e.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.textSecondary),
            ),
            if (onRetry != null && e.canRetry) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_tryAgain()),
                style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
              ),
            ],
            if (secondary != null) ...[const SizedBox(height: 8), secondary!],
          ],
        ),
      ),
    );
  }
}

/// An error inside a form or a sheet, under the field or above the button.
class InlineError extends StatelessWidget {
  final Object error;
  const InlineError(this.error, {super.key});

  @override
  Widget build(BuildContext context) {
    final e = error is String ? null : AppError.from(error);
    final text = e?.message ?? error as String;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(e == null ? Icons.error_outline_rounded : _iconFor(e.kind), size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35, color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

/// An action failed (a button press). One consistent strip at the bottom,
/// with the same words the full-screen error would use.
void showErrorSnack(BuildContext context, Object error, {VoidCallback? onRetry}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  showErrorSnackOn(messenger, error, onRetry: onRetry);
}

/// Same, for code that captured the messenger before an `await`.
void showErrorSnackOn(ScaffoldMessengerState messenger, Object error, {VoidCallback? onRetry}) {
  final e = error is String ? null : AppError.from(error);
  final text = e?.message ?? error as String;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Row(
        children: [
          Icon(e == null ? Icons.error_outline_rounded : _iconFor(e.kind), color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
      action: (onRetry != null && (e?.canRetry ?? true))
          ? SnackBarAction(label: _tryAgain(), onPressed: onRetry)
          : null,
    ));
}

/// A thin strip at the top of every screen while the phone is offline, so
/// old data on screen is never mistaken for current (Zeigarnik: the
/// unfinished state stays visible). Wrap the app's content with it once.
class OfflineBanner extends StatelessWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ApiService.offline,
      child: child,
      builder: (context, offline, child) {
        return Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: offline
                  ? Material(
                      color: AppColors.warningDark,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AppLang.isArabic
                                      ? 'مفيش إنترنت. اللي قدامك آخر حاجة اتحمّلت.'
                                      : 'No internet. You are seeing the last saved information.',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
              // The strip already covers the status bar area when shown
              child: offline ? MediaQuery.removePadding(context: context, removeTop: true, child: child!) : child!,
            ),
          ],
        );
      },
    );
  }
}

/// Replaces Flutter's grey or red box when one widget fails to draw, so a
/// bug in one card never takes the whole screen with it. Call once at start.
void installFriendlyErrorWidget() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      color: AppColors.surfaceVariant,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.textSecondary, size: 24),
          const SizedBox(height: 8),
          Text(
            AppLang.isArabic ? 'الجزء ده مش ظاهر دلوقتي' : 'This part cannot be shown right now',
            textAlign: TextAlign.center,
            textDirection: AppLang.isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, decoration: TextDecoration.none, fontWeight: FontWeight.w500),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 6),
            Text(
              details.exceptionAsString(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 11, color: AppColors.error, decoration: TextDecoration.none, fontWeight: FontWeight.w400),
            ),
          ],
        ],
      ),
    );
  };
}
