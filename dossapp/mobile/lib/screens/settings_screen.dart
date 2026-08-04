import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/locale_provider.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../utils/translations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final auth = context.watch<AuthProvider>();
    final locale = context.watch<LocaleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.settings),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Account Section ──
          _sectionHeader(s.account),
          const SizedBox(height: 8),
          _settingsCard([
            _settingsTile(
              icon: Icons.lock_outline,
              title: s.changePassword,
              onTap: () => _showChangePasswordDialog(context, auth),
            ),
            if (auth.isCustomer)
              _settingsTile(
                icon: Icons.email_outlined,
                title: s.changeEmail,
                onTap: () => _showChangeEmailDialog(context),
              ),
          ]),

          const SizedBox(height: 20),

          // ── General Section ──
          _sectionHeader(s.general),
          const SizedBox(height: 8),
          _settingsCard([
            _settingsTile(
              icon: Icons.language,
              title: s.language,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    locale.isArabic ? 'العربية' : 'English',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
              onTap: () => locale.toggleLanguage(),
            ),
          ]),

          const SizedBox(height: 20),

          // ── About Section ──
          _sectionHeader(s.about),
          const SizedBox(height: 8),
          _settingsCard([
            _settingsTile(
              icon: Icons.info_outline,
              title: s.appVersion,
              trailing: const Text(
                '1.0.0',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Logout ──
          _settingsCard([
            _settingsTile(
              icon: Icons.logout,
              title: s.logout,
              iconColor: AppColors.error,
              titleColor: AppColors.error,
              onTap: () => _showLogoutConfirm(context, auth, s),
            ),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.barlow(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 1,
      ),
    );
  }

  Widget _settingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, indent: 52),
          ],
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? AppColors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: titleColor ?? AppColors.textPrimary,
                ),
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, AuthProvider auth) {
    final s = S.of(context);
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool loading = false;
    bool obscureOld = true;
    bool obscureNew = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(s.changePassword),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: oldCtrl,
                  obscureText: obscureOld,
                  decoration: InputDecoration(
                    labelText: s.currentPassword,
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(obscureOld ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                      onPressed: () => setDialogState(() => obscureOld = !obscureOld),
                    ),
                  ),
                  validator: (v) => v == null || v.isEmpty ? s.required : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: s.newPassword,
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                      onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return s.required;
                    if (v.length < 6) return s.passwordTooShort;
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: s.confirmPassword,
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  ),
                  validator: (v) {
                    if (v != newCtrl.text) return s.passwordsMustMatch;
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: loading ? null : () async {
                if (!formKey.currentState!.validate()) return;
                setDialogState(() => loading = true);
                try {
                  if (auth.isStaff || auth.isCoach) {
                    await ApiService.staffUpdatePassword(oldCtrl.text, newCtrl.text);
                  } else {
                    await ApiService.updatePassword(oldCtrl.text, newCtrl.text);
                  }
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.passwordChanged)),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    setDialogState(() => loading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeEmailDialog(BuildContext context) {
    final s = S.of(context);
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(s.changeEmail),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: s.newEmail,
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return s.required;
                if (!v.contains('@') || !v.contains('.')) return s.invalidEmail;
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: loading ? null : () async {
                if (!formKey.currentState!.validate()) return;
                setDialogState(() => loading = true);
                try {
                  await ApiService.updateEmail(emailCtrl.text.trim());
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.emailUpdated)),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    setDialogState(() => loading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirm(BuildContext context, AuthProvider auth, S s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.logout),
        content: Text(s.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              auth.logout();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(s.logout),
          ),
        ],
      ),
    );
  }
}
