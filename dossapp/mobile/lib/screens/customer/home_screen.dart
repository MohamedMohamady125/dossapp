import '../../utils/app_error.dart';
import '../../services/app_refresh.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../auth/profile_picker_screen.dart';
import '../../models/athlete.dart';
import '../../models/bill.dart';
import '../../models/reinstatement.dart';
import '../../models/report.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/press_feedback.dart';
import '../../widgets/empty_state.dart';
import '../settings_screen.dart';
import 'bill_screen.dart';
import 'receipts_screen.dart';
import 'notifications_screen.dart';
import 'reports_screen.dart';
import '../../widgets/ui_kit.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> with AutoRefresh {
  @override
  Future<void> silentReload() => _loadUnread();

  int _currentIndex = 0;
  int _refreshKey = 0;
  int _unreadCount = 0;
  // Tabs opened at least once — lazily built, then kept alive in an
  // IndexedStack so scroll position & state persist between switches.
  final Set<int> _visitedTabs = {0};

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    try {
      final count = await ApiService.getUnreadCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {
      // Silently fail — badge count is non-critical
    }
  }

  Widget _bellIcon(IconData icon) {
    if (_unreadCount <= 0) return Icon(icon);
    return Badge(
      label: Text('$_unreadCount'),
      child: Icon(icon),
    );
  }

  void _goToPayTab() {
    setState(() {
      _currentIndex = 1;
      _visitedTabs.add(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: _buildCurrentTab(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) {
            setState(() {
              _currentIndex = i;
              _visitedTabs.add(i);
            });
            // Opening a tab is a good moment to bring old data up to date
            AppRefresh.nudge();
            if (i != 3) _loadUnread();
          },
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: s.home),
            NavigationDestination(icon: const Icon(Icons.payment_outlined), selectedIcon: const Icon(Icons.payment), label: s.pay),
            NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: s.receipts),
            NavigationDestination(
              icon: _bellIcon(Icons.notifications_outlined),
              selectedIcon: _bellIcon(Icons.notifications),
              label: s.alerts,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    // Lazy IndexedStack: build each tab on first visit, keep it alive after
    // so scroll position & loaded data survive tab switches.
    return IndexedStack(
      index: _currentIndex,
      children: List.generate(4, (i) {
        if (!_visitedTabs.contains(i)) return const SizedBox.shrink();
        switch (i) {
          case 0: return _HomeTab(key: ValueKey('home-$_refreshKey'), onRefresh: () => setState(() => _refreshKey++), onGoToPay: _goToPayTab);
          case 1: return BillScreen(key: ValueKey('bill-$_refreshKey'));
          case 2: return ReceiptsScreen(key: ValueKey('rec-$_refreshKey'));
          case 3: return NotificationsScreen(key: ValueKey('notif-$_refreshKey'), onUnreadChanged: _loadUnread);
          default: return const SizedBox.shrink();
        }
      }),
    );
  }
}

class _HomeTab extends StatefulWidget {
  final VoidCallback onRefresh;
  final VoidCallback onGoToPay;
  const _HomeTab({super.key, required this.onRefresh, required this.onGoToPay});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutoRefresh {
  @override
  Future<void> silentReload() => _load();

  // A payment made at the desk or on another phone shows up within 30 s
  @override
  Duration? get refreshEvery => const Duration(seconds: 30);

  AthleteProfile? _profile;
  Bill? _bill;
  List<MonthlyReport> _reports = [];
  ReinstatementStatus? _reinstatement;
  bool _loading = true;
  Object? _error;
  bool _submittingReinstatement = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Skeleton only on first load — pull-to-refresh updates silently.
    final isInitial = _profile == null;
    setState(() { if (isInitial) _loading = true; _error = null; });
    try {
      // Fire both requests concurrently
      final profileFuture = ApiService.getProfile();
      final billFuture = ApiService.getBill().catchError((_) => Bill.empty());
      final reportsFuture = ApiService.getMyReports().catchError((_) => <MonthlyReport>[]);
      final results = await Future.wait<dynamic>([profileFuture, billFuture, reportsFuture]);
      _profile = results[0] as AthleteProfile;
      _bill = results[1] as Bill;
      _reports = results[2] as List<MonthlyReport>;

      // If suspended, load reinstatement status
      if (_profile!.accountStatus == 'suspended' || _bill?.isSuspended == true) {
        try {
          _reinstatement = await ApiService.getReinstatementStatus();
        } catch (_) {}
      }
    } catch (e, stack) {
      debugPrint('Home load error: $e\n$stack');
      if (isInitial) _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submitReinstatement() async {
    setState(() => _submittingReinstatement = true);
    try {
      await ApiService.requestReinstatement();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppError.messageFor(e))));
      }
    }
    if (mounted) setState(() => _submittingReinstatement = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverAppBar(pinned: true, toolbarHeight: 64),
            SliverToBoxAdapter(
              child: Column(
                children: const [
                  SkeletonHero(),
                  SkeletonList(count: 3),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      // Always leave a way out (log out), so a parent is never stuck here
      return Scaffold(
        body: Column(
          children: [
            Expanded(child: ErrorState(message: _error!, onRetry: _load)),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton(
                  onPressed: () => context.read<AuthProvider>().logout(),
                  child: Text(S.of(context).logout),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final p = _profile!;
    final b = _bill;

    // ── Suspended state ──
    if (p.accountStatus == 'suspended') {
      return _buildSuspendedContent(p);
    }

    return CustomScrollView(
      slivers: [
        // ── App Bar: who this is, once, on a plain surface ──
        SliverAppBar(
          pinned: true,
          toolbarHeight: 76,
          titleSpacing: 16,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.primaryGradient)),
          title: _swimmerTitle(p),
          actions: [
            IconButton(
              tooltip: S.of(context).settings,
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
            const SizedBox(width: 4),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // Order follows what a parent opens the app for (Pareto):
            // is it paid, when is practice, did they attend. Each fact
            // appears once (Cognitive Load).

            // ── Payment ──
            if (b != null && !b.noEnrollment)
              AnimatedListItem(
                index: 0,
                child: PressFeedback(
                  onTap: widget.onGoToPay,
                  child: _billStatusCard(b),
                ),
              ),

            // ── No enrollment state ──
            if (b != null && b.noEnrollment)
              AnimatedListItem(index: 0, child: _noEnrollmentCard()),

            // ── The month at a glance (Chunking: three numbers) ──
            if (p.attendance.isNotEmpty) ...[
              const SizedBox(height: 12),
              AnimatedListItem(index: 1, child: _statsRow(p.attendance)),
            ],

            // ── Class & practice ──
            const SizedBox(height: 20),
            AnimatedListItem(index: 1, child: SectionTitle(S.of(context).classInfo)),
            AnimatedListItem(index: 2, child: _classCard(p)),

            // ── Attendance ──
            if (p.attendance.isNotEmpty) ...[
              const SizedBox(height: 20),
              AnimatedListItem(index: 3, child: SectionTitle(S.of(context).attendance)),
              AnimatedListItem(index: 4, child: _attendanceCard(p.attendance)),
            ],

            // ── Monthly Report ──
            if (_reports.isNotEmpty) ...[
              const SizedBox(height: 20),
              AnimatedListItem(index: 5, child: SectionTitle(S.of(context).monthlyReport)),
              AnimatedListItem(index: 6, child: _reportPreviewCard(_reports.first)),
            ],

            // ── About the swimmer ──
            if (p.age != null || p.dateOfBirth != null || p.gender != null) ...[
              const SizedBox(height: 20),
              AnimatedListItem(index: 7, child: SectionTitle(S.of(context).athleteDetails)),
              AnimatedListItem(index: 8, child: _detailsCard(p)),
            ],

            const SizedBox(height: 24),
          ])),
        ),
      ],
    );
  }

  // Who this is. With several swimmers on the parent's email, the whole
  // title is the switcher (Jakob's Law: tap the name to change account), and
  // it says so with a chevron and a count on the avatar.
  Widget _swimmerTitle(AthleteProfile p) {
    final auth = context.watch<AuthProvider>();
    final several = auth.hasSeveralSwimmers;

    final avatar = Container(
      width: 46, height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Text(
        InitialsAvatar.initialsOf(p.name),
        style: GoogleFonts.barlow(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );

    final row = Row(
      children: [
        if (several)
          Badge(
            label: Text('${auth.profiles.length}'),
            backgroundColor: Colors.white,
            textColor: AppColors.primary,
            child: avatar,
          )
        else
          avatar,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlowCondensed(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  if (several) const Icon(Icons.expand_more_rounded, color: Colors.white, size: 24),
                ],
              ),
              Text(
                several
                    ? '${p.branch} \u2022 #${p.athleteNumber} \u2022 ${S.of(context).switchSwimmer}'
                    : '${p.branch} \u2022 #${p.athleteNumber}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlow(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );

    if (!several) return row;
    return InkWell(
      onTap: () => showSwimmerSwitcher(context),
      borderRadius: BorderRadius.circular(14),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: row),
    );
  }

  // ── SUSPENDED CONTENT ──
  Widget _buildSuspendedContent(AthleteProfile p) {
    final r = _reinstatement;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(child: Icon(Icons.schedule_rounded, size: 28, color: Colors.white)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.of(context).enrollmentPaused,
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(p.name, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                            ],
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            if (context.watch<AuthProvider>().hasSeveralSwimmers)
              IconButton(
                tooltip: S.of(context).switchSwimmer,
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: () => showSwimmerSwitcher(context),
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () { _load(); widget.onRefresh(); },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // ── Suspension reason ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, size: 40, color: AppColors.error),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    S.of(context).enrollmentWindowClosed,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).spotLostExplain,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Reinstatement status / action ──
            if (r == null || r.isNone) ...[
              // No request yet — show button
              _reinstatementActionCard(),
            ] else if (r.isPending) ...[
              _reinstatementStatusCard(
                icon: Icons.hourglass_top_rounded,
                iconColor: AppColors.warning,
                bgColor: AppColors.warningLight,
                borderColor: AppColors.warning.withValues(alpha: 0.3),
                title: S.of(context).checkingAvailability,
                subtitle: S.of(context).checkingAvailabilityMsg,
              ),
            ] else if (r.isApproved) ...[
              _reinstatementStatusCard(
                icon: Icons.check_circle_rounded,
                iconColor: AppColors.success,
                bgColor: AppColors.success.withValues(alpha: 0.06),
                borderColor: AppColors.success.withValues(alpha: 0.3),
                title: S.of(context).spotConfirmed,
                subtitle: r.adminNote ?? S.of(context).spotConfirmedMsg,
              ),
            ] else if (r.isDeclined) ...[
              _reinstatementStatusCard(
                icon: Icons.event_busy_rounded,
                iconColor: AppColors.error,
                bgColor: AppColors.error.withValues(alpha: 0.06),
                borderColor: AppColors.error.withValues(alpha: 0.2),
                title: S.of(context).noSpotsAvailable,
                subtitle: r.adminNote ?? S.of(context).noSpotsMsg,
              ),
              const SizedBox(height: 12),
              // Allow resubmission after decline
              _reinstatementActionCard(),
            ],

            const SizedBox(height: 24),
          ])),
        ),
      ],
    );
  }

  Widget _reinstatementActionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_available_rounded, size: 36, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(
            S.of(context).checkSpotAvailability,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            S.of(context).askSpotHelp,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submittingReinstatement ? null : _submitReinstatement,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submittingReinstatement
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(S.of(context).requestAvailableSpot, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reinstatementStatusCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: iconColor),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── BILL STATUS CARD ──
  // Colour says the state before the words do: green = paid, orange = due
  // (the one thing here that asks for action, Von Restorff), amber = waiting.
  Widget _billStatusCard(Bill b) {
    final isPaid = b.isPaid;
    final hasBill = b.amountOwed != null;
    final due = !isPaid && hasBill;

    final s = S.of(context);
    final title = isPaid ? s.paid : hasBill ? s.paymentDue : s.billPending;
    final subtitle = isPaid
        ? formatPeriod(b.period)
        : hasBill
            ? formatPeriod(b.period)
            : s.billSoon;

    final tone = isPaid ? AppColors.success : AppColors.warning;
    final fg = due ? Colors.white : AppColors.textPrimary;
    final fgMuted = due ? Colors.white.withValues(alpha: 0.85) : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: due ? AppColors.accentGradient : null,
        color: due ? null : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: due ? null : Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: due ? Colors.white.withValues(alpha: 0.22) : tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isPaid ? Icons.check_circle_rounded : hasBill ? Icons.account_balance_wallet_rounded : Icons.hourglass_top_rounded,
              color: due ? Colors.white : tone,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: fg)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 13, color: fgMuted)),
            ],
          )),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (hasBill)
                Text(
                  formatMoney(b.amountOwed),
                  style: GoogleFonts.barlowCondensed(fontSize: 24, fontWeight: FontWeight.w700, color: fg),
                ),
              if (due)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Text(s.payNow, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                ),
            ],
          ),
          if (!due) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: fgMuted, size: 20),
          ],
        ],
      ),
    );
  }

  // ── STATS ROW ──
  Widget _statsRow(Map<String, String> attendance) {
    final present = attendance.values.where((v) => v == 'P').length;
    final total = attendance.length;
    final missed = total - present;
    final rate = total > 0 ? (present * 100 / total).round() : 0;
    return Row(
      children: [
        Expanded(child: StatTile(icon: Icons.pool_rounded, color: AppColors.primary, value: '$present', label: S.of(context).present)),
        const SizedBox(width: 10),
        Expanded(child: StatTile(icon: Icons.event_busy_rounded, color: missed > 0 ? AppColors.error : AppColors.textMuted, value: '$missed', label: S.of(context).absent)),
        const SizedBox(width: 10),
        Expanded(child: StatTile(icon: Icons.insights_rounded, color: AppColors.primary, value: '$rate%', label: S.of(context).attendance)),
      ],
    );
  }

  // ── CLASS CARD ──
  // One card for everything about the class: what it is, then when and with
  // whom (Common Region). Replaces four separate cards that repeated the same
  // type, level, days and sessions.
  Widget _classCard(AthleteProfile p) {
    final title = [
      if (p.type != null) p.type!,
      if (p.level != null && p.level != p.type) p.level!,
    ].join(' \u2022 ');
    final meta = [
      if (p.days != null) p.days!,
      if (p.sessions != null) p.sessions!,
    ].join(' \u2022 ');

    if (title.isEmpty && meta.isEmpty && p.schedule.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            S.of(context).classNotSetMsg,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(Icons.pool_rounded, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? S.of(context).classNotSet : title,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(meta, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (p.schedule.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              for (final slot in p.schedule) _scheduleRow(slot),
            ],
          ],
        ),
      ),
    );
  }

  // ── DETAILS CARD ──
  Widget _detailsCard(AthleteProfile p) {
    // One line: a parent knows their child, this only confirms the record
    // is the right one (Cognitive Load: three rows said what one can).
    final parts = <String>[
      if (p.age != null) S.of(context).yearsOld(p.age!.toStringAsFixed(1)),
      if (p.gender != null) p.gender == 'M' ? S.of(context).male : p.gender == 'F' ? S.of(context).female : p.gender!,
      if (p.dateOfBirth != null) S.of(context).bornOn(p.dateOfBirth!),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const IconBadge(Icons.person_rounded, color: AppColors.primary, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                parts.join(' \u2022 '),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // One practice slot: a time pill, the days, and the coach.
  Widget _scheduleRow(ScheduleSlot s) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          if (s.timeBlock != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, size: 15, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Text(s.timeBlock!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
                ],
              ),
            )
          else
            const Icon(Icons.schedule_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.dayPair ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
          if (s.coach != null) ...[
            const Icon(Icons.sports_rounded, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                s.coach!,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── NO ENROLLMENT ──
  Widget _noEnrollmentCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.info_outline, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(S.of(context).noActiveEnrollment, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(S.of(context).noActiveEnrollmentMsg,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ── ATTENDANCE CARD ──
  // One headline number with a progress bar (Goal-Gradient), then the dates.
  // Attended days are neutral; only a missed day carries colour, so misses
  // are what the eye lands on (Von Restorff).
  Widget _attendanceCard(Map<String, String> attendance) {
    final sortedDates = attendance.keys.toList()..sort();
    final present = attendance.values.where((v) => v == 'P').length;
    final total = attendance.length;
    final absent = total - present;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(S.of(context).sessionsOf(present, total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                if (absent > 0)
                  StatusPill(S.of(context).missedCount(absent), AppColors.error)
                else
                  StatusPill(S.of(context).noMisses, AppColors.primary),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? present / total : 0,
                minHeight: 8,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sortedDates.map((date) {
                final isPresent = attendance[date] == 'P';
                final parsed = DateTime.tryParse(date);
                final label = parsed != null ? westernDigits(DateFormat('E d').format(parsed)) : date;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isPresent ? AppColors.surfaceVariant : AppColors.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPresent ? Icons.check_rounded : Icons.close_rounded,
                        size: 14,
                        color: isPresent ? AppColors.textSecondary : AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPresent ? AppColors.textPrimary : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportPreviewCard(MonthlyReport report) {
    final note = report.note;
    return PressFeedback(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CustomerReportsScreen(initialReports: _reports)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            IconBadge(
              report.hasPdf ? Icons.picture_as_pdf_rounded : Icons.sticky_note_2_rounded,
              size: 46,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatPeriod(report.period),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note ?? S.of(context).pdfReport,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                  ),
                ],
              ),
            ),
            if (_reports.length > 1)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: StatusPill('${_reports.length}', AppColors.primary),
              ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

