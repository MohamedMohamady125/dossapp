import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_state.dart';

class CoachHomeScreen extends StatefulWidget {
  const CoachHomeScreen({super.key});

  @override
  State<CoachHomeScreen> createState() => _CoachHomeScreenState();
}

class _CoachHomeScreenState extends State<CoachHomeScreen> {
  Map<String, dynamic>? _schedule;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getCoachSchedule();
      setState(() {
        _schedule = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final coachName = _schedule?['coach_name'] as String?;
    final branchName = _schedule?['branch_name'] as String?;
    final sessions = (_schedule?['sessions'] as List?) ?? [];
    final totalSwimmers = sessions.fold<int>(0, (sum, s) {
      final swimmers = (s as Map<String, dynamic>)['swimmers'] as List?;
      return sum + (swimmers?.length ?? 0);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Schedule',
          style: GoogleFonts.barlowCondensed(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 22),
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: _buildBody(coachName, branchName, sessions, totalSwimmers),
    );
  }

  Widget _buildBody(String? coachName, String? branchName, List<dynamic> sessions, int totalSwimmers) {
    if (_loading) {
      return Column(
        children: [
          const SkeletonHero(),
          const Expanded(child: SkeletonList(count: 3)),
        ],
      );
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    if (sessions.isEmpty) {
      return Column(
        children: [
          _buildHeader(coachName, branchName, 0, 0),
          const Expanded(
            child: EmptyState(
              icon: Icons.event_busy_rounded,
              title: 'No sessions found',
              subtitle: 'Your schedule will appear here once sessions are assigned in the Excel sheet.',
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: sessions.length + 1, // +1 for header
        itemBuilder: (context, i) {
          if (i == 0) {
            return _buildHeader(coachName, branchName, sessions.length, totalSwimmers);
          }
          final session = sessions[i - 1] as Map<String, dynamic>;
          final swimmers = (session['swimmers'] as List?)?.cast<String>() ?? [];
          return AnimatedListItem(
            index: i - 1,
            child: _SessionCard(
              dayPair: session['day_pair'] as String?,
              timeBlock: session['time_block'] as String?,
              swimmers: swimmers,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(String? coachName, String? branchName, int sessionCount, int totalSwimmers) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(Icons.pool_rounded, color: Colors.white.withValues(alpha: 0.9), size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coachName != null ? 'Coach $coachName' : 'Coach',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (branchName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        branchName,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _headerStat(Icons.event_rounded, '$sessionCount', 'Sessions'),
              const SizedBox(width: 24),
              _headerStat(Icons.people_rounded, '$totalSwimmers', 'Swimmers'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.5), size: 18),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final String? dayPair;
  final String? timeBlock;
  final List<String> swimmers;

  const _SessionCard({this.dayPair, this.timeBlock, required this.swimmers});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left accent bar ──
          Container(
            width: 4,
            height: null,
            constraints: const BoxConstraints(minHeight: 80),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),

          // ── Content ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          dayPair ?? 'Unscheduled days',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_rounded, size: 14, color: AppColors.secondary),
                            const SizedBox(width: 4),
                            Text(
                              '${swimmers.length}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (timeBlock != null) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 32),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            timeBlock!,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 24),
                  ...swimmers.asMap().entries.map(
                    (entry) {
                      final name = entry.value;
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  initial,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
