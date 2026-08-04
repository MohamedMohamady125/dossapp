import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/bill.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/press_feedback.dart';
import '../../widgets/empty_state.dart';
import 'package:url_launcher/url_launcher.dart';

class BillScreen extends StatefulWidget {
  const BillScreen({super.key});

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> with SingleTickerProviderStateMixin {
  Bill? _bill;
  bool _loading = true;
  String? _error;
  bool _paying = false;
  late AnimationController _checkController;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _load();
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _bill = await ApiService.getBill();
      if (_bill?.isPaid == true) {
        _checkController.forward(from: 0);
      }
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  Future<void> _pay() async {
    setState(() => _paying = true);
    try {
      final intent = await ApiService.createPaymentIntent();
      final urlStr = intent['url'] as String?;
      if (urlStr == null || urlStr.isEmpty) {
        throw ApiException(0, 'Payment is not available at the moment. Please try again later.');
      }
      final url = Uri.parse(urlStr);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open payment page. Please try again.')),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        final msg = e.isServer
            ? 'Payment service is temporarily unavailable. Please try again later.'
            : e.isNetwork
                ? e.message
                : 'Payment error: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment error: $e')),
        );
      }
    }
    if (mounted) setState(() => _paying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? _buildLoadingState()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildLoadingState() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 140,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: const [
              SkeletonHero(),
              SkeletonList(count: 2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final bill = _bill!;

    if (bill.noEnrollment) {
      return CustomScrollView(
        slivers: [
          _buildHeader(bill),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.info_outline_rounded,
              title: 'No Active Enrollment',
              subtitle: 'You are not enrolled for the current period.\nContact your branch for more information.',
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        _buildHeader(bill),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(delegate: SliverChildListDelegate([
            // ── Amount Card ──
            AnimatedListItem(index: 0, child: _buildAmountCard(bill)),
            const SizedBox(height: 16),

            // ── Service Details ──
            if (bill.branchName != null || bill.schedule.isNotEmpty)
              AnimatedListItem(index: 1, child: _buildServiceCard(bill)),

            const SizedBox(height: 16),

            // ── Payment Action / Status ──
            if (bill.isSuspended)
              AnimatedListItem(index: 2, child: _buildSuspendedCard())
            else if (bill.isPaid)
              AnimatedListItem(index: 2, child: _buildPaidCard(bill))
            else if (bill.amountOwed != null)
              AnimatedListItem(index: 2, child: _buildPayButton(bill))
            else
              AnimatedListItem(index: 2, child: _buildPendingCard()),

            const SizedBox(height: 24),
          ])),
        ),
      ],
    );
  }

  Widget _buildHeader(Bill bill) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Bill',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatPeriod(bill.period),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountCard(Bill bill) {
    final isPaid = bill.isPaid;
    final gradient = isPaid ? AppColors.successGradient : AppColors.primaryGradient;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isPaid ? AppColors.success : AppColors.primary).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Amount Due',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          bill.amountOwed != null
              ? Text(
                  formatMoney(bill.amountOwed),
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                )
              : ShimmerLoading(
                  width: 180,
                  height: 42,
                  borderRadius: 8,
                ),
          if (isPaid) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'PAID',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServiceCard(Bill bill) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.pool, size: 20, color: AppColors.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Service Details',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    if (bill.branchName != null)
                      Text(
                        'In-person swimming lessons at ${bill.branchName}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (bill.schedule.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final s in bill.schedule)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${s.dayPair ?? ""} ${s.timeBlock ?? ""}'
                        '${s.coach != null ? " \u2014 Coach: ${s.coach}" : ""}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaidCard(Bill bill) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.successGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ScaleTransition(
            scale: CurvedAnimation(
              parent: _checkController,
              curve: AppAnimation.bounceCurve,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, size: 48, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'PAID',
            style: GoogleFonts.barlowCondensed(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          if (bill.receiptNumber != null) ...[
            const SizedBox(height: 6),
            Text(
              'Receipt: ${bill.receiptNumber}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayButton(Bill bill) {
    return PressFeedback(
      onTap: _paying ? null : _pay,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: _paying ? null : AppColors.accentGradient,
          color: _paying ? AppColors.textMuted : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: _paying
              ? null
              : [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_paying)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            else
              const Icon(Icons.payment_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(
              _paying ? 'Processing...' : 'Pay ${formatMoney(bill.amountOwed)}',
              style: GoogleFonts.barlow(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuspendedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.schedule_rounded, size: 36, color: AppColors.warning),
          ),
          const SizedBox(height: 12),
          Text(
            'Enrollment Window Closed',
            style: GoogleFonts.barlowCondensed(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'The payment window for this period has closed.\n'
            'Go to the Home tab to check if a spot is\n'
            'still available in your class.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_empty_rounded, size: 36, color: AppColors.warning),
          ),
          const SizedBox(height: 12),
          Text(
            'Bill Pending',
            style: GoogleFonts.barlowCondensed(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your bill amount has not been set yet.\nYou will be notified when it is ready.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
