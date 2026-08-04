import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/press_feedback.dart';

class BranchAdminsScreen extends StatefulWidget {
  const BranchAdminsScreen({super.key});

  @override
  State<BranchAdminsScreen> createState() => _BranchAdminsScreenState();
}

class _BranchAdminsScreenState extends State<BranchAdminsScreen> {
  List<Map<String, dynamic>>? _admins;
  List<Map<String, dynamic>>? _branches;
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
        ApiService.getBranchAdmins(),
        ApiService.getBranches(),
      ]);
      _admins = List<Map<String, dynamic>>.from(results[0]);
      _branches = List<Map<String, dynamic>>.from(results[1]);
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Branch Admins',
          style: GoogleFonts.barlowCondensed(
            fontSize: 22, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary, letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: Text(
          'New Branch Admin',
          style: GoogleFonts.barlow(fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const SkeletonList(count: 4, hasAvatar: true);
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_admins == null || _admins!.isEmpty) {
      return EmptyState(
        icon: Icons.admin_panel_settings_outlined,
        title: 'No Branch Admins',
        subtitle: 'Tap the button below to create a branch admin.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _admins!.length,
        itemBuilder: (context, i) => _adminCard(_admins![i]),
      ),
    );
  }

  Widget _adminCard(Map<String, dynamic> admin) {
    final isActive = admin['is_active'] == true;
    final mustChange = admin['must_change_password'] == true;
    final lastLogin = admin['last_login_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isActive ? AppColors.border : AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primarySurface : AppColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.admin_panel_settings,
                  color: isActive ? AppColors.primary : AppColors.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      admin['username'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      admin['email'] ?? '',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Inactive', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.error)),
                )
              else if (mustChange)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Pending', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.warningDark)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                admin['branch_name'] ?? 'Branch ${admin['branch_id']}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const Spacer(),
              if (lastLogin != null) ...[
                const Icon(Icons.login, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  _formatDate(lastLogin),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ] else
                const Text('Never logged in', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              _actionButton(
                icon: Icons.lock_reset,
                label: 'Reset Password',
                onTap: () => _resetPassword(admin),
              ),
              const SizedBox(width: 12),
              _actionButton(
                icon: isActive ? Icons.block : Icons.check_circle_outline,
                label: isActive ? 'Deactivate' : 'Activate',
                color: isActive ? AppColors.error : AppColors.success,
                onTap: () => _toggleActive(admin),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? AppColors.primary;
    return PressFeedback(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c)),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  void _showCreateDialog() {
    if (_branches == null || _branches!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No branches available')),
      );
      return;
    }

    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int? selectedBranchId;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add, size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('New Branch Admin')),
              ],
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Branch selection
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    ),
                    initialValue: selectedBranchId,
                    items: _branches!.map((b) => DropdownMenuItem<int>(
                      value: b['id'] as int,
                      child: Text(b['name'] as String),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => selectedBranchId = v),
                    validator: (v) => v == null ? 'Select a branch' : null,
                  ),
                  const SizedBox(height: 16),
                  // Email
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, size: 20),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (!v.contains('@') || !v.contains('.')) return 'Invalid email';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: Text(S.of(context).cancel),
              ),
              FilledButton(
                onPressed: loading ? null : () async {
                  if (!formKey.currentState!.validate()) return;
                  setDialogState(() => loading = true);
                  try {
                    final result = await ApiService.createBranchAdmin(
                      email: emailCtrl.text.trim(),
                      branchId: selectedBranchId!,
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      _showCredentialsDialog(result);
                      _load();
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      setDialogState(() => loading = false);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  }
                },
                child: loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Generate'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCredentialsDialog(Map<String, dynamic> data) {
    final username = data['username'] as String;
    final password = data['temp_password'] as String;
    final branchName = data['branch_name'] as String?;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle, size: 22, color: AppColors.success),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Branch Admin Created')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (branchName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Branch: $branchName',
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
              ),
            _credentialRow('Username', username),
            const SizedBox(height: 12),
            _credentialRow('Password', password),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: AppColors.warningDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Share these credentials with the branch admin. They will be prompted to set a new password on first login.',
                      style: TextStyle(fontSize: 12, color: AppColors.warningDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'Username: $username\nPassword: $password'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Credentials copied to clipboard')),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.copy, size: 18),
                SizedBox(width: 6),
                Text('Copy'),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).done),
          ),
        ],
      ),
    );
  }

  Widget _credentialRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.barlow(
                fontSize: 16, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary, letterSpacing: 0.5,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18, color: AppColors.textMuted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copied')),
              );
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(Map<String, dynamic> admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text('Reset password for ${admin['username']}? A new temporary password will be generated.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.of(context).cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(S.of(context).confirm)),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await ApiService.resetBranchAdminPassword(admin['id'] as int);
      if (mounted) {
        _showCredentialsDialog({
          'username': result['username'],
          'temp_password': result['temp_password'],
          'branch_name': admin['branch_name'],
        });
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> admin) async {
    final isActive = admin['is_active'] == true;
    final action = isActive ? 'deactivate' : 'activate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} Admin'),
        content: Text('Are you sure you want to $action ${admin['username']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.of(context).cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: isActive ? FilledButton.styleFrom(backgroundColor: AppColors.error) : null,
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.toggleBranchAdminActive(admin['id'] as int);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}
