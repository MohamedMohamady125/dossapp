import '../../widgets/motion.dart';
import '../../services/app_refresh.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/bill.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/press_feedback.dart';
import '../../widgets/empty_state.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/ui_kit.dart';

class BillScreen extends StatefulWidget {
  const BillScreen({super.key});

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen>
    with AutoRefresh, SingleTickerProviderStateMixin, WidgetsBindingObserver {  @override
  Future<void> silentReload() => _load(silent: true);

  // A payment made at the desk or on another phone shows up within 30 s
  @override
  Duration? get refreshEvery => const Duration(seconds: 30);


  Bill? _bill;
  bool _loading = true;
  Object? _error;
  bool _paying = false;
  bool _awaitingPayment = false;
  bool _confirming = false;
  late AnimationController _checkController;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkController.dispose();
    super.dispose();
  }

  /// The payment page opens in the browser. When the parent comes back,
  /// check the bill ourselves instead of leaving "Payment due" on screen
  /// (which invites a second payment).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPayment) {
      _confirmPayment();
    }
  }

  Future<void> _confirmPayment() async {
    if (_confirming) return;
    setState(() => _confirming = true);
    // The gateway tells the server a few seconds after the parent pays
    for (var attempt = 0; attempt < 6 && mounted; attempt++) {
      try {
        final bill = await ApiService.getBill();
        if (!mounted) return;
        setState(() => _bill = bill);
        if (bill.isPaid) {
          _checkController.forward(from: 0);
          // Home, Receipts and Alerts show this payment straight away
          AppRefresh.dataChanged();
          break;
        }
      } catch (_) {
        // Keep trying; the last known bill stays on screen
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    if (mounted) setState(() { _confirming = false; _awaitingPayment = false; });
  }

  Future<void> _load({bool silent = false}) async {
    // A quiet refresh keeps the bill on screen; only the first load and a
    // retry show the skeleton.
    silent = silent && _bill != null;
    if (_confirming) return;
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final bill = await ApiService.getBill();
      if (!mounted) return;
      final becamePaid = bill.isPaid && _bill?.isPaid != true;
      _bill = bill;
      _error = null;
      if (becamePaid) _checkController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      if (!silent) _error = e;
    }
    setState(() => _loading = false);
  }

  Future<void> _pay() async {
    final s = S.read(context);
    setState(() => _paying = true);
    try {
      final intent = await ApiService.createPaymentIntent();
      final urlStr = intent['url'] as String?;
      if (urlStr == null || urlStr.isEmpty) {
        throw ApiException(0, s.paymentUnavailable);
      }
      final url = Uri.parse(urlStr);
      // No canLaunchUrl check: on Android 11+ it answers "no" for web links
      // unless the manifest declares them, which blocked the Pay button.
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (opened) {
        _awaitingPayment = true;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.couldNotOpenPayment)),
        );
      }
    } on ApiException catch (e) {
      if (e.message.toLowerCase().contains('already paid')) {
        // The screen was stale: the payment has gone through. Show it.
        if (mounted) setState(() => _paying = false);
        await _load();
        return;
      }
      if (mounted) {
        final msg = e.isServer
            ? s.paymentUnavailable
            : e.isNetwork
                ? e.message
                : s.paymentError(e.message);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.somethingWentWrong)),
        );
      }
    }
    if (mounted) setState(() => _paying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: FadeThrough(
          stateKey: _loading ? 'loading' : _error != null ? 'error' : 'content',
          child: _loading
              ? _buildLoadingState()
              : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : RefreshIndicator(onRefresh: _load, child: _buildContent()),
        ),
      ),
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
      final s = S.of(context);
      return CustomScrollView(
        slivers: [
          _buildHeader(bill),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.info_outline_rounded,
              title: s.noActiveEnrollment,
              subtitle: s.noActiveEnrollmentMsg,
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
            // ── Amount + status: one card answers "how much, and is it paid" ──
            AnimatedListItem(index: 0, child: _buildAmountCard(bill)),
            const SizedBox(height: 16),

            // ── The single action on this screen (Von Restorff) ──
            if (bill.isSuspended)
              AnimatedListItem(index: 1, child: _buildSuspendedCard())
            else if (!bill.isPaid && bill.amountOwed != null)
              AnimatedListItem(index: 1, child: _buildPayButton(bill))
            else if (!bill.isPaid)
              AnimatedListItem(index: 1, child: _buildPendingCard()),


            // ── What the bill covers ──
            if (bill.branchName != null || bill.schedule.isNotEmpty) ...[
              const SizedBox(height: 12),
              AnimatedListItem(index: 3, child: _buildServiceCard(bill)),
            ],

            const SizedBox(height: 24),
          ])),
        ),
      ],
    );
  }

  Widget _buildHeader(Bill bill) {
    return SliverAppBar(
      pinned: true,
      title: Text(S.of(context).myBill),
    );
  }

  // The amount sits on the brand gradient while it is owed and turns green
  // once paid, so the state reads from across the room (Von Restorff).
  Widget _buildAmountCard(Bill bill) {
    final isPaid = bill.isPaid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isPaid ? AppColors.successGradient : AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      formatPeriod(bill.period),
                      style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ScaleTransition(
                scale: isPaid
                    ? CurvedAnimation(parent: _checkController, curve: AppAnimation.bounceCurve)
                    : const AlwaysStoppedAnimation(1.0),
                child: Icon(
                  isPaid ? Icons.check_circle_rounded : Icons.account_balance_wallet_rounded,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (bill.amountOwed != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                formatMoney(bill.amountOwed),
                style: GoogleFonts.barlow(
                  fontSize: 46,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            )
          else if (!isPaid)
            Text(
              S.of(context).billPending,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          const SizedBox(height: 4),
          Text(
            isPaid
                ? (bill.receiptNumber != null
                    ? '${S.of(context).paid} \u2022 ${S.of(context).receiptLabel(bill.receiptNumber!)}'
                    : S.of(context).paid)
                : S.of(context).amountDue,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9)),
          ),
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
              const IconBadge(Icons.pool_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.of(context).serviceDetails,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    if (bill.branchName != null)
                      Text(
                        '${S.of(context).swimmingLessonsAt} ${bill.branchName}',
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
                    const Icon(Icons.schedule, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${s.dayPair ?? ""} ${s.timeBlock ?? ""}'
                        '${s.coach != null ? " \u2022 ${S.of(context).coachNamed(s.coach!)}" : ""}',
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

  Widget _buildPayButton(Bill bill) {
    return PressFeedback(
      onTap: (_paying || _confirming) ? null : _pay,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: (_paying || _confirming) ? null : AppColors.accentGradient,
          color: (_paying || _confirming) ? AppColors.textMuted : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_paying || _confirming)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            else
              const Icon(Icons.payment_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(
              _confirming
                  ? S.of(context).confirmingPayment
                  : _paying ? S.of(context).processing : S.of(context).payAmount(formatMoney(bill.amountOwed)),
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

  // Same card as the Home screen shows for a spot on hold, so the two pages
  // say one thing in one way (Similarity). Red is only on the small tag.
  Widget _buildSuspendedCard() {
    final s = S.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(s.enrollmentPaused, AppColors.error, icon: Icons.pause_circle_outline_rounded),
          const SizedBox(height: 14),
          Text(
            s.enrollmentWindowClosed,
            style: GoogleFonts.barlow(
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.enrollmentWindowClosedMsg,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
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
            S.of(context).billPending,
            style: GoogleFonts.barlow(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.of(context).billPendingMsg,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
