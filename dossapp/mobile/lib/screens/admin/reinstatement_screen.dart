import 'dart:async';
import 'package:flutter/services.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/motion.dart';
import '../../utils/formatters.dart';
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

  // Which request is being answered right now, and how ('approve' or
  // 'decline'). Its buttons show a spinner and cannot be pressed twice.
  final Map<int, String> _busy = {};
  // Requests that were just answered and are folding away
  final Set<int> _leaving = {};
  // Only the newest load may write to the screen. A slow answer for a
  // filter the person has already left is dropped.
  int _loadSeq = 0;

  static const _patience = Duration(seconds: 20);

  Future<void> _load({bool silent = false}) async {
    silent = silent && _requests != null;
    final seq = ++_loadSeq;
    final filter = _filter;
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      // Never wait forever: after 20 seconds this becomes an error with
      // a Try again button
      final list = await ApiService.getReinstatementRequests(statusFilter: filter).timeout(_patience);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _requests = list;
        _leaving.clear();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  // One path for both answers. The card shows a spinner on the pressed
  // button, then folds away as soon as the server says yes (Doherty
  // Threshold: no full reload, no blank screen). The list is refreshed
  // quietly behind it. Whatever goes wrong, the buttons come back.
  Future<void> _answer(int requestId, {required bool approve, String? note}) async {
    if (_busy.containsKey(requestId)) return;
    final t = SS.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy[requestId] = approve ? 'approve' : 'decline');
    try {
      if (approve) {
        await ApiService.approveReinstatement(requestId).timeout(_patience);
      } else {
        await ApiService.declineReinstatement(requestId, adminNote: note).timeout(_patience);
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() { _busy.remove(requestId); _leaving.add(requestId); });
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(approve ? t.requestAccepted : t.requestRejected),
        backgroundColor: approve ? AppColors.success : null,
        duration: const Duration(seconds: 2),
      ));
      // Let the card finish folding, then drop it and sync with the server
      await Future.delayed(Motion.slow);
      if (!mounted) return;
      setState(() {
        _requests?.removeWhere((r) => r['id'] == requestId);
        _leaving.remove(requestId);
      });
      _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(requestId));
      // Another staff member got there first: not an error, just refresh
      final taken = e is ApiException && (e.statusCode == 409 || e.statusCode == 404);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(taken ? t.answeredAlready : AppError.messageFor(e))));
      if (taken) _load(silent: true);
    }
  }

  Future<void> _approve(int requestId) => _answer(requestId, approve: true);

  // Rejecting asks once, in a sheet within reach of the thumb. Keeping the
  // request is the quiet answer; rejecting is the red one.
  Future<void> _decline(int requestId) async {
    if (_busy.containsKey(requestId)) return;
    final t = SS.read(context);
    final noteController = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t.rejectRequestTitle,
                    style: GoogleFonts.barlow(fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.parentWillBeTold,
                    style: GoogleFonts.barlow(fontSize: 15, height: 1.4, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    maxLength: 300,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: t.noteToParentOptional,
                      hintText: t.noteToParentHint,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(t.reject),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        textStyle: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      child: Text(t.keepRequest),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final note = noteController.text.trim();
    await _answer(requestId, approve: false, note: note.isEmpty ? null : note);
  }

  // An answered card fades and folds shut, and the ones below slide up
  Widget _folding(int id, Widget card) {
    final leaving = _leaving.contains(id);
    return AnimatedSize(
      key: ValueKey<String>('req-$id'),
      duration: Motion.slow,
      curve: Motion.enter,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: leaving ? 0 : 1,
        child: leaving ? const SizedBox(width: double.infinity) : card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SS.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.requestsToReturn),
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
            // Loading, empty and the list replace each other with a soft fade
            child: FadeThrough(
              stateKey: '$_filter|${_loading ? 'loading' : _error != null ? 'error' : (_requests == null || _requests!.isEmpty) ? 'empty' : 'list'}',
              child: _loading
                  ? const SkeletonList(count: 3)
                  : _error != null
                      ? ErrorState(message: _error!, onRetry: _load)
                      : _requests == null || _requests!.isEmpty
                          ? EmptyState(
                              icon: Icons.check_circle_outline,
                              title: t.noRequests(_filter),
                              subtitle: _filter == 'pending' ? t.newRequestsShowHere : '',
                            )
                          : RefreshIndicator(
                              onRefresh: () => _load(silent: true),
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                itemCount: _requests!.length,
                                // Cards are tracked by request, not by row,
                                // so when one leaves the others slide up
                                // without replaying their entrance
                                findChildIndexCallback: (key) {
                                  if (key is! ValueKey<String>) return null;
                                  final i = _requests!.indexWhere((r) => 'req-${r['id']}' == key.value);
                                  return i < 0 ? null : i;
                                },
                                itemBuilder: (ctx, i) => _folding(
                                  _requests![i]['id'] as int,
                                  AnimatedListItem(index: i, child: _requestCard(_requests![i])),
                                ),
                              ),
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
        if (s && _filter != value) {
          HapticFeedback.selectionClick();
          setState(() { _filter = value; _requests = null; });
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
                    Text('${swimmerId(athleteNumber)} \u2022 $branchName', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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

          // The two answers, only while the request is waiting. Full
          // height targets (Fitts's Law); the pressed one shows a spinner
          // and both are locked until the server answers.
          if (status == 'pending') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _busy.containsKey(id) ? null : () => _decline(id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _busy[id] == 'decline'
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
                          : Text(t.reject),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy.containsKey(id) ? null : () => _approve(id),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        disabledBackgroundColor: AppColors.success.withValues(alpha: _busy[id] == 'approve' ? 1 : 0.4),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _busy[id] == 'approve'
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(t.accept),
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
