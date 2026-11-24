import '../../widgets/motion.dart';
import '../../widgets/email_suggestion.dart';
import '../../utils/app_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/brand_page.dart';
import '../../utils/translations.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

/// Forgot password flow: Email → Verify Code → New Password
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 0; // 0=email, 1=verify, 2=password
  bool _loading = false;
  String? _error;
  bool _success = false;

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _email = '';
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
      _email = _emailController.text.trim();
      await ApiService.forgotPasswordSendCode(_email);
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
      await ApiService.forgotPasswordSendCode(_email);
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
      await ApiService.forgotPasswordVerify(_email, code);
      _verifiedCode = code;
      if (mounted) setState(() => _step = 2);
    } catch (e) {
      if (mounted) setState(() => _error = AppError.messageFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.forgotPasswordReset(
        _email, _verifiedCode, _passwordController.text,
      );
      if (mounted) setState(() => _success = true);
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
    return switch (_passwordStrength) {
      1 => S.of(context).weak,
      2 => S.of(context).fair,
      3 => S.of(context).good,
      4 => S.of(context).strong,
      5 => S.of(context).veryStrong,
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_success) return _buildSuccessScreen();

    final s = S.of(context);
    final titles = [s.forgotPasswordTitle, s.checkEmailTitle, s.newPassword];
    // Same shell as the login; the step count shows how close the end is
    // (Goal-Gradient Effect)
    return BrandPage(
      title: titles[_step],
      subtitle: s.stepOf(_step + 1, 3),
      onBack: () {
        if (_step > 0) {
          setState(() { _step--; _error = null; });
        } else {
          Navigator.pop(context);
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
        return Expanded(
          child: Container(
            margin: EdgeInsetsDirectional.only(end: i < 2 ? 6 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildEmailStep() {
    return Column(
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
          S.of(context).forgotEmailIntro,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 15, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          textInputAction: TextInputAction.done,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: S.of(context).email,
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            hintText: 'you@example.com',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return S.read(context).emailRequired;
            if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(v.trim())) return S.read(context).invalidEmail;
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
          S.of(context).enterCodeSentTo,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 15, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          _email,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
          S.of(context).chooseNewPasswordIntro,
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
    // Skip button on verify step (auto-verify on 6 digits)
    if (_step == 1) return const SizedBox.shrink();

    final labels = [S.of(context).sendCode, '', S.of(context).setPassword];
    final actions = [_sendCode, _verifyCode, _resetPassword];

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

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, size: 48, color: AppColors.success),
              ),
              const SizedBox(height: 24),
              Text(
                S.of(context).passwordChanged,
                style: GoogleFonts.barlow(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                S.of(context).passwordResetMsg,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlow(fontSize: 15, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(S.of(context).backToLogin, style: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
