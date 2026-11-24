import '../../utils/formatters.dart';
import '../../utils/app_error.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../utils/translations_staff.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/report.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/report_widgets.dart';
import '../../widgets/ui_kit.dart';

/// Staff screen: send the monthly report for one athlete (a PDF or a note)
/// and see what was sent before.
class ReportEditorScreen extends StatefulWidget {
  final int branchId;
  final int athleteNumber;
  final String athleteName;

  const ReportEditorScreen({
    super.key,
    required this.branchId,
    required this.athleteNumber,
    required this.athleteName,
  });

  @override
  State<ReportEditorScreen> createState() => _ReportEditorScreenState();
}

class _ReportEditorScreenState extends State<ReportEditorScreen> {
  List<MonthlyReport>? _history;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  late String _period;
  late List<String> _periodOptions;
  // Two ways to report, because classes differ: some hand out a PDF, others
  // only need a few lines (Hick's Law: two clear choices, nothing else).
  bool _pdfMode = true;
  PlatformFile? _pdf;
  final _notesCtrl = TextEditingController();

  static const _maxPdfBytes = 10 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periodOptions = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
    _period = _periodOptions.first;
    _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Skeleton only on first load — after saving we refresh silently so the
    // screen doesn't flash and lose scroll position.
    final isInitial = _history == null;
    setState(() { if (isInitial) _loading = true; _error = null; });
    try {
      final fresh = await ApiService.getAthleteReports(widget.branchId, widget.athleteNumber);
      _history = fresh;
      if (isInitial) _applyExisting();
    } catch (e) {
      if (isInitial) _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  MonthlyReport? get _existingForPeriod {
    try {
      return _history?.firstWhere((r) => r.period == _period);
    } catch (_) {
      return null;
    }
  }

  void _applyExisting() {
    final existing = _existingForPeriod;
    _pdf = null;
    _notesCtrl.text = existing?.note ?? '';
    // Open on the kind that was sent last time for this month
    if (existing != null) _pdfMode = existing.hasPdf;
  }

  bool get _canSend => _pdfMode ? _pdf != null : _notesCtrl.text.trim().isNotEmpty;

  Future<void> _pickPdf() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      final file = result?.files.single;
      if (file == null || file.bytes == null) return;
      if (file.size > _maxPdfBytes) {
        messenger.showSnackBar(SnackBar(content: Text(s.pdfTooLarge), backgroundColor: AppColors.error));
        return;
      }
      if (mounted) setState(() => _pdf = file);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AppError.messageFor(e)), backgroundColor: AppColors.error));
    }
  }

  Future<void> _save() async {
    final s = S.of(context);
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final note = _notesCtrl.text.trim();
      if (_pdfMode) {
        await ApiService.uploadReportPdf(
          branchId: widget.branchId,
          athleteNumber: widget.athleteNumber,
          period: _period,
          bytes: _pdf!.bytes!,
          filename: _pdf!.name,
          note: note,
        );
      } else {
        await ApiService.sendReportNote(
          branchId: widget.branchId,
          athleteNumber: widget.athleteNumber,
          period: _period,
          note: note,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.reportSent), backgroundColor: AppColors.success),
        );
        await _load();
        if (mounted) setState(() => _pdf = null);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppError.messageFor(e)), backgroundColor: AppColors.error));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _deleteReport(MonthlyReport report) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.delete, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text('${SS.read(context).period(report.period)}\n${widget.athleteName}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.close)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, minimumSize: const Size(0, 44)),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deleteReport(report.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppError.messageFor(e)), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.monthlyReport)),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(S s) {
    if (_loading) return const SkeletonList(count: 4);
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final isEdit = _existingForPeriod != null;
    final history = (_history ?? []).where((r) => r.period != _period).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Athlete header ──
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    widget.athleteName.isNotEmpty ? widget.athleteName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.athleteName,
                      style: GoogleFonts.barlow(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      swimmerId(widget.athleteNumber),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Period selector ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _period,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
              items: _periodOptions.map((p) {
                final hasReport = _history?.any((r) => r.period == p) ?? false;
                return DropdownMenuItem(
                  value: p,
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(SS.of(context).period(p), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (hasReport)
                        const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _period = v;
                  _applyExisting();
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── PDF or note ──
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: Text(s.uploadPdf)),
              ButtonSegment(value: false, icon: const Icon(Icons.sticky_note_2_rounded, size: 18), label: Text(s.writeNote)),
            ],
            selected: {_pdfMode},
            onSelectionChanged: (v) => setState(() => _pdfMode = v.first),
          ),
        ),
        const SizedBox(height: 12),

        if (_pdfMode) ...[
          _pdfPicker(s),
          const SizedBox(height: 12),
        ],

        TextField(
          controller: _notesCtrl,
          minLines: _pdfMode ? 2 : 5,
          maxLines: 10,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _pdfMode ? s.optionalNote : s.noteHint,
            alignLabelWithHint: true,
            counterText: '',
          ),
        ),

        const SizedBox(height: 16),

        // ── Send: the one filled action (Von Restorff) ──
        FilledButton.icon(
          onPressed: (_saving || !_canSend) ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded),
          label: Text(isEdit ? s.replaceReport : s.sendReport),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_active_outlined, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(s.parentNotified, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
          ],
        ),

        // ── Existing report for selected period (preview + delete) ──
        if (_existingForPeriod != null) ...[
          const SizedBox(height: 24),
          SectionTitle(s.alreadySent),
          ReportCard(
            staff: true,
            report: _existingForPeriod!,
            onDelete: () => _deleteReport(_existingForPeriod!),
          ),
        ],

        // ── History ──
        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionTitle(s.reports),
          ...history.map((r) => ReportCard(staff: true, report: r, onDelete: () => _deleteReport(r))),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  // A large drop target: empty it invites the pick, filled it shows the file.
  Widget _pdfPicker(S s) {
    final file = _pdf;
    final existing = _existingForPeriod;
    final sentName = (existing != null && existing.hasPdf) ? existing.pdfFilename : null;
    return Material(
      color: file != null ? AppColors.primarySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: file != null ? AppColors.primary : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _saving ? null : _pickPdf,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconBadge(
                file != null ? Icons.picture_as_pdf_rounded : Icons.upload_file_rounded,
                size: 48,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file?.name ?? s.choosePdf,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      file != null
                          ? SS.of(context).megabytes((file.size / 1024 / 1024).toStringAsFixed(1))
                          : sentName != null
                              ? '${s.alreadySent}: $sentName'
                              : SS.of(context).pdfUpTo10Mb,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (file != null)
                Text(s.changePdf, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary))
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
