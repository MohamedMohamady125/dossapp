import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/athlete.dart';
import '../../models/bill.dart';
import '../../models/reinstatement.dart';
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

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _currentIndex = 0;
  int _refreshKey = 0;
  int _unreadCount = 0;

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
    setState(() => _currentIndex = 1);
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
            setState(() => _currentIndex = i);
            // Only refresh unread count when leaving notifications tab
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
    switch (_currentIndex) {
      case 0: return _HomeTab(key: ValueKey('home-$_refreshKey'), onRefresh: () => setState(() => _refreshKey++), onGoToPay: _goToPayTab);
      case 1: return BillScreen(key: ValueKey('bill-$_refreshKey'));
      case 2: return ReceiptsScreen(key: ValueKey('rec-$_refreshKey'));
      case 3: return NotificationsScreen(key: ValueKey('notif-$_refreshKey'), onUnreadChanged: _loadUnread);
      default: return const SizedBox.shrink();
    }
  }
}

class _HomeTab extends StatefulWidget {
  final VoidCallback onRefresh;
  final VoidCallback onGoToPay;
  const _HomeTab({super.key, required this.onRefresh, required this.onGoToPay});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  AthleteProfile? _profile;
  Bill? _bill;
  ReinstatementStatus? _reinstatement;
  bool _loading = true;
  String? _error;
  bool _submittingReinstatement = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Load profile first — it's fast and tells us suspension status immediately
      _profile = await ApiService.getProfile();

      // If suspended, show suspended UI right away while loading reinstatement
      if (_profile!.accountStatus == 'suspended') {
        if (mounted) setState(() => _loading = false);
        _reinstatement = await ApiService.getReinstatementStatus();
        if (mounted) setState(() {});
        return;
      }

      // Only load bill if active (bill endpoint is slower due to Excel lookup)
      _bill = await ApiService.getBill();

