import '../../widgets/motion.dart';
import '../../widgets/email_suggestion.dart';
import '../../utils/app_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../widgets/brand_page.dart';
import '../../utils/translations.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';

/// First-time login onboarding: Email → Verify Code → Set Password
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0=email, 1=verify, 2=password
  bool _loading = false;
  String? _error;

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _verifiedEmail = '';
  String _verifiedCode = '';
  Timer? _resendTimer;
  int _resendSeconds = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendSeconds = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.sendVerificationCode(_emailController.text.trim());
      _verifiedEmail = _emailController.text.trim();
      _startResendTimer();
      if (mounted) setState(() => _step = 1);
    } catch (e) {
      if (mounted) setState(() => _error = AppError.messageFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendSeconds > 0) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.sendVerificationCode(_verifiedEmail);
      _startResendTimer();
      _codeController.clear();
    } catch (e) {
      if (mounted) setState(() => _error = AppError.messageFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = S.read(context).enterSixDigitCode);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final result = await ApiService.verifyCodeDetailed(_verifiedEmail, code);
      _verifiedCode = code;
      if (!mounted) return;
      if (result['joined_family'] == true) {
        // This parent already has a password: skip that step (Tesler's Law,
        // the system carries the complexity) and show all their swimmers.
        await context.read<AuthProvider>().joinedFamily((result['profiles'] as List?) ?? const []);
        return;
      }
      setState(() => _step = 2);
    } catch (e) {
      if (mounted) setState(() => _error = AppError.messageFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().completeOnboarding(
        _verifiedEmail, _verifiedCode, _passwordController.text,
      );
    } catch (e) {
      if (mounted) setState(() => _error = AppError.messageFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _passwordStrength {
    final pw = _passwordController.text;
    if (pw.isEmpty) return 0;
    int score = 0;
    if (pw.length >= 6) score++;
    if (pw.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw)) score++;
    if (RegExp(r'[0-9]').hasMatch(pw)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(pw)) score++;
    return score.clamp(0, 5);
  }

  Color get _strengthColor {
    return switch (_passwordStrength) {
      1 => AppColors.error,
      2 => AppColors.warning,
      3 => AppColors.accent,
      >= 4 => AppColors.success,
      _ => AppColors.textMuted,
    };
  }

  String get _strengthLabel {
    final s = S.of(context);
    return switch (_passwordStrength) {
      1 => s.weak,
      2 => s.fair,
      3 => s.good,
      4 => s.strong,
      5 => s.veryStrong,
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final titles = [s.setUpEmailTitle, s.checkEmailTitle, s.choosePasswordTitle];
    // Same shell as the login; the step count shows how close the end is
    // (Goal-Gradient Effect)
    return BrandPage(
      title: titles[_step],
      subtitle: s.stepOf(_step + 1, 3),
      onBack: () {
        if (_step > 0) {
          setState(() { _step--; _error = null; });
        } else {
          // Back on the first step logs out and returns to the login
          context.read<AuthProvider>().logout();
        }
      },
      child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      _buildStepIndicator(),
                      const SizedBox(height: 32),
                      // The next step comes in from the side it is on
                      StepSwitcher(
                        step: _step,
                        child: _step == 0
                            ? _buildEmailStep()
                            : _step == 1
                                ? _buildVerifyStep()
                                : _buildPasswordStep(),
                      ),
                      _buildErrorWidget(),
                      const SizedBox(height: 24),
                      _buildActionButton(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(3, (i) {
        final isActive = i <= _step;
        final isCurrent = i == _step;
        return Expanded(
          child: Container(
            margin: EdgeInsetsDirectional.only(end: i < 2 ? 8 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
            child: isCurrent
                ? TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 500),
                    builder: (_, v, __) => FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: v,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.15), width: 2),
            ),
            child: const Icon(Icons.email_outlined, size: 36, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          S.of(context).onboardingEmailIntro,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 15, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          textInputAction: TextInputAction.done,
          // An email is always typed left to right, in either language
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: S.of(context).email,
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            hintText: 'you@example.com',
          ),
          validator: (v) {
            final s = S.read(context);
            if (v == null || v.trim().isEmpty) return s.emailRequired;
            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) return s.invalidEmail;
            return null;
          },
          onFieldSubmitted: (_) => _sendCode(),
        ),
        // "Did you mean name@gmail.com?" One tap fixes it
        EmailSuggestion(controller: _emailController),
      ],
    );
  }

  Widget _buildVerifyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.15), width: 2),
            ),
            child: const Icon(Icons.mark_email_read_outlined, size: 36, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          S.of(context).codeSentToLabel,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 15, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          _verifiedEmail,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          autofocus: true,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.barlow(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 8),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '000000',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            if (v.length == 6) _verifyCode();
          },
        ),
        const SizedBox(height: 16),
        Center(
          child: _resendSeconds > 0
              ? Text(
                  S.of(context).resendCodeIn(_resendSeconds),
                  style: GoogleFonts.barlow(fontSize: 13, color: AppColors.textMuted),
                )
              : TextButton(
                  onPressed: _loading ? null : _resendCode,
                  child: Text(
                    S.of(context).resendCode,
                    style: GoogleFonts.barlow(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.15), width: 2),
            ),
            child: const Icon(Icons.lock_reset_rounded, size: 36, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          S.of(context).onboardingPasswordIntro,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 15, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: S.of(context).newPassword,
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (v) {
            if (v == null || v.length < 6) return S.read(context).passwordTooShort;
            return null;
          },
        ),
        if (_passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _passwordStrength / 5.0,
                    minHeight: 4,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(_strengthLabel, style: GoogleFonts.barlow(fontSize: 12, fontWeight: FontWeight.w600, color: _strengthColor)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            S.of(context).passwordTip,
            style: GoogleFonts.barlow(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: S.of(context).confirmPassword,
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (v) {
            if (v != _passwordController.text) return S.read(context).passwordsMustMatch;
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, style: GoogleFonts.barlow(color: AppColors.error, fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final s = S.of(context);
    final labels = [s.sendCode, s.checkCode, s.finishSetup];
    final actions = [_sendCode, _verifyCode, _setPassword];

    // Skip verify button on step 1 since auto-verify on 6 digits
    if (_step == 1) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _loading ? null : actions[_step],
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: _loading
              ? LinearGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.5),
                  AppColors.secondary.withValues(alpha: 0.5),
                ])
              : AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(labels[_step], style: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ),
    );
  }
}
