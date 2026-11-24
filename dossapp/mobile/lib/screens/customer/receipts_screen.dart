import '../../widgets/motion.dart';
import '../../services/app_refresh.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../widgets/ui_kit.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/receipt.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/press_feedback.dart';
import '../../widgets/empty_state.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> with AutoRefresh {
  @override
  Future<void> silentReload() => _load(silent: true);

  // Refreshes on changes and when reopened; no timer needed here
  @override
  Duration? get refreshEvery => null;

  List<Receipt>? _receipts;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    silent = silent && _receipts != null;
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final receipts = await ApiService.getReceipts();
      _receipts = receipts;
      _error = null;
    } catch (e) {
      if (!silent) _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _downloadPdf(Receipt receipt) async {
    final origin = shareOrigin(context); // iPad needs an anchor for the share sheet
    final failed = S.read(context).pdfFailed;
    try {
      final pdfBytes = await ApiService.downloadReceiptPdf(receipt.id);
      if (!mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt_${receipt.receiptNumber}.pdf');
      await file.writeAsBytes(pdfBytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], sharePositionOrigin: origin),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).receipts)),
      body: SizedBox.expand(
        child: FadeThrough(
          stateKey: _loading ? 'loading' : _error != null ? 'error' : 'content',
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SkeletonList(count: 4, hasAvatar: true);
    }

    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    if (_receipts == null || _receipts!.isEmpty) {
      final s = S.of(context);
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        title: s.noReceipts,
        subtitle: s.noReceiptsMsg,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _receipts!.length,
        itemBuilder: (ctx, i) => AnimatedListItem(
          index: i,
          child: PressFeedback(
            child: _buildReceiptCard(_receipts![i]),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard(Receipt receipt) {
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
          // Header row: receipt number badge + paid badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tag, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      receipt.receiptNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  S.of(context).paid,
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    // Spacing letters apart breaks joined Arabic script
                    letterSpacing: S.of(context).isArabic ? 0 : 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Amount
          Text(
            formatMoney(receipt.amountPaid),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),

          // Period and channel
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                formatPeriod(receipt.period),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  receipt.paymentChannel,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Date
          Text(
            westernDigits(DateFormat('dd MMM yyyy, hh:mm a').format(receipt.issuedAt.toLocal())),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Divider
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Action buttons as Wrap to prevent overflow
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (receipt.pdfAvailable)
                _actionButton(
                  icon: Icons.download_rounded,
                  label: S.of(context).openPdf,
                  onPressed: () => _downloadPdf(receipt),
                ),
              // Without a PDF, sharing the details as text is the fallback
              if (!receipt.pdfAvailable)
                _actionButton(
                icon: Icons.share_rounded,
                label: S.of(context).share,
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(sharePositionOrigin: shareOrigin(context), text: S.read(context).receiptShareText(receipt.receiptNumber, formatMoney(receipt.amountPaid), formatPeriod(receipt.period))),
                  );
                },
              ),
              _actionButton(
                icon: Icons.send_rounded,
                label: S.of(context).emailMeCopy,
                onPressed: () async {
                  final sent = S.read(context).sentToEmail;
                  final failedSend = S.read(context).somethingWentWrong;
                  try {
                    await ApiService.resendReceipt(receipt.id);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(sent)),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e is ApiException ? e.message : failedSend)),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon, size: 16, color: AppColors.textSecondary),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