      // Bill endpoint may have just suspended the account — re-check
      if (_bill?.isSuspended == true) {
        _profile = await ApiService.getProfile();
        if (_profile!.accountStatus == 'suspended') {
          _reinstatement = await ApiService.getReinstatementStatus();
        }
      }
    } catch (e) {
      _error = e.toString();
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
            SliverAppBar(
              expandedHeight: 200,
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
                  SkeletonList(count: 3),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: ErrorState(
          message: _error!,
          onRetry: _load,
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
        // ── App Bar ──
        SliverAppBar(
          expandedHeight: 200,
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
                      Row(
                        children: [
                          Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text('${p.branch} \u2022 #${p.athleteNumber}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
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
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: () { _load(); widget.onRefresh(); },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white70),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // ── Class & Practice Info (most important for parents) ──
            AnimatedListItem(index: 0, child: _classInfoCard(p)),

            // ── Practice Times ──
            const SizedBox(height: 8),
            AnimatedListItem(index: 1, child: _sectionLabel('Practice Times')),
            AnimatedListItem(
              index: 2,
              child: p.schedule.isNotEmpty
                  ? _scheduleCard(p.schedule)
                  : _practiceFromRoster(p),
            ),

            // ── Attendance ──
            if (p.attendance.isNotEmpty) ...[
              const SizedBox(height: 8),
              AnimatedListItem(index: 3, child: _sectionLabel('Attendance')),
              AnimatedListItem(index: 4, child: _attendanceCard(p.attendance)),
            ],

            // ── Payment Status ──
            if (b != null && !b.noEnrollment) ...[
              const SizedBox(height: 8),
              AnimatedListItem(index: 5, child: _sectionLabel('Payment Status')),
              AnimatedListItem(
                index: 6,
                child: PressFeedback(
                  onTap: widget.onGoToPay,
                  child: _billStatusCard(b),
                ),
              ),
            ],

            // ── Athlete Details ──
            const SizedBox(height: 8),
            AnimatedListItem(index: 7, child: _sectionLabel('Athlete Details')),
            AnimatedListItem(index: 8, child: _detailsCard(p)),

            // ── Enrollment Info ──
            const SizedBox(height: 8),
            AnimatedListItem(index: 9, child: _sectionLabel('Enrollment')),
            AnimatedListItem(index: 10, child: _enrollmentCard(p)),

            // ── No enrollment state ──
            if (b != null && b.noEnrollment)
              AnimatedListItem(index: 11, child: _noEnrollmentCard()),

            const SizedBox(height: 24),
          ])),
        ),
      ],
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
                                'Enrollment Paused',
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
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: () { _load(); widget.onRefresh(); },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white70),
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
                  const Text(
                    'Enrollment Window Closed',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The enrollment period for this month has ended. '
                    'Spots are limited and are assigned to confirmed members who completed their payment on time.\n\n'
                    'If you\'d like to check for available spots, you can submit a request below.',
                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
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
                title: 'Checking Availability',
                subtitle: 'Your request has been submitted. The system is checking for available spots in your class. You\'ll be notified once confirmed.',
              ),
            ] else if (r.isApproved) ...[
              _reinstatementStatusCard(
                icon: Icons.check_circle_rounded,
                iconColor: AppColors.success,
                bgColor: AppColors.success.withValues(alpha: 0.06),
                borderColor: AppColors.success.withValues(alpha: 0.3),
                title: 'Spot Confirmed',
                subtitle: r.adminNote ?? 'Your spot has been confirmed. Please complete your payment to resume training.',
              ),
            ] else if (r.isDeclined) ...[
              _reinstatementStatusCard(
                icon: Icons.event_busy_rounded,
                iconColor: AppColors.error,
                bgColor: AppColors.error.withValues(alpha: 0.06),
                borderColor: AppColors.error.withValues(alpha: 0.2),
                title: 'No Spots Available',
                subtitle: r.adminNote ?? 'Unfortunately, all spots in your class have been filled for this period. The system was unable to hold your spot as the enrollment window has passed.',
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
          const Text(
            'Check Spot Availability',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Submit a request to check if a spot is still available in your class. '
            'You\'ll be notified once the system confirms availability.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
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
                  : const Text('Request Available Spot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
  Widget _billStatusCard(Bill b) {
    final isPaid = b.isPaid;
    final hasBill = b.amountOwed != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPaid ? AppColors.successLight : hasBill ? AppColors.warningLight : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPaid ? AppColors.success.withValues(alpha: 0.3) : hasBill ? AppColors.warning.withValues(alpha: 0.3) : AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isPaid ? AppColors.success : hasBill ? AppColors.warning : AppColors.textMuted).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPaid ? Icons.check_circle : hasBill ? Icons.payments : Icons.hourglass_empty,
              color: isPaid ? AppColors.success : hasBill ? AppColors.warning : AppColors.textMuted,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPaid ? 'Payment Complete' : hasBill ? 'Payment Due' : 'Bill Pending',
                style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15,
                  color: isPaid ? AppColors.success : hasBill ? AppColors.warningDark : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isPaid ? 'Receipt: ${b.receiptNumber ?? "Available"}' : hasBill ? formatPeriod(b.period) : 'Amount not set yet',
                style: TextStyle(fontSize: 12, color: isPaid ? AppColors.success.withValues(alpha: 0.7) : AppColors.textSecondary),
              ),
            ],
          )),
          if (hasBill)
            Text(
              formatMoney(b.amountOwed),
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: isPaid ? AppColors.success : AppColors.warningDark,
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
        ],
      ),
    );
  }

  // ── CLASS INFO CARD (the big one parents care about) ──
  Widget _classInfoCard(AthleteProfile p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Type + Level row
          Row(
            children: [
              Expanded(child: _classInfoTile(
                icon: Icons.pool,
                iconColor: AppColors.secondary,
                label: 'Class Type',
                value: p.type ?? 'Not assigned',
              )),
              Container(width: 1, height: 50, color: AppColors.border),
              Expanded(child: _classInfoTile(
                icon: Icons.stairs,
                iconColor: AppColors.primary,
                label: 'Level',
                value: p.level ?? 'Not assigned',
              )),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          // Days + Sessions row
          Row(
            children: [
              Expanded(child: _classInfoTile(
                icon: Icons.calendar_today,
                iconColor: AppColors.accent,
                label: 'Practice Days',
                value: p.days ?? 'Not assigned',
              )),
              Container(width: 1, height: 50, color: AppColors.border),
              Expanded(child: _classInfoTile(
                icon: Icons.repeat,
                iconColor: AppColors.success,
                label: 'Sessions',
                value: p.sessions ?? 'Not set',
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _classInfoTile({required IconData icon, required Color iconColor, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ── PRACTICE TIMES FROM ROSTER (when no schedule data from attendance sheets) ──
  Widget _practiceFromRoster(AthleteProfile p) {
    if (p.days == null && p.type == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            const Icon(Icons.info_outline, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Practice schedule will appear once assigned', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.pool, size: 20, color: AppColors.secondary),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.days != null)
                    Text(p.days!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  Text(
                    [if (p.type != null) p.type!, if (p.sessions != null) p.sessions!].join(' \u2022 '),
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── DETAILS CARD ──
  Widget _detailsCard(AthleteProfile p) {
    final items = <_DetailItem>[];
    if (p.age != null) items.add(_DetailItem(Icons.cake_outlined, 'Age', '${p.age!.toStringAsFixed(1)} years'));
    if (p.dateOfBirth != null) items.add(_DetailItem(Icons.calendar_today_outlined, 'Date of Birth', p.dateOfBirth!));
    if (p.gender != null) {
      items.add(_DetailItem(
        p.gender == 'M' ? Icons.male : Icons.female,
        'Gender',
        p.gender == 'M' ? 'Male' : p.gender == 'F' ? 'Female' : p.gender!,
      ));
    }
    if (p.level != null) items.add(_DetailItem(Icons.stairs_outlined, 'Level', p.level!));
    if (p.type != null) items.add(_DetailItem(Icons.category_outlined, 'Type', p.type!));
    if (p.sessions != null) items.add(_DetailItem(Icons.repeat, 'Sessions', p.sessions!));

    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(Icons.info_outline, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 10),
            const Text('Details will appear once updated', style: TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _detailRow(items[i]),
              if (i < items.length - 1) const Divider(indent: 52, height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(_DetailItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
            child: Icon(item.icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Text(item.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(item.value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  // ── SCHEDULE CARD ──
  Widget _scheduleCard(List<ScheduleSlot> schedule) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (var i = 0; i < schedule.length; i++) ...[
              _scheduleRow(schedule[i]),
              if (i < schedule.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scheduleRow(ScheduleSlot s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.pool, size: 20, color: AppColors.secondary),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.dayPair != null)
                Text(s.dayPair!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
              if (s.timeBlock != null)
                Text(s.timeBlock!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          )),
          if (s.coach != null)
            Flexible(
              flex: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: Text(s.coach!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── ENROLLMENT CARD ──
  Widget _enrollmentCard(AthleteProfile p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _enrollmentStat(Icons.location_on_outlined, 'Branch', p.branch),
            _enrollmentDivider(),
            _enrollmentStat(Icons.calendar_month, 'Days', p.days ?? 'N/A'),
            _enrollmentDivider(),
            _enrollmentStat(Icons.pool, 'Type', p.type ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _enrollmentStat(IconData icon, String label, String value) {
    return Expanded(child: Column(children: [
      Icon(icon, size: 20, color: AppColors.primary.withValues(alpha: 0.6)),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]));
  }

  Widget _enrollmentDivider() {
    return Container(width: 1, height: 36, color: AppColors.border);
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
      child: const Column(
        children: [
          Icon(Icons.info_outline, size: 40, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text('No Active Enrollment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 4),
          Text('You are not enrolled for the current period.\nContact your branch for more information.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ── ATTENDANCE CARD ──
  Widget _attendanceCard(Map<String, String> attendance) {
    // Sort dates chronologically
    final sortedDates = attendance.keys.toList()..sort();
    final present = attendance.values.where((v) => v == 'P').length;
    final absent = attendance.values.where((v) => v == 'A').length;
    final total = present + absent;
    final pct = total > 0 ? (present / total * 100).round() : 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary row
            Row(
              children: [
                _attendanceStat('$pct%', 'Rate', AppColors.primary),
                _attendanceDivider(),
                _attendanceStat('$present', 'Present', AppColors.success),
                _attendanceDivider(),
                _attendanceStat('$absent', 'Absent', AppColors.error),
                _attendanceDivider(),
                _attendanceStat('$total', 'Total', AppColors.textSecondary),
              ],
            ),
            if (sortedDates.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              // Date-by-date grid
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: sortedDates.map((date) {
                  final isPresent = attendance[date] == 'P';
                  final parsed = DateTime.tryParse(date);
                  final label = parsed != null ? DateFormat('d MMM').format(parsed) : date;
                  final dayName = parsed != null ? DateFormat('E').format(parsed) : '';

                  final chipW = ((MediaQuery.of(context).size.width - 80) / 5).clamp(52.0, 68.0);
                  return Container(
                    width: chipW,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isPresent
                          ? AppColors.success.withValues(alpha: 0.08)
                          : AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isPresent
                            ? AppColors.success.withValues(alpha: 0.2)
                            : AppColors.error.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          isPresent ? Icons.check_circle : Icons.cancel,
                          size: 18,
                          color: isPresent ? AppColors.success : AppColors.error,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isPresent ? AppColors.success : AppColors.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (dayName.isNotEmpty)
                          Text(
                            dayName,
                            style: TextStyle(
                              fontSize: 9,
                              color: (isPresent ? AppColors.success : AppColors.error).withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _attendanceStat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _attendanceDivider() {
    return Container(width: 1, height: 32, color: AppColors.border);
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
    );
  }
}

class _DetailItem {
  final IconData icon;
  final String label;
  final String value;
  _DetailItem(this.icon, this.label, this.value);
}
