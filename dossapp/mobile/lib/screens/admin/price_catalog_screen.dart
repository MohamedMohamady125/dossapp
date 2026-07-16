import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/press_feedback.dart';
import '../../widgets/empty_state.dart';

class PriceCatalogScreen extends StatefulWidget {
  const PriceCatalogScreen({super.key});

  @override
  State<PriceCatalogScreen> createState() => _PriceCatalogScreenState();
}

class _PriceCatalogScreenState extends State<PriceCatalogScreen> {
  List<Map<String, dynamic>>? _entries;
  List<Map<String, dynamic>>? _branches;
  int? _selectedBranchId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final branches = await ApiService.getBranches();
      final entries = await ApiService.getPriceCatalog(branchId: _selectedBranchId);
      if (mounted) {
        setState(() {
          _branches = branches;
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadEntries() async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await ApiService.getPriceCatalog(branchId: _selectedBranchId);
      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showEntryForm({Map<String, dynamic>? entry}) {
    final isEdit = entry != null;
    int? formBranchId = isEdit ? entry['branch_id'] as int : _selectedBranchId;
    final programController = TextEditingController(text: isEdit ? (entry['program_name'] ?? '') : '');
    final priceController = TextEditingController(text: isEdit ? (entry['price'] ?? '') : '');
    final sessionsController = TextEditingController(text: isEdit ? (entry['sessions'] ?? '') : '');
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
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEdit ? 'Edit Price' : 'Add Price',
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
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
                          // Branch dropdown (only for add)
                          if (!isEdit && _branches != null) ...[
                            DropdownButtonFormField<int>(
                              initialValue: formBranchId,
                              decoration: const InputDecoration(labelText: 'Branch'),
                              items: _branches!.map((b) => DropdownMenuItem(
                                value: b['id'] as int,
                                child: Text(b['name'] as String),
                              )).toList(),
                              onChanged: (v) => setSheetState(() => formBranchId = v),
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                          ],
                          // Program name
                          TextFormField(
                            controller: programController,
                            decoration: const InputDecoration(
                              labelText: 'Program Name',
                              hintText: 'e.g. Group Training, Private Training',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),
                          // Segment
                          DropdownButtonFormField<String>(
                            initialValue: formSegment,
                            decoration: const InputDecoration(labelText: 'Segment (optional)'),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('All (no segment)')),
                              DropdownMenuItem(value: 'Student', child: Text('Student')),
                              DropdownMenuItem(value: 'Outsider', child: Text('Outsider')),
                            ],
                            onChanged: (v) => setSheetState(() => formSegment = v),
                          ),
                          const SizedBox(height: 16),
                          // Sessions
                          TextFormField(
                            controller: sessionsController,
                            decoration: const InputDecoration(
                              labelText: 'Sessions (optional)',
                              hintText: 'e.g. 8 Sessions, 1 Session, 4 Weeks',
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Price
                          TextFormField(
                            controller: priceController,
                            decoration: const InputDecoration(
                              labelText: 'Price (EGP)',
                              hintText: 'e.g. 1500',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Required';
                              if (double.tryParse(v.trim()) == null) return 'Invalid number';
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: saving ? null : () async {
                              if (!formKey.currentState!.validate()) return;
                              setSheetState(() => saving = true);
                              try {
                                if (isEdit) {
                                  await ApiService.updatePriceCatalogEntry(
                                    entry['id'] as int,
                                    programName: programController.text.trim(),
                                    segment: formSegment ?? '',
                                    sessions: sessionsController.text.trim(),
                                    price: priceController.text.trim(),
                                  );
                                } else {
                                  await ApiService.createPriceCatalogEntry(
                                    branchId: formBranchId!,
                                    programName: programController.text.trim(),
                                    price: priceController.text.trim(),
                                    segment: formSegment,
                                    sessions: sessionsController.text.trim().isNotEmpty
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
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
                            },
                            child: saving
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(isEdit ? 'Save Changes' : 'Add Price'),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Price entry deleted')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String _branchName(int branchId) {
    if (_branches == null) return 'Branch $branchId';
    final b = _branches!.firstWhere((b) => b['id'] == branchId, orElse: () => {'name': 'Branch $branchId'});
    return b['name'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            floating: true,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
              title: Text(
                'Price Catalog',
                style: GoogleFonts.barlowCondensed(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              background: Container(decoration: const BoxDecoration(gradient: AppColors.primaryGradient)),
            ),
          ),
          // Branch filter
          if (_branches != null && _branches!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: DropdownButtonFormField<int?>(
                  initialValue: _selectedBranchId,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Branch',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Branches')),
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
            ),
          if (_loading)
            const SliverFillRemaining(child: SkeletonList(count: 5, padding: EdgeInsets.all(16)))
          else if (_error != null)
            SliverFillRemaining(child: ErrorState(message: _error!, onRetry: _loadEntries))
          else if (_entries == null || _entries!.isEmpty)
            SliverFillRemaining(
              child: EmptyState(
                icon: Icons.attach_money_outlined,
                title: 'No prices yet',
                subtitle: 'Add pricing for your programs.',
                actionLabel: 'Add Price',
                onAction: () => _showEntryForm(),
              ),
            )
          else
            _buildGroupedList(),
        ],
      ),
      floatingActionButton: (!_loading && _error == null)
          ? FloatingActionButton.extended(
              onPressed: () => _showEntryForm(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('Add Price', style: GoogleFonts.barlow(fontWeight: FontWeight.w600, color: Colors.white)),
              backgroundColor: AppColors.accent,
            )
          : null,
    );
  }

  Widget _buildGroupedList() {
    // Group entries by branch_id
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final e in _entries!) {
      final bid = e['branch_id'] as int;
      grouped.putIfAbsent(bid, () => []).add(e);
    }

    final branchIds = grouped.keys.toList()..sort();
    int itemIndex = 0;

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // Interleave headers and entries
            int currentIndex = 0;
            for (final bid in branchIds) {
              // Header
              if (index == currentIndex) {
                return Padding(
                  padding: EdgeInsets.only(top: currentIndex > 0 ? 20 : 0, bottom: 8),
                  child: Text(
                    _branchName(bid),
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                    ),
                  ),
                );
              }
              currentIndex++;

              final entries = grouped[bid]!;
              for (int i = 0; i < entries.length; i++) {
                if (index == currentIndex) {
                  final entry = entries[i];
                  return AnimatedListItem(
                    index: itemIndex++,
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
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        if (entry['segment'] != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: entry['segment'] == 'Student'
                                                  ? AppColors.primary.withValues(alpha: 0.1)
                                                  : AppColors.accent.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              entry['segment'] as String,
                                              style: TextStyle(
                                                fontSize: 11, fontWeight: FontWeight.w600,
                                                color: entry['segment'] == 'Student' ? AppColors.primary : AppColors.accent,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (entry['sessions'] != null)
                                          Text(
                                            entry['sessions'] as String,
                                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${_formatPrice(entry['price'] as String)} EGP',
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                                tooltip: 'Delete',
                                onPressed: () => _confirmDelete(entry),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                currentIndex++;
              }
            }
            return null;
          },
          childCount: branchIds.length + _entries!.length,
        ),
      ),
    );
  }

  String _formatPrice(String price) {
    final d = double.tryParse(price);
    if (d == null) return price;
    if (d == d.truncateToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2);
  }
}
