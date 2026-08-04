import 'package:flutter/material.dart';
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

class _ReinstatementScreenState extends State<ReinstatementScreen> {
  List<Map<String, dynamic>>? _requests;
  bool _loading = true;
  String? _error;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _requests = await ApiService.getReinstatementRequests(statusFilter: _filter);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _approve(int requestId) async {
    try {
      await ApiService.approveReinstatement(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reinstatement approved'), backgroundColor: AppColors.success),
        );
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _decline(int requestId) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This will inform the athlete that their spot has been taken.'),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note to athlete (optional)',
                hintText: 'e.g., Your spot was given to another swimmer',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.declineReinstatement(requestId, adminNote: noteController.text.isNotEmpty ? noteController.text : null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request declined')),
        );
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Reinstatement Requests',
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
                _filterChip('Pending', 'pending'),
                const SizedBox(width: 8),
                _filterChip('Approved', 'approved'),
                const SizedBox(width: 8),
                _filterChip('Declined', 'declined'),
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
                            title: 'No $_filter requests',
                            subtitle: 'There are no $_filter reinstatement requests at the moment.',
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
    final id = req['id'] as int;
    final athleteName = req['athlete_name'] as String? ?? 'Unknown';
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
              _statChip(Icons.event_available, '$present/$total', 'Attendance', rate >= 50 ? AppColors.success : AppColors.error),
              const SizedBox(width: 8),
              _statChip(Icons.percent, '$rate%', 'Rate', rate >= 50 ? AppColors.success : AppColors.error),
              const SizedBox(width: 8),
              _statChip(
                paymentStatus == 'paid' ? Icons.check_circle : Icons.cancel,
                paymentStatus == 'paid' ? 'Paid' : 'Unpaid',
                'Payment',
                paymentStatus == 'paid' ? AppColors.success : AppColors.error,
              ),
              if (sessions != null) ...[
                const SizedBox(width: 8),
                _statChip(Icons.repeat, sessions, 'Sessions', AppColors.secondary),
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
              'Submitted: ${_formatDate(createdAt)}',
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
                    label: const Text('Decline'),
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
                    label: const Text('Approve'),
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
    final Color color;
    final String label;
    switch (status) {
      case 'approved':
        color = AppColors.success;
        label = 'Approved';
        break;
      case 'declined':
        color = AppColors.error;
        label = 'Declined';
        break;
      default:
        color = AppColors.warning;
        label = 'Pending';
    }
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

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
