import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';
import 'athletes_screen.dart';
import 'payments_screen.dart';
import 'analytics_screen.dart';
import 'excel_health_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBranches();
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

  void _refreshAll() {
    setState(() => _refreshKey++);
    _loadBranches();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_loadingBranches) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Find selected branch name
    final selectedBranch = _branches?.firstWhere(
      (b) => b['id'] == _selectedBranchId,
      orElse: () => {'name': 'Select Branch', 'athlete_count': 0},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aqua Athletic'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh',
            onPressed: _refreshAll,
          ),
          if (auth.isAdmin && _branches != null && _branches!.isNotEmpty)
            PopupMenuButton<int>(
              icon: const Icon(Icons.swap_horiz_rounded, size: 22),
              tooltip: 'Switch Branch',
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
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 22),
            onPressed: () => auth.logout(),
          ),
        ],
        bottom: selectedBranch != null ? PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              '${selectedBranch['name']} \u2022 ${formatNumber(selectedBranch['athlete_count'])} athletes',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ) : null,
      ),
      body: _selectedBranchId == null
          ? const Center(child: Text('No branches available'))
          : _buildCurrentTab(auth),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Athletes'),
            NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Payments'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Analytics'),
            NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: 'Health'),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab(AuthProvider auth) {
    switch (_currentIndex) {
      case 0: return AthletesScreen(branchId: _selectedBranchId!, key: ValueKey('ath-$_selectedBranchId-$_refreshKey'));
      case 1: return PaymentsScreen(branchId: _selectedBranchId!, key: ValueKey('pay-$_selectedBranchId-$_refreshKey'));
      case 2: return AnalyticsScreen(branchId: _selectedBranchId!, isAdmin: auth.isAdmin, key: ValueKey('ana-$_selectedBranchId-$_refreshKey'));
      case 3: return ExcelHealthScreen(key: ValueKey('health-$_refreshKey'));
      default: return const SizedBox.shrink();
    }
  }
}
