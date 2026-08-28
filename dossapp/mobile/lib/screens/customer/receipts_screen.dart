import 'dart:io';
import 'package:flutter/material.dart';
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

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  List<Receipt>? _receipts;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _receipts = await ApiService.getReceipts();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _downloadPdf(Receipt receipt) async {
    try {
      final pdfBytes = await ApiService.downloadReceiptPdf(receipt.id);
      if (!mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt_${receipt.receiptNumber}.pdf');
      await file.writeAsBytes(pdfBytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).receipts)),
      body: _buildBody(),
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
                child: const Text(
                  'PAID',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.5,
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
            DateFormat('dd MMM yyyy, hh:mm a').format(receipt.issuedAt),
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
                  label: 'PDF',
                  onPressed: () => _downloadPdf(receipt),
                ),
              _actionButton(
                icon: Icons.share_rounded,
                label: 'Share',
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(text: 'Aquathletic Swimming Academy\n'
                        'Receipt: ${receipt.receiptNumber}\n'
                        'Amount: ${formatMoney(receipt.amountPaid)}\n'
                        'Period: ${formatPeriod(receipt.period)}\n'
                        'Status: PAID ✓'),
                  );
                },
              ),
              _actionButton(
                icon: Icons.send_rounded,
                label: 'Resend',
                onPressed: () async {
                  try {
                    await ApiService.resendReceipt(receipt.id);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Receipt resend queued')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
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
