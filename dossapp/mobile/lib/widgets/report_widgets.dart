import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/report.dart';
import '../utils/theme.dart';
import '../utils/translations.dart';
import '../utils/formatters.dart';

/// Color for a 1-5 score.
Color scoreColor(double score) {
  if (score >= 4.5) return AppColors.success;
  if (score >= 3.5) return AppColors.secondary;
  if (score >= 2.5) return AppColors.warning;
  return AppColors.error;
}

/// Row of 5 water drops showing a rating (display only).
class RatingDrops extends StatelessWidget {
  final int value;
  final double size;
  final Color? color;

  const RatingDrops({super.key, required this.value, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? scoreColor(value.toDouble());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < value;
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            filled ? Icons.water_drop_rounded : Icons.water_drop_outlined,
            size: size,
            color: filled ? c : AppColors.border,
          ),
        );
      }),
    );
  }
}

/// Tappable rating row used in the editor.
class RatingInput extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  const RatingInput({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = scoreColor(value.toDouble());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          Row(
            children: List.generate(5, (i) {
              final filled = i < value;
              return GestureDetector(
                onTap: () => onChanged(i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                  child: AnimatedScale(
                    scale: filled ? 1.0 : 0.85,
                    duration: AppAnimation.fastDuration,
                    child: Icon(
                      filled ? Icons.water_drop_rounded : Icons.water_drop_outlined,
                      size: 26,
                      color: filled ? c : AppColors.textMuted,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Full report display card (athlete view + staff history).
class ReportCard extends StatelessWidget {
  final MonthlyReport report;
  final VoidCallback? onDelete;

  const ReportCard({super.key, required this.report, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final overall = report.overall;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: month + overall ring ──
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatPeriod(report.period),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.reportBy} ${report.createdByName}',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                // Overall score ring
                SizedBox(
                  width: 58,
                  height: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 58,
                        height: 58,
                        child: CircularProgressIndicator(
                          value: overall / 5.0,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            overall.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '/5',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline_rounded, color: Colors.white.withValues(alpha: 0.8), size: 20),
                  ),
              ],
            ),
          ),

          // ── Ratings ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Column(
              children: [
                _ratingRow(s.technique, Icons.pool_rounded, report.technique),
                _ratingRow(s.endurance, Icons.bolt_rounded, report.endurance),
                _ratingRow(s.commitment, Icons.event_available_rounded, report.commitment),
                _ratingRow(s.discipline, Icons.military_tech_rounded, report.discipline),
              ],
            ),
          ),

          // ── Notes & goals ──
          if (report.coachNotes != null && report.coachNotes!.trim().isNotEmpty)
            _noteBlock(
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: AppColors.secondary,
              bg: AppColors.secondaryLight.withValues(alpha: 0.4),
              title: s.coachNotes,
              text: report.coachNotes!.trim(),
            ),
          if (report.goals != null && report.goals!.trim().isNotEmpty)
            _noteBlock(
              icon: Icons.flag_rounded,
              iconColor: AppColors.accent,
              bg: AppColors.accentLight,
              title: s.nextMonthGoals,
              text: report.goals!.trim(),
            ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _ratingRow(String label, IconData icon, int value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
          ),
          RatingDrops(value: value),
        ],
      ),
    );
  }

  Widget _noteBlock({
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required String title,
    required String text,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: iconColor, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
        ],
      ),
    );
  }
}
