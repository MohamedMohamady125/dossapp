import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/press_feedback.dart';
import '../../widgets/empty_state.dart';

class PriceCatalogScreen extends StatefulWidget {
  const PriceCatalogScreen({super.key});

  @override
  State<PriceCatalogScreen> createState() => _PriceCatalogScreenState();
}

class _PriceCatalogScreenState extends State<PriceCatalogScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>>? _entries;
  List<Map<String, dynamic>>? _branches;
  List<Map<String, dynamic>>? _missing;
  int? _selectedBranchId;
  bool _loading = true;
  String? _error;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getBranches(),
        ApiService.getPriceCatalog(branchId: _selectedBranchId),
        ApiService.getMissingPrices(),
      ]);
      if (mounted) {
        setState(() {
          _branches = results[0];
          _entries = results[1];
          _missing = results[2];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getPriceCatalog(branchId: _selectedBranchId),
        ApiService.getMissingPrices(),
      ]);
      if (mounted) {
        setState(() {
          _entries = results[0];
          _missing = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _showEntryForm({
    Map<String, dynamic>? entry,
    int? prefillBranchId,
    String? prefillProgram,
  }) {
    final isEdit = entry != null;
    int? formBranchId =
        isEdit ? entry['branch_id'] as int : (prefillBranchId ?? _selectedBranchId);
    final programController = TextEditingController(
      text: isEdit ? (entry['program_name'] ?? '') : (prefillProgram ?? ''),
    );
    final priceController =
        TextEditingController(text: isEdit ? (entry['price'] ?? '') : '');
    final sessionsController =
        TextEditingController(text: isEdit ? (entry['sessions'] ?? '') : '');
    String? formSegment = isEdit ? entry['segment'] : null;
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEdit ? 'Edit Price' : 'Assign Price',
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Branch dropdown
                          if (!isEdit && _branches != null) ...[
                            DropdownButtonFormField<int>(
                              initialValue: formBranchId,
                              decoration:
                                  const InputDecoration(labelText: 'Branch'),
                              items: _branches!
                                  .map((b) => DropdownMenuItem(
                                        value: b['id'] as int,
                                        child: Text(b['name'] as String),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setSheetState(() => formBranchId = v),
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: programController,
                            decoration: const InputDecoration(
                              labelText: 'Program Name',
                              hintText:
                                  'e.g. Group Training, Private Training',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: formSegment,
                            decoration: const InputDecoration(
                                labelText: 'Segment (optional)'),
                            items: const [
                              DropdownMenuItem(
                                  value: null,
                                  child: Text('All (no segment)')),
                              DropdownMenuItem(
                                  value: 'Student', child: Text('Student')),
                              DropdownMenuItem(
                                  value: 'Outsider', child: Text('Outsider')),
                            ],
                            onChanged: (v) =>
                                setSheetState(() => formSegment = v),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: sessionsController,
                            decoration: const InputDecoration(
                              labelText: 'Sessions (optional)',
                              hintText:
                                  'e.g. 8 Sessions, 1 Session, 4 Weeks',
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: priceController,
                            decoration: const InputDecoration(
                              labelText: 'Price (EGP)',
                              hintText: 'e.g. 1500',
                            ),
                            keyboardType: TextInputType.number,
                            autofocus: prefillProgram != null,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              if (double.tryParse(v.trim()) == null) {
                                return 'Invalid number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    setSheetState(() => saving = true);
                                    try {
                                      if (isEdit) {
                                        await ApiService
                                            .updatePriceCatalogEntry(
                                          entry['id'] as int,
                                          programName:
                                              programController.text.trim(),
                                          segment: formSegment ?? '',
                                          sessions:
                                              sessionsController.text.trim(),
                                          price: priceController.text.trim(),
                                        );
                                      } else {
                                        await ApiService
                                            .createPriceCatalogEntry(
                                          branchId: formBranchId!,
                                          programName:
                                              programController.text.trim(),
                                          price: priceController.text.trim(),
                                          segment: formSegment,
                                          sessions: sessionsController.text
                                                  .trim()
                                                  .isNotEmpty
                                              ? sessionsController.text.trim()
                                              : null,
                                        );
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _loadEntries();
                                    } catch (e) {
                                      setSheetState(() => saving = false);
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                              content: Text(e.toString())),
                                        );
                                      }
                                    }
                                  },
                            child: saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(isEdit ? 'Save Changes' : 'Assign Price'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Price Entry'),
        content: Text('Delete "${entry['program_name']}" pricing?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService.deletePriceCatalogEntry(entry['id'] as int);
        _loadEntries();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Price entry deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }

  String _branchName(int branchId) {
    if (_branches == null) return 'Branch $branchId';
    final b = _branches!.firstWhere((b) => b['id'] == branchId,
        orElse: () => {'name': 'Branch $branchId'});
    return b['name'] as String;
  }

  String _formatPrice(String price) {
    final d = double.tryParse(price);
    if (d == null) return price;
    if (d == d.truncateToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final missingCount = _missing?.length ?? 0;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 100,
            floating: true,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 50),
              title: Text(
                'Price Catalog',
                style: GoogleFonts.barlowCondensed(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
              background: Container(
                  decoration:
                      const BoxDecoration(gradient: AppColors.primaryGradient)),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: [
                const Tab(text: 'All Prices'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Missing'),
                      if (missingCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$missingCount',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        body: _loading
            ? const SkeletonList(count: 5, padding: EdgeInsets.all(16))
            : _error != null
                ? ErrorState(message: _error!, onRetry: _loadData)
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCatalogTab(),
                      _buildMissingTab(),
                    ],
                  ),
      ),
      floatingActionButton: (!_loading && _error == null)
          ? FloatingActionButton.extended(
              onPressed: () => _showEntryForm(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('Add Price',
                  style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600, color: Colors.white)),
              backgroundColor: AppColors.accent,
            )
          : null,
    );
  }

  // ── CATALOG TAB ──

  Widget _buildCatalogTab() {
    return Column(
      children: [
        // Branch filter
        if (_branches != null && _branches!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButtonFormField<int?>(
              initialValue: _selectedBranchId,
              decoration: const InputDecoration(
                labelText: 'Filter by Branch',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('All Branches')),
                ..._branches!.map((b) => DropdownMenuItem(
                      value: b['id'] as int,
                      child: Text(b['name'] as String),
                    )),
              ],
              onChanged: (v) {
                setState(() => _selectedBranchId = v);
                _loadEntries();
              },
            ),
          ),
        Expanded(
          child: _entries == null || _entries!.isEmpty
              ? EmptyState(
                  icon: Icons.attach_money_outlined,
                  title: 'No prices yet',
                  subtitle: 'Add pricing for your programs.',
                  actionLabel: 'Add Price',
                  onAction: () => _showEntryForm(),
                )
              : _buildGroupedList(),
        ),
      ],
    );
  }

  Widget _buildGroupedList() {
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final e in _entries!) {
      final bid = e['branch_id'] as int;
      grouped.putIfAbsent(bid, () => []).add(e);
    }

    final branchIds = grouped.keys.toList()..sort();
    final items = <Widget>[];

    for (final bid in branchIds) {
      items.add(Padding(
        padding: EdgeInsets.only(
            top: items.isNotEmpty ? 20 : 8, bottom: 8, left: 16, right: 16),
        child: Text(
          _branchName(bid),
          style: GoogleFonts.barlowCondensed(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
      ));

      for (final entry in grouped[bid]!) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: PressFeedback(
            onTap: () => _showEntryForm(entry: entry),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry['program_name'] as String,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (entry['segment'] != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: entry['segment'] == 'Student'
                                        ? AppColors.primary
                                            .withValues(alpha: 0.1)
                                        : AppColors.accent
                                            .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry['segment'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: entry['segment'] == 'Student'
                                          ? AppColors.primary
                                          : AppColors.accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (entry['sessions'] != null)
                                Text(
                                  entry['sessions'] as String,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_formatPrice(entry['price'] as String)} EGP',
                      style: GoogleFonts.barlowCondensed(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.error),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(entry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
      }
    }

    items.add(const SizedBox(height: 80));

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: ListView(children: items),
    );
  }

  // ── MISSING PRICES TAB ──

  Widget _buildMissingTab() {
    if (_missing == null || _missing!.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'All Priced!',
        subtitle:
            'Every athlete program has a matching price in the catalog.',
      );
    }

    // Group by branch
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final m in _missing!) {
      final bid = m['branch_id'] as int;
      grouped.putIfAbsent(bid, () => []).add(m);
    }
    final branchIds = grouped.keys.toList()..sort();

    final items = <Widget>[];

    // Warning banner
    items.add(
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_missing!.length} program${_missing!.length == 1 ? '' : 's'} without prices',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'These athletes have no bill. Tap to assign a price.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    for (final bid in branchIds) {
      final branchName = grouped[bid]!.first['branch_name'] as String;
      items.add(Padding(
        padding: EdgeInsets.only(
            top: items.length > 1 ? 16 : 8, bottom: 6, left: 16, right: 16),
        child: Text(
          branchName,
          style: GoogleFonts.barlowCondensed(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
      ));

      for (final m in grouped[bid]!) {
        final programLabel = m['program_label'] as String;
        final athleteCount = m['athlete_count'] as int;
        final samples = (m['sample_athletes'] as List).cast<String>();

        // Extract clean program name (strip the "(Type / Step)" suffix for the form)
        final cleanProgram = programLabel.contains(' (')
            ? programLabel.substring(0, programLabel.indexOf(' ('))
            : programLabel;

        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: PressFeedback(
            onTap: () => _showEntryForm(
              prefillBranchId: bid,
              prefillProgram: cleanProgram,
            ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.money_off_rounded,
                        color: AppColors.error, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          programLabel,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${formatNumber(athleteCount)} athlete${athleteCount == 1 ? '' : 's'} affected',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          samples.join(', ') +
                              (athleteCount > samples.length
                                  ? ' +${athleteCount - samples.length} more'
                                  : ''),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Assign',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
      }
    }

    items.add(const SizedBox(height: 80));

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: ListView(children: items),
    );
  }
}
