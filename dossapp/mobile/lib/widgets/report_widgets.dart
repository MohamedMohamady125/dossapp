import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/report.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../utils/translations.dart';
import '../utils/formatters.dart';
import 'ui_kit.dart';

/// Downloads a report's PDF and hands it to the system sheet (open, save,
/// share), the same way receipts work (Jakob's Law: one pattern for PDFs).
Future<void> openReportPdf(BuildContext context, MonthlyReport report, {required bool staff}) async {
  final messenger = ScaffoldMessenger.of(context);
  final origin = shareOrigin(context); // iPad needs an anchor for the share sheet
  try {
    final bytes = await ApiService.downloadReportPdf(report.id, staff: staff);
    final dir = await getTemporaryDirectory();
    final name = report.pdfFilename ?? 'report_${report.period}.pdf';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], sharePositionOrigin: origin),
    );
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the PDF: $e')));
  }
}

/// One month's report: the note, the PDF, or both.
class ReportCard extends StatefulWidget {
  final MonthlyReport report;
  final VoidCallback? onDelete;

  /// True on staff screens: picks the staff PDF endpoint.
  final bool staff;

  const ReportCard({super.key, required this.report, this.onDelete, this.staff = false});

  @override
  State<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<ReportCard> {
  bool _opening = false;

  Future<void> _open() async {
    setState(() => _opening = true);
    await openReportPdf(context, widget.report, staff: widget.staff);
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final report = widget.report;
    final note = report.note;

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
          // ── Header: month and who sent it ──
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 14),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    report.hasPdf ? Icons.picture_as_pdf_rounded : Icons.sticky_note_2_rounded,
                    color: Colors.white, size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatPeriod(report.period),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${s.reportBy} ${report.createdByName}',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                ),
                if (widget.onDelete != null)
                  IconButton(
                    onPressed: widget.onDelete,
                    tooltip: s.delete,
                    icon: Icon(Icons.delete_outline_rounded, color: Colors.white.withValues(alpha: 0.85), size: 22),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),

          // ── Note ──
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.noteFromCoach,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(note, style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.5)),
                ],
              ),
            ),

          // ── PDF: a full-width row, 56px tall (Fitts's Law) ──
          if (report.hasPdf)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Material(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _opening ? null : _open,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const IconBadge(Icons.picture_as_pdf_rounded, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            report.pdfFilename ?? s.pdfReport,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_opening)
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary))
                        else
                          Text(s.openPdf, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}
