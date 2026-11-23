import '../../utils/app_error.dart';
import 'package:flutter/material.dart';
import '../../utils/translations_staff.dart';
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
  Object? _error;

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
      if (mounted) setState(() { _error = e; _loading = false; });
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
            final t = SS.of(ctx);
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
                            isEdit ? t.editBranch : t.addBranch,
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
                              decoration: InputDecoration(
                                labelText: t.shortName,
                                hintText: t.shortNameHint,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return t.required;
                                if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(v.trim())) {
                                  return t.shortNameRule;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: displayNameController,
                            decoration: InputDecoration(
                              labelText: t.nameInApp,
                              hintText: t.nameInAppHint,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: driveFileIdController,
                            // An ID is always left to right, also in Arabic
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: t.sheetId,
                              hintText: '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms',
                              helperText: t.sheetIdHelp,
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
                                          SnackBar(content: Text(AppError.messageFor(e))),
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
                                : Text(isEdit ? t.save : t.addBranch),
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
    final t = SS.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteBranchTitle),
        content: Text(t.deleteBranchQuestion('${branch['display_name'] ?? branch['name']}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(t.delete),
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
            SnackBar(content: Text(t.branchDeleted)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppError.messageFor(e))),
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
    final t = SS.of(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(t.branches),
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
                title: t.noBranchesYet,
                subtitle: t.addFirstBranch,
                actionLabel: t.addBranch,
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
                                                textDirection: TextDirection.ltr,
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
                                  tooltip: t.edit,
                                  onPressed: () => _showEditBranchSheet(branch),
                                ),
                                // Delete button
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20, color: AppColors.error),
                                  tooltip: t.delete,
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
                t.addBranch,
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
