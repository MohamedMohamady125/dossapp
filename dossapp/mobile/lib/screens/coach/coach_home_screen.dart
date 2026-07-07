import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Schedule'),
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
        bottom: coachName != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text(
                    'Coach $coachName \u2022 ${branchName ?? ''}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final sessions = (_schedule?['sessions'] as List?) ?? [];
    if (sessions.isEmpty) {
      return const Center(
        child: Text(
          'No sessions found in your schedule.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sessions.length,
        itemBuilder: (context, i) {
          final session = sessions[i] as Map<String, dynamic>;
          final swimmers = (session['swimmers'] as List?)?.cast<String>() ?? [];
          return _SessionCard(
            dayPair: session['day_pair'] as String?,
            timeBlock: session['time_block'] as String?,
            swimmers: swimmers,
          );
        },
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dayPair ?? 'Unscheduled days',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${swimmers.length}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            if (timeBlock != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  timeBlock!,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
              ),
            ],
            const Divider(height: 24),
            ...swimmers.map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.pool_outlined, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
