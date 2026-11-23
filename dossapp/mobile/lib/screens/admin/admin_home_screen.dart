import '../../utils/translations_staff.dart';
import 'accounts_screen.dart';
import '../../services/app_refresh.dart';
import 'package:flutter/material.dart';
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

class _AdminHomeScreenState extends State<AdminHomeScreen> with AutoRefresh {
  @override
  Future<void> silentReload() => _loadPendingCount();

  int _currentIndex = 0;
  int? _selectedBranchId;
  List<Map<String, dynamic>>? _branches;
  bool _loadingBranches = true;
  int _refreshKey = 0;
  int _pendingReinstatements = 0;
  // Tabs that have been opened at least once — lazily built, then kept
  // alive inside an IndexedStack so scroll position & state persist.
  final Set<int> _visitedTabs = {0};

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
      if (!mounted) return;
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
      if (mounted) setState(() => _loadingBranches = false);
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
    final t = SS.of(context);
    if (_currentIndex > 4) _currentIndex = 0;

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
        // The title says which branch you are looking at and is also how you
        // switch (Jakob's Law: title-as-switcher). This replaces a logo, the
        // app name, a separate swap icon and a strip repeating the branch.
        titleSpacing: 16,
        title: _branchTitle(auth, selectedBranch),
        actions: [
          IconButton(
            icon: _pendingReinstatements > 0
                ? Badge(label: Text('$_pendingReinstatements'), child: const Icon(Icons.person_add_alt_1_rounded, size: 22))
                : const Icon(Icons.person_add_alt_1_rounded, size: 22),
            tooltip: t.requestsToReturn,
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReinstatementScreen()));
              _loadPendingCount();
            },
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
                    Text(t.menuRefresh),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'health',
                child: Row(
                  children: [
                    const Icon(Icons.monitor_heart_outlined, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Text(t.menuSheetCheck),
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
                      Text(t.menuBranches),
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
                      Text(t.menuBranchAdmins),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    const Icon(Icons.settings_outlined, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Text(t.menuSettings),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildCurrentTab(auth),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) {
            setState(() {
              _currentIndex = i;
              _visitedTabs.add(i);
            });
            // Opening a tab brings anything older than a few seconds up to date
            AppRefresh.nudge();
          },
          destinations: [
            NavigationDestination(icon: const Icon(Icons.people_outline), selectedIcon: const Icon(Icons.people), label: t.tabSwimmers),
            NavigationDestination(
              icon: const Icon(Icons.phone_iphone_outlined),
              selectedIcon: const Icon(Icons.phone_iphone),
              label: t.tabAccounts,
            ),
            NavigationDestination(icon: const Icon(Icons.payments_outlined), selectedIcon: const Icon(Icons.payments), label: t.tabPayments),
            NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights), label: t.tabAnalytics),
            NavigationDestination(icon: const Icon(Icons.sell_outlined), selectedIcon: const Icon(Icons.sell), label: t.tabPrices),
          ],
        ),
      ),
    );
  }

  Widget _branchTitle(AuthProvider auth, Map<String, dynamic>? selectedBranch) {
    final name = (selectedBranch?['name'] as String?) ?? S.of(context).appName;
    final canSwitch = auth.isAdmin && _branches != null && _branches!.length > 1;

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (canSwitch) const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
      ],
    );
    if (!canSwitch) return label;

    return PopupMenuButton<int>(
      tooltip: S.of(context).branches,
      position: PopupMenuPosition.under,
      onSelected: (id) => setState(() { _selectedBranchId = id; _refreshKey++; }),
      itemBuilder: (ctx) => _branches!.map((b) => PopupMenuItem(
        value: b['id'] as int,
        child: Row(
          children: [
            Icon(
              _selectedBranchId == b['id'] ? Icons.check_rounded : null,
              size: 18, color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(b['name'] as String)),
            Text(formatNumber(b['athlete_count']), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      )).toList(),
      // 48px tall target (Fitts's Law)
      child: SizedBox(height: 48, child: Align(alignment: AlignmentDirectional.centerStart, child: label)),
    );
  }

  Widget _buildCurrentTab(AuthProvider auth) {
    if (_selectedBranchId == null && _currentIndex <= 3) {
      return Center(child: Text(SS.of(context).noDataYet));
    }
    // Lazy IndexedStack: each tab is built the first time it's opened and
    // then kept alive, so lists resume exactly where the user left off.
    return IndexedStack(
      index: _currentIndex,
      children: List.generate(5, (i) {
        if (!_visitedTabs.contains(i)) return const SizedBox.shrink();
        switch (i) {
          case 0: return AthletesScreen(branchId: _selectedBranchId!, key: ValueKey('ath-$_selectedBranchId-$_refreshKey'));
          case 1: return AccountsScreen(branchId: _selectedBranchId!, key: ValueKey('acc-$_selectedBranchId-$_refreshKey'));
          case 2: return PaymentsScreen(branchId: _selectedBranchId!, key: ValueKey('pay-$_selectedBranchId-$_refreshKey'));
          case 3: return AnalyticsScreen(branchId: _selectedBranchId!, isAdmin: auth.isAdmin, key: ValueKey('ana-$_selectedBranchId-$_refreshKey'));
          case 4: return PriceCatalogScreen(branchId: _selectedBranchId, key: ValueKey('pricing-$_selectedBranchId-$_refreshKey'));
          default: return const SizedBox.shrink();
        }
      }),
    );
  }
}
