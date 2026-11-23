import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/ui_kit.dart';

class PriceCatalogScreen extends StatefulWidget {
  /// The branch chosen in the admin header. Prices are shown for that branch
  /// only, so this tab matches the other three (Working Memory).
  final int? branchId;
  const PriceCatalogScreen({super.key, this.branchId});

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
    _selectedBranchId = widget.branchId;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
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
          _missing = _forBranch(results[2]);
          _loading = false;
        });
        // Unfinished work first: open on the to-do list when there is one
        // (Zeigarnik Effect).
        if (_missing!.isNotEmpty) _tabController.index = 1;
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

  List<Map<String, dynamic>> _forBranch(List<Map<String, dynamic>> items) {
    if (_selectedBranchId == null) return items;
    return items.where((m) => m['branch_id'] == _selectedBranchId).toList();
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
          _missing = _forBranch(results[1]);
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
    String? prefillSessions,
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
        TextEditingController(
            text: isEdit ? (entry['sessions'] ?? '') : (prefillSessions ?? ''));
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
                            isEdit ? 'Edit price' : 'Add price',
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
                          if (!isEdit && _branches != null && widget.branchId == null) ...[
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
                                : Text(isEdit ? 'Save changes' : 'Save price'),
                          ),
                          if (isEdit) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: saving
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      _confirmDelete(entry);
                                    },
                              style: TextButton.styleFrom(foregroundColor: AppColors.error),
                              child: const Text('Delete this price'),
                            ),
                          ],
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

  @override
  Widget build(BuildContext context) {
    final missingCount = _missing?.length ?? 0;

    return Scaffold(
      body: Column(
        children: [
          // Plain tabs under the admin header. The old screen stacked a second
          // coloured "Price Catalog" header on top of the app bar.
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              dividerColor: AppColors.border,
              tabs: [
                const Tab(text: 'Price list'),
                Tab(text: missingCount > 0 ? 'Needs a price ($missingCount)' : 'Needs a price'),
              ],
            ),
          ),
          Expanded(
            child: _loading
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
        ],
      ),
      // One filled action, and only where adding is the task (Von Restorff).
      floatingActionButton: (!_loading && _error == null && _tabController.index == 0)
          ? FloatingActionButton.extended(
              onPressed: () => _showEntryForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add price'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  // ── PRICE LIST TAB ──

  static int _sessionCount(Map<String, dynamic> e) =>
      int.tryParse(RegExp(r'\d+').firstMatch((e['sessions'] ?? '') as String)?.group(0) ?? '') ?? 0;

  static String _segmentLabel(String? segment) =>
      segment == null ? '' : segment == 'Student' ? 'Gems students' : segment == 'Outsider' ? 'Outsiders' : segment;

  Widget _buildCatalogTab() {
    if (_entries == null || _entries!.isEmpty) {
      return EmptyState(
        icon: Icons.sell_outlined,
        title: 'No prices yet',
        subtitle: 'Prices come from the Sk. tab of the roster sheet. You can also add one here.',
        actionLabel: 'Add price',
        onAction: () => _showEntryForm(),
      );
    }

    // One card per program, its session prices as rows inside (Chunking).
    // The old list drew a separate card for every single price.
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in _entries!) {
      final branch = _selectedBranchId == null ? '${_branchName(e['branch_id'] as int)} \u2022 ' : '';
      final segment = _segmentLabel(e['segment'] as String?);
      final key = '$branch${e['program_name']}${segment.isEmpty ? '' : ' \u2022 $segment'}';
      groups.putIfAbsent(key, () => []).add(e);
    }
    final titles = groups.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: titles.length,
        itemBuilder: (ctx, i) {
          final rows = groups[titles[i]]!..sort((a, b) => _sessionCount(b).compareTo(_sessionCount(a)));
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      IconBadge(
                        titles[i].toLowerCase().contains('private') ? Icons.person_rounded
                            : titles[i].toLowerCase().contains('team') ? Icons.emoji_events_rounded
                            : Icons.pool_rounded,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          titles[i],
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final entry in rows)
                  InkWell(
                    onTap: () => _showEntryForm(entry: entry),
                    child: Padding(
                      // 48px row (Fitts's Law)
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              (entry['sessions'] as String?) ?? 'Monthly',
                              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                            ),
                          ),
                          Text(
                            '${formatNumber(double.tryParse(entry['price'] as String)?.round() ?? 0)} EGP',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── NEEDS A PRICE TAB ──

  Widget _buildMissingTab() {
    if (_missing == null || _missing!.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Every swimmer has a price',
        subtitle: 'Nothing to do here.',
      );
    }

    final swimmers = _missing!.fold<int>(0, (n, m) => n + (m['athlete_count'] as int));

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // What is left and why it matters, in one sentence (Goal-Gradient).
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const IconBadge(Icons.priority_high_rounded, color: AppColors.warningDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${formatNumber(swimmers)} swimmer${swimmers == 1 ? '' : 's'} can\'t be billed until '
                    '${_missing!.length == 1 ? 'this price is' : 'these ${_missing!.length} prices are'} added.',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.warningDark, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _missing!.length; i++) ...[
                  _missingRow(_missing![i]),
                  if (i < _missing!.length - 1) const Divider(height: 1, indent: 68),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _missingRow(Map<String, dynamic> m) {
    final programLabel = m['program_label'] as String;
    final athleteCount = m['athlete_count'] as int;
    final samples = (m['sample_athletes'] as List).cast<String>();

    // The server names the exact program + sessions a price is needed for,
    // so the form opens pre-filled and staff only type the price
    // (Tesler's Law: the system absorbs the matching rules).
    final program = (m['program_name'] as String?) ??
        (programLabel.contains(' (')
            ? programLabel.substring(0, programLabel.indexOf(' ('))
            : programLabel);
    final sessions = m['sessions'] as String?;
    final branchPrefix = _selectedBranchId == null ? '${m['branch_name']} \u2022 ' : '';

    return InkWell(
      onTap: () => _showEntryForm(
        prefillBranchId: m['branch_id'] as int,
        prefillProgram: program,
        prefillSessions: sessions,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(12)),
              child: Text('$athleteCount', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.warningDark)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sessions != null ? '$branchPrefix$program \u2022 $sessions' : '$branchPrefix$programLabel',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${samples.take(2).join(', ')}${athleteCount > 2 ? ' and ${athleteCount - 2} more' : ''}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
              child: const Text('Add price', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
