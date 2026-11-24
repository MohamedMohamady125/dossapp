import '../../utils/app_error.dart';
import '../../services/app_refresh.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../utils/translations_staff.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/ui_kit.dart';

class PaymentsScreen extends StatefulWidget {
  final int branchId;
  const PaymentsScreen({super.key, required this.branchId});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with SingleTickerProviderStateMixin, AutoRefresh {
  @override
  Future<void> silentReload() => _load(silent: true);

  List<Map<String, dynamic>>? _payments;
  bool _loading = true;
  Object? _error;
  String _statusFilter = 'paid';
  String _search = '';
  Timer? _searchDebounce;
  late AnimationController _animController;

  String? _period;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    silent = silent && _payments != null;
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      _payments = await ApiService.getBranchPayments(
        widget.branchId,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );
      // Derive period from first payment or fallback to current month
      if (_payments != null && _payments!.isNotEmpty) {
        _period = _payments!.first['period']?.toString();
      }
      _period ??= DateTime.now().toString().substring(0, 7);
      _error = null;
      if (!silent) _animController.forward(from: 0);
    } catch (e) {
      if (!silent) _error = e;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_payments == null) return [];
    if (_search.isEmpty) return _payments!;
    final q = _search.toLowerCase();
    return _payments!.where((p) =>
      (p['athlete_name'] ?? '').toString().toLowerCase().contains(q) ||
      (p['athlete_number'] ?? '').toString().contains(q) ||
      (p['amount_paid'] ?? '').toString().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = SS.of(context);
    final list = _filtered;

    // Compute summary
    double totalCollected = 0;
    int paidCount = 0;
    if (_payments != null) {
      for (final p in _payments!) {
        if (p['status'] == 'paid') {
          paidCount++;
          totalCollected += num.tryParse(p['amount_paid']?.toString() ?? '0')?.toDouble() ?? 0;
        }
      }
    }

    return Column(
      children: [
        // ── Summary: one headline number on a plain surface ──
        if (!_loading && _payments != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.savings_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.collectedIn(t.period(_period ?? '')),
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(t.money(totalCollected), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                  child: Text(t.paidCount(paidCount), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

        // ── Search + Filter ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: t.searchByNameOrNumber,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                      if (mounted) setState(() => _search = v);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _statusFilter.isEmpty ? AppColors.surfaceVariant : AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.filter_list, size: 22, color: _statusFilter.isEmpty ? AppColors.textSecondary : AppColors.primary),
                  tooltip: t.filter,
                  position: PopupMenuPosition.under,
                  onSelected: (v) { _statusFilter = v; _load(); },
                  itemBuilder: (ctx) => [
                    _filterItem('', t.all, Icons.list),
                    _filterItem('paid', t.paid, Icons.check_circle_outline),
                    _filterItem('pending', t.notFinished, Icons.pending_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── List ──
        if (_loading)
          const Expanded(child: SkeletonList(count: 5, hasAvatar: true))
        else if (_error != null)
          Expanded(child: ErrorState(message: _error!, onRetry: _load))
        else if (list.isEmpty)
          Expanded(
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: _search.isNotEmpty ? t.nothingFoundFor(_search) : t.noPaymentsThisMonth,
              subtitle: _search.isNotEmpty ? t.tryAnotherSearch : t.paymentsShowAfterPay,
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
                itemBuilder: (ctx, i) {
                  final delay = (i * 0.05).clamp(0.0, 0.5);
                  return AnimatedBuilder(
                    animation: _animController,
                    builder: (ctx, child) {
                      final value = Curves.easeOut.transform(
                        ((_animController.value - delay) / (1 - delay)).clamp(0.0, 1.0),
                      );
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: _paymentCard(list[i]),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  PopupMenuItem<String> _filterItem(String value, String label, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 18, color: _statusFilter == value ? AppColors.primary : AppColors.textMuted),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontWeight: _statusFilter == value ? FontWeight.w600 : FontWeight.w400)),
      ]),
    );
  }

  // Receipts being emailed right now, and the ones already sent this visit
  final Set<int> _emailing = {};
  final Set<int> _emailed = {};

  // One tap: the receipt goes to the email on the swimmer's own account
  Future<void> _emailReceipt(int receiptId) async {
    if (_emailing.contains(receiptId)) return;
    final t = SS.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _emailing.add(receiptId));
    try {
      final email = await ApiService.adminEmailReceipt(receiptId);
      if (!mounted) return;
      setState(() { _emailing.remove(receiptId); _emailed.add(receiptId); });
      messenger.showSnackBar(SnackBar(content: Text(t.receiptEmailedTo(email))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _emailing.remove(receiptId));
      messenger.showSnackBar(SnackBar(content: Text(AppError.messageFor(e))));
    }
  }

  Future<void> _downloadReceipt(int receiptId, String receiptNumber) async {
    final t = SS.read(context);
    final origin = shareOrigin(context); // iPad needs an anchor for the share sheet
    try {
      final pdfBytes = await ApiService.adminDownloadReceiptPdf(receiptId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt_$receiptNumber.pdf');
      await file.writeAsBytes(pdfBytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], sharePositionOrigin: origin),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.receiptDownloadFailed)));
      }
    }
  }

  // Name and amount on the first line; class and payment facts as two quiet
  // lines beneath. "Paid" is the normal state here so it gets no badge; only
  // a payment that is not yet paid is flagged (Von Restorff).
  Widget _paymentCard(Map<String, dynamic> p) {
    final t = SS.of(context);
    final isPaid = p['status'] == 'paid';
    final name = p['athlete_name'] ?? t.swimmerNumber(p['athlete_number']);
    final level = (p['level'] ?? '') as String;
    final type = (p['athlete_type'] ?? '') as String;
    final coach = p['coach'] as String?;
    final trainingTime = p['training_time'] as String?;
    final channel = p['payment_channel'] as String?;
    final receiptId = p['receipt_id'] as int?;
    final receiptNumber = p['receipt_number'] as String?;

    final classLine = [
      if (level.isNotEmpty) level,
      if (type.isNotEmpty && type != level) type,
      if (coach != null) t.coachNamed(coach),
      if (trainingTime != null) trainingTime,
    ].join(' \u2022 ');
    final paymentLine = [
      if (channel != null) t.channel(channel),
      if (receiptNumber != null) t.receiptNo(receiptNumber),
    ].join(' \u2022 ');

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 12),
      child: Row(
        children: [
          InitialsAvatar(name.toString()),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  if (!isPaid)
                    Container(
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(6)),
                      child: Text(t.notFinished, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warningDark)),
                    ),
                  Text(t.money(p['amount_paid']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                ],
              ),
              if (classLine.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(classLine, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              if (paymentLine.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(paymentLine, style: const TextStyle(fontSize: 13, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          )),
          // 48px target (Fitts's Law); was 32px
          if (isPaid && receiptId != null)
            IconButton(
              onPressed: _emailing.contains(receiptId) ? null : () => _emailReceipt(receiptId),
              icon: _emailing.contains(receiptId)
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(
                      _emailed.contains(receiptId) ? Icons.mark_email_read_rounded : Icons.forward_to_inbox_rounded,
                      size: 22,
                    ),
              color: _emailed.contains(receiptId) ? AppColors.success : AppColors.primary,
              tooltip: t.emailReceipt,
            ),
          if (isPaid && receiptId != null)
            IconButton(
              onPressed: () => _downloadReceipt(receiptId, receiptNumber ?? '$receiptId'),
              icon: const Icon(Icons.download_rounded, size: 22),
              color: AppColors.primary,
              tooltip: t.downloadReceipt,
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
