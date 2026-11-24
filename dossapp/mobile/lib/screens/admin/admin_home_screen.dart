import '../../widgets/motion.dart';
import '../../widgets/ui_kit.dart';
import 'package:flutter/services.dart';
import '../../utils/translations_staff.dart';
import 'accounts_screen.dart';
import '../../services/app_refresh.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
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
            if (i != _currentIndex) HapticFeedback.selectionClick();
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

  // The title says which branch you are looking at and is how you switch
  // (Jakob's Law: title as switcher). It looks tappable: the name sits in a
  // soft chip with a chevron. The list opens as a sheet from the bottom,
  // within reach of the thumb (Fitts's Law), with the current branch ticked.
  Widget _branchTitle(AuthProvider auth, Map<String, dynamic>? selectedBranch) {
    final name = (selectedBranch?['name'] as String?) ?? S.of(context).appName;
    final canSwitch = auth.isAdmin && _branches != null && _branches!.length > 1;

    if (!canSwitch) return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _showBranchSheet,
          child: Padding(
            // 44px tall target
            padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 6, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_outlined, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.2),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBranchSheet() {
    final t = SS.read(context);
    final branches = _branches ?? const [];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        // Never taller than most of the screen, however many branches
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Text(
                  t.chooseBranch,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.3),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: branches.length,
                  itemBuilder: (_, i) {
                    final b = branches[i];
                    final selected = _selectedBranchId == b['id'];
                    final count = (b['athlete_count'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: selected ? AppColors.primarySurface : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            if (selected) return;
                            HapticFeedback.selectionClick();
                            setState(() { _selectedBranchId = b['id'] as int; _refreshKey++; });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            child: Row(
                              children: [
                                IconBadge(
                                  Icons.pool_rounded,
                                  size: 44,
                                  color: selected ? AppColors.primary : AppColors.secondary,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b['name'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        t.swimmersCount(count),
                                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check_circle_rounded, color: AppColors.primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTab(AuthProvider auth) {
    if (_selectedBranchId == null && _currentIndex <= 3) {
      return Center(child: Text(SS.of(context).noDataYet));
    }
    // Lazy IndexedStack: each tab is built the first time it's opened and
    // then kept alive, so lists resume exactly where the user left off.
    return TabSwitcher(
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
