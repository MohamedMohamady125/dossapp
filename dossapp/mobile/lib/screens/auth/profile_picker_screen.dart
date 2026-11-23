import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../widgets/language_toggle.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../widgets/ui_kit.dart';

/// Shown once after sign-in when the parent's email has several swimmers.
/// One question, one tap (Hick's Law): each swimmer is a full-width card.
class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  int? _opening;

  Future<void> _open(SwimmerProfile p) async {
    setState(() => _opening = p.accountId);
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final fallback = S.read(context).somethingWentWrong;
    try {
      await auth.chooseProfile(p.accountId);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : fallback)));
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final auth = context.watch<AuthProvider>();
    final profiles = auth.profiles;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Same navy header as the home screen, so it reads as one app
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.family_restroom_rounded, color: Colors.white, size: 28),
                        ),
                        const LanguageToggle(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.whoIsSwimming,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.chooseSwimmerSubtitle,
                      style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                for (final p in profiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SwimmerCard(
                      profile: p,
                      busy: _opening == p.accountId,
                      enabled: _opening == null,
                      onTap: () => _open(p),
                    ),
                  ),
                const SizedBox(height: 8),
                // Teach the switcher here, where the question is on their mind
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.switchAnytime,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: TextButton(
              onPressed: _opening == null ? () => auth.logout() : null,
              child: Text(s.logout),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwimmerCard extends StatelessWidget {
  final SwimmerProfile profile;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  const _SwimmerCard({required this.profile, required this.busy, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          // 88px tall: an easy target for a thumb (Fitts's Law)
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              InitialsAvatar(profile.name, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.branchName} • #${profile.athleteNumber}',
                      style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The switcher opened from the home header: the family's swimmers, the
/// current one ticked. Tapping another opens it straight away.
Future<void> showSwimmerSwitcher(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SwitcherSheet(),
  );
}

class _SwitcherSheet extends StatefulWidget {
  const _SwitcherSheet();

  @override
  State<_SwitcherSheet> createState() => _SwitcherSheetState();
}

class _SwitcherSheetState extends State<_SwitcherSheet> {
  int? _opening;

  Future<void> _open(SwimmerProfile p) async {
    final s = S.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (p.isCurrent) {
      navigator.pop();
      return;
    }
    setState(() => _opening = p.accountId);
    try {
      await context.read<AuthProvider>().chooseProfile(p.accountId);
      navigator.pop();
      // Confirm what changed, in words (Doherty Threshold: immediate feedback)
      messenger.showSnackBar(SnackBar(
        content: Text(s.nowViewing(p.name)),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : s.somethingWentWrong)));
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final profiles = context.watch<AuthProvider>().profiles;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                s.switchSwimmer,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ),
            for (final p in profiles)
              InkWell(
                onTap: _opening == null ? () => _open(p) : null,
                child: Container(
                  color: p.isCurrent ? AppColors.primarySurface.withValues(alpha: 0.6) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      InitialsAvatar(p.name, size: 46),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            Text(
                              p.isCurrent
                                  ? s.viewingNow
                                  : '${p.branchName} • #${p.athleteNumber}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: p.isCurrent ? FontWeight.w600 : FontWeight.w400,
                                color: p.isCurrent ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_opening == p.accountId)
                        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      else if (p.isCurrent)
                        const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                      else
                        const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1, color: AppColors.border),
            InkWell(
              onTap: _opening == null
                  ? () {
                      final rootContext = Navigator.of(context, rootNavigator: true).context;
                      Navigator.of(context).pop();
                      showAddSwimmerSheet(rootContext);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 46, height: 46,
                      decoration: const BoxDecoration(color: AppColors.primarySurface, shape: BoxShape.circle),
                      child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        s.addSwimmer,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// A parent who is already signed in adds another child with the login code
/// and password the front desk gave for that child. Two fields, one button
/// (Hick's Law); no email step, because this parent's email is already proven.
Future<void> showAddSwimmerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _AddSwimmerSheet(),
  );
}

class _AddSwimmerSheet extends StatefulWidget {
  const _AddSwimmerSheet();

  @override
  State<_AddSwimmerSheet> createState() => _AddSwimmerSheetState();
}

class _AddSwimmerSheetState extends State<_AddSwimmerSheet> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.read(context);
    if (_code.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = s.fillCodeAndPassword);
      return;
    }
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() { _busy = true; _error = null; });
    try {
      final name = await auth.addSwimmer(_code.text, _password.text);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.swimmerAdded(name))));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : s.somethingWentWrong;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      // Keep the button above the keyboard
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(
                  s.addSwimmer,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  s.addSwimmerHelp,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  enabled: !_busy,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: s.loginCode,
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _hide,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: s.password,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(fontSize: 14, color: AppColors.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(s.addSwimmerButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
