import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/report.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_state.dart';
import 'report_editor_screen.dart';

/// Staff screen: list swimmers with monthly-report status, tap to write/edit.
/// Coaches see only their own swimmers; admins pass a branchId.
class StaffReportsScreen extends StatefulWidget {
  final int? branchId;
  const StaffReportsScreen({super.key, this.branchId});

  @override
  State<StaffReportsScreen> createState() => _StaffReportsScreenState();
}

class _StaffReportsScreenState extends State<StaffReportsScreen> {
  int? _branchId;
  String? _branchName;
  String? _currentPeriod;
  List<ReportSwimmer>? _swimmers;
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Skeleton only on first load — silent refresh afterwards keeps scroll.
    final isInitial = _swimmers == null;
    setState(() { if (isInitial) _loading = true; _error = null; });
    try {
      final data = await ApiService.getReportSwimmers(branchId: widget.branchId);
      _branchId = data['branch_id'];
      _branchName = data['branch_name'];
      _currentPeriod = data['current_period'];
      _swimmers = (data['swimmers'] as List).map((x) => ReportSwimmer.fromJson(x)).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  List<ReportSwimmer> get _filtered {
    final list = _swimmers ?? [];
    if (_search.isEmpty) return list;
    final q = _search.toLowerCase();
    return list.where((sw) => sw.name.toLowerCase().contains(q) || sw.athleteNumber.toString().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.monthlyReports)),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(S s) {
    if (_loading) return const SkeletonList(count: 6, hasAvatar: true);
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final list = _filtered;
    final reportedCount = (_swimmers ?? []).where((sw) => sw.hasCurrentReport).length;
    final total = _swimmers?.length ?? 0;

    return Column(
      children: [
        // ── Progress header ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentPeriod != null ? formatPeriod(_currentPeriod!) : '',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (_branchName != null)
                          Text(_branchName!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(
                    '$reportedCount / $total',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total > 0 ? reportedCount / total : 0,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ],
          ),
        ),

        // ── Search ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: '${s.swimmers}...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),

        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: s.noData,
                  subtitle: '',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final sw = list[i];
                      return AnimatedListItem(
                        index: i,
                        child: _swimmerTile(sw, s),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _swimmerTile(ReportSwimmer sw, S s) {
    final done = sw.hasCurrentReport;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: done ? AppColors.success.withValues(alpha: 0.3) : AppColors.border),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          backgroundColor: done ? AppColors.successLight : AppColors.surfaceVariant,
          child: done
              ? const Icon(Icons.check_rounded, color: AppColors.success, size: 20)
              : Text(
                  sw.name.isNotEmpty ? sw.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
        ),
        title: Text(sw.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('#${sw.athleteNumber}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: done ? AppColors.successLight : AppColors.warningLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            done ? s.reported : s.notReported,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: done ? AppColors.success : AppColors.warningDark,
            ),
          ),
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportEditorScreen(
                branchId: _branchId!,
                athleteNumber: sw.athleteNumber,
                athleteName: sw.name,
              ),
            ),
          );
          _load();
        },
      ),
    );
  }
}
