import '../../utils/app_error.dart';
import '../../services/app_refresh.dart';
import 'package:flutter/material.dart';
import '../../utils/translations_staff.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';

class ReinstatementScreen extends StatefulWidget {
  const ReinstatementScreen({super.key});

  @override
  State<ReinstatementScreen> createState() => _ReinstatementScreenState();
}

class _ReinstatementScreenState extends State<ReinstatementScreen> with AutoRefresh {
  @override
  Future<void> silentReload() => _load(silent: true);

  // Refreshes on changes and when reopened; no timer needed here
  @override
  Duration? get refreshEvery => null;

  List<Map<String, dynamic>>? _requests;
  bool _loading = true;
  Object? _error;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    silent = silent && _requests != null;
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      _requests = await ApiService.getReinstatementRequests(statusFilter: _filter);
      _error = null;
    } catch (e) {
      if (!silent) _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _approve(int requestId) async {
    final t = SS.read(context);
    try {
      await ApiService.approveReinstatement(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.requestAccepted), backgroundColor: AppColors.success),
        );
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppError.messageFor(e))));
      }
    }
  }

  Future<void> _decline(int requestId) async {
    final t = SS.read(context);
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.rejectRequestTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.parentWillBeTold),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: t.noteToParentOptional,
                hintText: t.noteToParentHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: Text(t.reject),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.declineReinstatement(requestId, adminNote: noteController.text.isNotEmpty ? noteController.text : null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.requestRejected)),
        );
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppError.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SS.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.requestsToReturn,
          style: GoogleFonts.barlowCondensed(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                _filterChip(t.statusWaiting, 'pending'),
                const SizedBox(width: 8),
                _filterChip(t.statusAccepted, 'approved'),
                const SizedBox(width: 8),
                _filterChip(t.statusRejected, 'declined'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: SkeletonList(count: 3))
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _requests == null || _requests!.isEmpty
                        ? EmptyState(
                            icon: Icons.check_circle_outline,
                            title: t.noRequests(_filter),
                            subtitle: _filter == 'pending' ? t.newRequestsShowHere : '',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _requests!.length,
                              itemBuilder: (ctx, i) => _requestCard(_requests![i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (s) {
        if (s) {
          setState(() => _filter = value);
          _load();
        }
      },
      selectedColor: AppColors.primarySurface,
      checkmarkColor: AppColors.primary,
    );
  }

  Widget _requestCard(Map<String, dynamic> req) {
    final t = SS.of(context);
    final id = req['id'] as int;
    final athleteName = req['athlete_name'] as String? ?? t.swimmer;
    final athleteNumber = req['athlete_number'] as int? ?? 0;
    final branchName = req['branch_name'] as String? ?? '';
    final status = req['status'] as String? ?? 'pending';
    final message = req['message'] as String?;
    final createdAt = req['created_at'] as String?;
    final sessions = req['sessions'] as String?;
    final isPaid = req['is_paid'] == true;
    final paymentStatus = isPaid ? 'paid' : 'unpaid';
    final attendance = req['attendance'] as Map<String, dynamic>?;

    // Compute attendance stats
    int present = 0, absent = 0;
    if (attendance != null) {
      for (final v in attendance.values) {
        if (v == 'P') present++;
        if (v == 'A') absent++;
      }
    }
    final total = present + absent;
    final rate = total > 0 ? (present / total * 100).round() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: name + number
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    athleteName.isNotEmpty ? athleteName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(athleteName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('#$athleteNumber \u2022 $branchName', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              _statusBadge(status),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Stats row
          Row(
            children: [
              _statChip(Icons.event_available, '$present/$total', t.attendance, rate >= 50 ? AppColors.success : AppColors.error),
              const SizedBox(width: 8),
              _statChip(Icons.percent, '$rate%', t.percent, rate >= 50 ? AppColors.success : AppColors.error),
              const SizedBox(width: 8),
              _statChip(
                paymentStatus == 'paid' ? Icons.check_circle : Icons.cancel,
                paymentStatus == 'paid' ? t.paid : t.notPaid,
                t.payment,
                paymentStatus == 'paid' ? AppColors.success : AppColors.error,
              ),
              if (sessions != null) ...[
                const SizedBox(width: 8),
                _statChip(Icons.repeat, sessions, t.sessionsShort, AppColors.secondary),
              ],
            ],
          ),

          // Message from athlete
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
                  ),
                ],
              ),
            ),
          ],

          if (createdAt != null) ...[
            const SizedBox(height: 8),
            Text(
              t.sentOn(t.dateTime(createdAt)),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],

          // Action buttons (only for pending)
          if (status == 'pending') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _decline(id),
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(t.reject),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approve(id),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(t.accept),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final label = SS.of(context).requestStatus(status);
    final color = switch (status) {
      'approved' => AppColors.success,
      'declined' => AppColors.error,
      _ => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color), textAlign: TextAlign.center),
            Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
