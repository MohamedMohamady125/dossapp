import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/report.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/report_widgets.dart';

/// Staff screen: write/edit the monthly report for one athlete + see history.
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
  String? _error;

  late String _period;
  late List<String> _periodOptions;
  int _technique = 3;
  int _endurance = 3;
  int _commitment = 3;
  int _discipline = 3;
  final _notesCtrl = TextEditingController();
  final _goalsCtrl = TextEditingController();

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
    _goalsCtrl.dispose();
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
      if (isInitial) _error = e.toString();
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
    if (existing != null) {
      _technique = existing.technique;
      _endurance = existing.endurance;
      _commitment = existing.commitment;
      _discipline = existing.discipline;
      _notesCtrl.text = existing.coachNotes ?? '';
      _goalsCtrl.text = existing.goals ?? '';
    } else {
      _technique = 3;
      _endurance = 3;
      _commitment = 3;
      _discipline = 3;
      _notesCtrl.clear();
      _goalsCtrl.clear();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService.upsertReport(
        branchId: widget.branchId,
        athleteNumber: widget.athleteNumber,
        period: _period,
        technique: _technique,
        endurance: _endurance,
        commitment: _commitment,
        discipline: _discipline,
        coachNotes: _notesCtrl.text.trim(),
        goals: _goalsCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).reportSaved), backgroundColor: AppColors.success),
        );
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
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
        content: Text('${formatPeriod(report.period)} — ${widget.athleteName}'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
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
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
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
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '#${widget.athleteNumber}',
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
                      Text(formatPeriod(p), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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

        // ── Ratings ──
        RatingInput(label: S.of(context).technique, icon: Icons.pool_rounded, value: _technique, onChanged: (v) => setState(() => _technique = v)),
        RatingInput(label: S.of(context).endurance, icon: Icons.bolt_rounded, value: _endurance, onChanged: (v) => setState(() => _endurance = v)),
        RatingInput(label: S.of(context).commitment, icon: Icons.event_available_rounded, value: _commitment, onChanged: (v) => setState(() => _commitment = v)),
        RatingInput(label: S.of(context).discipline, icon: Icons.military_tech_rounded, value: _discipline, onChanged: (v) => setState(() => _discipline = v)),

        const SizedBox(height: 6),

        // ── Notes ──
        TextField(
          controller: _notesCtrl,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: s.coachNotes,
            alignLabelWithHint: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _goalsCtrl,
          maxLines: 3,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: s.nextMonthGoals,
            alignLabelWithHint: true,
            counterText: '',
          ),
        ),

        const SizedBox(height: 20),

        // ── Save ──
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(isEdit ? Icons.save_rounded : Icons.send_rounded),
          label: Text(_saving ? '...' : (isEdit ? s.editReport : s.saveReport)),
        ),

        // ── Existing report for selected period (preview + delete) ──
        if (_existingForPeriod != null) ...[
          const SizedBox(height: 24),
          _sectionLabel(formatPeriod(_period)),
          ReportCard(
            report: _existingForPeriod!,
            onDelete: () => _deleteReport(_existingForPeriod!),
          ),
        ],

        // ── History ──
        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionLabel(s.reports),
          ...history.map((r) => ReportCard(report: r, onDelete: () => _deleteReport(r))),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1),
      ),
    );
  }
}
