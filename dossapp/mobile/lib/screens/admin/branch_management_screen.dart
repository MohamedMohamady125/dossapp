import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/press_feedback.dart';
import '../../widgets/empty_state.dart';

class BranchManagementScreen extends StatefulWidget {
  final VoidCallback? onBranchesChanged;
  const BranchManagementScreen({super.key, this.onBranchesChanged});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  List<Map<String, dynamic>>? _branches;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branches = await ApiService.getManageBranches();
      if (mounted) setState(() { _branches = branches; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showAddBranchSheet() {
    _showBranchFormSheet(isEdit: false);
  }

  void _showEditBranchSheet(Map<String, dynamic> branch) {
    _showBranchFormSheet(isEdit: true, branch: branch);
  }

  void _showBranchFormSheet({required bool isEdit, Map<String, dynamic>? branch}) {
    final nameController = TextEditingController(text: isEdit ? (branch?['name'] ?? '') : '');
    final displayNameController = TextEditingController(text: isEdit ? (branch?['display_name'] ?? '') : '');
    final driveFileIdController = TextEditingController(text: isEdit ? (branch?['drive_file_id'] ?? '') : '');
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
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Gradient header
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
                            isEdit ? 'Edit Branch' : 'Add Branch',
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
                          if (!isEdit) ...[
                            TextFormField(
                              controller: nameController,
                              decoration: const InputDecoration(
                                labelText: 'Branch Name (slug)',
                                hintText: 'e.g. main_branch',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(v.trim())) {
                                  return 'Lowercase letters, numbers, underscores only';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: displayNameController,
                            decoration: const InputDecoration(
                              labelText: 'Display Name',
                              hintText: 'e.g. Main Branch',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: driveFileIdController,
                            decoration: const InputDecoration(
                              labelText: 'Google Drive File ID',
                              hintText: 'e.g. 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms',
                              helperText: 'Find this in the Google Sheets URL after /d/',
                              helperMaxLines: 2,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) return;
                                    setSheetState(() => saving = true);
                                    try {
                                      if (isEdit) {
                                        await ApiService.updateBranch(
                                          branch!['id'] as int,
                                          displayName: displayNameController.text.trim(),
                                          driveFileId: driveFileIdController.text.trim(),
                                        );
                                      } else {
                                        await ApiService.createBranch(
                                          name: nameController.text.trim(),
                                          displayName: displayNameController.text.trim(),
                                          driveFileId: driveFileIdController.text.trim().isNotEmpty
                                              ? driveFileIdController.text.trim()
                                              : null,
                                        );
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _loadBranches();
                                      widget.onBranchesChanged?.call();
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
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(isEdit ? 'Save Changes' : 'Create Branch'),
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

  Future<void> _confirmDelete(Map<String, dynamic> branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Branch'),
        content: Text('Are you sure you want to delete "${branch['display_name'] ?? branch['name']}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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
        await ApiService.deleteBranch(branch['id'] as int);
        _loadBranches();
        widget.onBranchesChanged?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Branch deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
              title: Text(
                'Branch Management',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: SkeletonList(count: 5, padding: EdgeInsets.all(16)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: ErrorState(message: _error!, onRetry: _loadBranches),
            )
          else if (_branches == null || _branches!.isEmpty)
            SliverFillRemaining(
              child: EmptyState(
                icon: Icons.account_tree_outlined,
                title: 'No branches yet',
                subtitle: 'Create your first branch to get started.',
                actionLabel: 'Add Branch',
                onAction: _showAddBranchSheet,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final branch = _branches![index];
                    final hasDrive = branch['drive_file_id'] != null &&
                        (branch['drive_file_id'] as String).isNotEmpty;
                    final driveId = branch['drive_file_id'] as String? ?? '';

                    return AnimatedListItem(
                      index: index,
                      child: PressFeedback(
                        onTap: () => _showEditBranchSheet(branch),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Status indicator
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: hasDrive
                                        ? AppColors.success
                                        : AppColors.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // Branch info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        branch['display_name'] as String? ??
                                            branch['name'] as String,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        branch['name'] as String,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      if (driveId.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.table_chart_outlined,
                                              size: 14,
                                              color: AppColors.textMuted,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                _truncate(driveId, 20),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.textMuted,
                                                  fontFamily: 'monospace',
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Edit button
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 20, color: AppColors.textSecondary),
                                  tooltip: 'Edit',
                                  onPressed: () => _showEditBranchSheet(branch),
                                ),
                                // Delete button
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20, color: AppColors.error),
                                  tooltip: 'Delete',
                                  onPressed: () => _confirmDelete(branch),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _branches!.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: (!_loading && _error == null)
          ? FloatingActionButton.extended(
              onPressed: _showAddBranchSheet,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                'Add Branch',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              backgroundColor: AppColors.accent,
            )
          : null,
    );
  }
}
