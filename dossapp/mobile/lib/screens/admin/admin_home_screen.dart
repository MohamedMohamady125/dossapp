import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../settings_screen.dart';
import 'athletes_screen.dart';
import 'payments_screen.dart';
import 'analytics_screen.dart';
import 'excel_health_screen.dart';
import 'branch_management_screen.dart';
import 'price_catalog_screen.dart';
import 'reinstatement_screen.dart';
import 'branch_admins_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentIndex = 0;
  int? _selectedBranchId;
  List<Map<String, dynamic>>? _branches;
  bool _loadingBranches = true;
  int _refreshKey = 0;
  int _pendingReinstatements = 0;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadPendingCount();
  }

  Future<void> _loadBranches() async {
    try {
      final auth = context.read<AuthProvider>();
      final branches = await ApiService.getBranches();
      setState(() {
        _branches = branches;
        _loadingBranches = false;
        if (auth.isAssistant && auth.branchId != null) {
          _selectedBranchId = auth.branchId;
        } else if (_selectedBranchId == null && branches.isNotEmpty) {
          _selectedBranchId = branches.first['id'];
        }
      });
    } catch (e) {
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _loadPendingCount() async {
    try {
      final requests = await ApiService.getReinstatementRequests(statusFilter: 'pending');
      if (mounted) setState(() => _pendingReinstatements = requests.length);
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    // Force backend to re-download Excel from Google Drive
    if (_selectedBranchId != null) {
      try {
        await ApiService.refreshBranch(_selectedBranchId!);
      } catch (_) {}
    }
    setState(() => _refreshKey++);
    _loadBranches();
    _loadPendingCount();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final s = S.of(context);
    if (_currentIndex > 3) _currentIndex = 0;

    if (_loadingBranches) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SkeletonHero(),
              SkeletonList(count: 3, padding: EdgeInsets.symmetric(horizontal: 16)),
            ],
          ),
        ),
      );
    }

    // Find selected branch name
    final selectedBranch = _branches?.firstWhere(
      (b) => b['id'] == _selectedBranchId,
      orElse: () => {'name': s.branch, 'athlete_count': 0},
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', height: 32, width: 32),
            const SizedBox(width: 8),
            Text(
              s.appName,
              style: GoogleFonts.barlowCondensed(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _pendingReinstatements > 0
                ? Badge(label: Text('$_pendingReinstatements'), child: const Icon(Icons.person_add_alt_1_rounded, size: 22))
                : const Icon(Icons.person_add_alt_1_rounded, size: 22),
            tooltip: s.reinstatementRequests,
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReinstatementScreen()));
              _loadPendingCount();
            },
          ),
          if (auth.isAdmin && _branches != null && _branches!.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.swap_horiz_rounded, size: 22),
              tooltip: s.branches,
              position: PopupMenuPosition.under,
              onSelected: (id) => setState(() { _selectedBranchId = id; _refreshKey++; }),
              itemBuilder: (ctx) => _branches!.map((b) => PopupMenuItem(
                value: b['id'] as int,
                child: Row(
                  children: [
                    Icon(
                      _selectedBranchId == b['id'] ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 18, color: _selectedBranchId == b['id'] ? AppColors.primary : AppColors.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(b['name'] as String)),
                    Text(formatNumber(b['athlete_count']), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              )).toList(),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 22),
            position: PopupMenuPosition.under,
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _refreshAll();
                  break;
                case 'health':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(s.health)),
                    body: const ExcelHealthScreen(),
                  )));
                  break;
                case 'branches':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BranchManagementScreen(onBranchesChanged: _refreshAll)));
                  break;
                case 'branch_admins':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BranchAdminsScreen()));
                  break;
                case 'settings':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    const Icon(Icons.refresh_rounded, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Text(s.refresh),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'health',
                child: Row(
                  children: [
                    const Icon(Icons.monitor_heart_outlined, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Text(s.health),
                  ],
                ),
              ),
              if (auth.isAdmin)
                PopupMenuItem(
                  value: 'branches',
                  child: Row(
                    children: [
                      const Icon(Icons.account_tree_outlined, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Text(s.branches),
                    ],
                  ),
                ),
              if (auth.isAdmin)
                PopupMenuItem(
                  value: 'branch_admins',
                  child: Row(
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Text(s.branchAdmins),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    const Icon(Icons.settings_outlined, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Text(s.settings),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: selectedBranch != null ? PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 16, bottom: 10),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${selectedBranch['name']} \u2022 ${formatNumber(selectedBranch['athlete_count'])} ${s.athletes.toLowerCase()}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ) : null,
      ),
      body: _buildCurrentTab(auth),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: s.home),
            NavigationDestination(icon: const Icon(Icons.payments_outlined), selectedIcon: const Icon(Icons.payments), label: s.payments),
            NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights), label: s.analytics),
            NavigationDestination(icon: const Icon(Icons.sell_outlined), selectedIcon: const Icon(Icons.sell), label: s.pricing),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab(AuthProvider auth) {
    if (_selectedBranchId == null && _currentIndex <= 2) {
      return Center(child: Text(S.of(context).noData));
    }
    switch (_currentIndex) {
      case 0: return AthletesScreen(branchId: _selectedBranchId!, key: ValueKey('ath-$_selectedBranchId-$_refreshKey'));
      case 1: return PaymentsScreen(branchId: _selectedBranchId!, key: ValueKey('pay-$_selectedBranchId-$_refreshKey'));
      case 2: return AnalyticsScreen(branchId: _selectedBranchId!, isAdmin: auth.isAdmin, key: ValueKey('ana-$_selectedBranchId-$_refreshKey'));
      case 3: return PriceCatalogScreen(key: ValueKey('pricing-$_refreshKey'));
      default: return const SizedBox.shrink();
    }
  }
}
