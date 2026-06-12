import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/athlete.dart';
import '../../models/bill.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';
import 'bill_screen.dart';
import 'receipts_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _currentIndex = 0;
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentTab(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.payment_outlined), selectedIcon: Icon(Icons.payment), label: 'Pay'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Receipts'),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0: return _HomeTab(key: ValueKey('home-$_refreshKey'), onRefresh: () => setState(() => _refreshKey++));
      case 1: return BillScreen(key: ValueKey('bill-$_refreshKey'));
      case 2: return ReceiptsScreen(key: ValueKey('rec-$_refreshKey'));
      default: return const SizedBox.shrink();
    }
  }
}

class _HomeTab extends StatefulWidget {
  final VoidCallback onRefresh;
  const _HomeTab({super.key, required this.onRefresh});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  AthleteProfile? _profile;
  Bill? _bill;
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
      final results = await Future.wait([
        ApiService.getProfile(),
        ApiService.getBill(),
      ]);
      _profile = results[0] as AthleteProfile;
      _bill = results[1] as Bill;
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 14), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ]))
              : RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final p = _profile!;
    final b = _bill;

    return CustomScrollView(
      slivers: [
        // ── App Bar ──
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, Color(0xFF283593)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
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
                            child: Center(child: Text(
                              p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                            )),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
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
              icon: const Icon(Icons.logout_rounded, color: Colors.white70),
              onPressed: () => context.read<AuthProvider>().logout(),
            ),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // ── Class & Practice Info (most important for parents) ──
            _classInfoCard(p),

            // ── Practice Times ──
            const SizedBox(height: 8),
            _sectionLabel('Practice Times'),
            if (p.schedule.isNotEmpty)
              _scheduleCard(p.schedule)
            else
              _practiceFromRoster(p),

            // ── Payment Status ──
            if (b != null && !b.noEnrollment) ...[
              const SizedBox(height: 8),
              _sectionLabel('Payment Status'),
              _billStatusCard(b),
            ],

            // ── Athlete Details ──
            const SizedBox(height: 8),
            _sectionLabel('Athlete Details'),
            _detailsCard(p),

            // ── Enrollment Info ──
            const SizedBox(height: 8),
            _sectionLabel('Enrollment'),
            _enrollmentCard(p),

            // ── No enrollment state ──
            if (b != null && b.noEnrollment)
              _noEnrollmentCard(),

            const SizedBox(height: 24),
          ])),
        ),
      ],
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
                  color: isPaid ? AppColors.success : hasBill ? const Color(0xFF92400E) : AppColors.textSecondary,
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
                color: isPaid ? AppColors.success : const Color(0xFF92400E),
              ),
            ),
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
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary), textAlign: TextAlign.center),
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
    if (p.gender != null) items.add(_DetailItem(
      p.gender == 'M' ? Icons.male : Icons.female,
      'Gender',
      p.gender == 'M' ? 'Male' : p.gender == 'F' ? 'Female' : p.gender!,
    ));
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(s.coach!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ],
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
