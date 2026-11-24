import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';
import '../utils/translations.dart';

/// Catches the slips people make typing an email on a phone, before the
/// server ever sees them (Postel's Law: accept messy input, fix it kindly).
class EmailCheck {
  // Real providers. A domain on this list is never "corrected".
  static const _known = [
    'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 'icloud.com',
    'live.com', 'msn.com', 'aol.com', 'me.com', 'mac.com', 'ymail.com',
    'mail.com', 'gmx.com', 'proton.me', 'protonmail.com', 'googlemail.com',
    'yahoo.co.uk', 'hotmail.co.uk', 'outlook.sa', 'windowslive.com',
  ];

  // Only these are offered as a correction: the ones people actually mean
  static const _targets = [
    'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 'icloud.com',
    'live.com',
  ];

  static final _shape = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}$');

  /// Spaces removed, Arabic comma and comma turned into a dot after the @.
  static String clean(String input) {
    var v = input.replaceAll(RegExp(r'\s'), '');
    final at = v.lastIndexOf('@');
    if (at > 0) {
      final domain = v.substring(at + 1).replaceAll(',', '.').replaceAll('،', '.');
      v = v.substring(0, at + 1) + domain;
    }
    while (v.endsWith('.')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  static bool looksLikeEmail(String input) => input.contains('@');

  static bool isValid(String input) => _shape.hasMatch(clean(input));

  /// The email the person most likely meant, or null when it looks fine.
  /// "name@gmail.comm" gives "name@gmail.com".
  static String? suggestion(String input) {
    final v = clean(input);
    final at = v.lastIndexOf('@');
    if (at <= 0 || at == v.length - 1) return null;
    final name = v.substring(0, at);
    final domain = v.substring(at + 1).toLowerCase();
    if (_known.contains(domain)) {
      // Only the cleaning changed something (a space, a comma, a last dot)
      return v == input ? null : v;
    }

    String? best;
    var bestDistance = 3;
    for (final target in _targets) {
      final d = _distance(domain, target);
      if (d < bestDistance) {
        bestDistance = d;
        best = target;
      }
    }
    // "gmail" with no ending at all
    if (best == null && !domain.contains('.')) {
      for (final target in _targets) {
        if (_distance(domain, target.split('.').first) <= 1) best = target;
      }
    }
    return best == null ? null : '$name@$best';
  }

  // Edit distance: how many single-letter slips separate two words
  static int _distance(String a, String b) {
    if (a == b) return 0;
    if ((a.length - b.length).abs() > 2) return 3;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var prevPrev = prev;
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
        // Two letters swapped ("gmial") counts as one slip
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
          final swapped = prevPrev[j - 2] + 1;
          if (swapped < cur[j]) cur[j] = swapped;
        }
      }
      prevPrev = prev;
      prev = cur;
    }
    return prev[b.length];
  }
}

/// A line under an email field: "Did you mean name@gmail.com?" One tap fixes
/// the field. Shows nothing when the email looks fine.
class EmailSuggestion extends StatelessWidget {
  final TextEditingController controller;

  const EmailSuggestion({super.key, required this.controller});

  // Isolates the email so it stays left to right inside Arabic text
  static String _ltr(String v) =>
      String.fromCharCode(0x2066) + v + String.fromCharCode(0x2069);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final fix = EmailCheck.suggestion(value.text);
        return AnimatedSize(
          duration: AppAnimation.fastDuration,
          alignment: Alignment.topCenter,
          child: fix == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      controller.value = TextEditingValue(
                        text: fix,
                        selection: TextSelection.collapsed(offset: fix.length),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: '${S.of(context).didYouMean} ',
                                children: [
                                  // Kept left to right inside Arabic text
                                  TextSpan(
                                    text: _ltr(fix),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(text: S.of(context).isArabic ? '؟' : '?'),
                                ],
                              ),
                              style: GoogleFonts.barlow(
                                fontSize: 14,
                                height: 1.3,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            S.of(context).useThis,
                            style: GoogleFonts.barlow(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
