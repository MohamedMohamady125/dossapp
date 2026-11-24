import '../../widgets/motion.dart';
import '../../utils/app_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../widgets/brand_page.dart';
import '../../widgets/email_suggestion.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import 'forgot_password_screen.dart';

/// The first screen anyone sees.
///
/// Built like the sign-in of a bank or delivery app: a white page, the crest,
/// one title, two labelled fields and one solid button. Nothing decorative,
/// so the only thing that stands out is the button (Von Restorff Effect).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _fieldBorder = Color(0xFFCBD5E1);

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _isAdmin = false;
  bool _loading = false;
  String? _error;
  bool _obscure = true;
  // Only complain about empty fields after a first attempt, not while typing
  bool _triedOnce = false;

  int _logoTapCount = 0;
  DateTime? _lastLogoTap;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() => _triedOnce = true);
    // Postel's Law: drop stray spaces and a comma typed for a dot
    if (!_isAdmin && EmailCheck.looksLikeEmail(_codeController.text)) {
      final cleaned = EmailCheck.clean(_codeController.text);
      if (cleaned != _codeController.text) _codeController.text = cleaned;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      if (_isAdmin) {
        await auth.adminLogin(
            _codeController.text.trim(), _passwordController.text);
      } else {
        await auth.customerLogin(
            _codeController.text.trim(), _passwordController.text);
      }
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) {
        final s = S.read(context);
        final typed = _codeController.text.trim();
        String translated;
        if (e is ApiException && e.statusCode == 401) {
          // Say which thing was wrong: staff name, email or login code
          final fix = EmailCheck.suggestion(typed);
          translated = _isAdmin
              ? s.wrongStaffLogin
              : !EmailCheck.looksLikeEmail(typed)
                  ? s.wrongCodeOrPassword
                  : fix != null
                      ? s.wrongEmailMaybe(fix)
                      : s.wrongEmailOrPassword;
        } else {
          translated = AppError.messageFor(e);
        }
        setState(() => _error = translated);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showForgotPassword() {
    _logoTapCount = 0;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  // Five taps on the crest opens the staff login
  void _onLogoTap() {
    final now = DateTime.now();
    if (_lastLogoTap != null && now.difference(_lastLogoTap!).inSeconds > 10) {
      _logoTapCount = 0;
    }
    _lastLogoTap = now;
    _logoTapCount++;
    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      HapticFeedback.selectionClick();
      setState(() {
        _isAdmin = true;
        _error = null;
      });
    }
  }

  InputDecoration _decoration({Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      hoverColor: Colors.transparent,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: border(_fieldBorder),
      focusedBorder: border(AppColors.primary, 1.5),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 1.5),
      errorStyle: GoogleFonts.barlow(fontSize: 13, color: AppColors.error),
      errorMaxLines: 2,
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minHeight: 44, minWidth: 44),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: GoogleFonts.barlow(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sessionExpired = context.watch<AuthProvider>().sessionExpired;
    final validateMode = _triedOnce
        ? AutovalidateMode.onUserInteraction
        : AutovalidateMode.disabled;
    final inputStyle = GoogleFonts.barlow(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
    );

    return BrandPage(
      title: _isAdmin ? s.staffLogin : s.login,
      subtitle: _isAdmin ? s.staffLoginSubtitle : s.loginSubtitle,
      // Five taps on the crest opens the staff login
      onCrestTap: _onLogoTap,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                              // Signed out by the server: say so once, quietly
                              if (_error == null && sessionExpired)
                                _Notice(
                                  text: s.sessionExpired,
                                  color: AppColors.textSecondary,
                                  background: AppColors.surfaceVariant,
                                  icon: Icons.info_outline_rounded,
                                ),

                              // Labels sit above the fields so they stay
                              // readable while typing (Working Memory)
                              _label(_isAdmin ? s.username : s.loginCodeOrEmail),
                              TextFormField(
                                controller: _codeController,
                                // Codes and emails read left to right in both languages
                                textDirection: TextDirection.ltr,
                                style: inputStyle,
                                autovalidateMode: validateMode,
                                // Postel's Law: take the code or the email, any case
                                keyboardType: _isAdmin
                                    ? TextInputType.text
                                    : TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [AutofillHints.username],
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                                decoration: _decoration(),
                                onChanged: (_) {
                                  if (_error != null) setState(() => _error = null);
                                },
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return s.required;
                                  if (!_isAdmin &&
                                      EmailCheck.looksLikeEmail(v) &&
                                      !EmailCheck.isValid(v)) {
                                    return s.emailLooksWrong;
                                  }
                                  return null;
                                },
                              ),
                              // "Did you mean name@gmail.com?" One tap fixes it
                              if (!_isAdmin)
                                EmailSuggestion(controller: _codeController),
                              if (!_isAdmin)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    s.loginHelp,
                                    style: GoogleFonts.barlow(
                                      fontSize: 13,
                                      height: 1.35,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 20),

                              // Password label and the way out share one line
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(child: _label(s.password)),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: InkWell(
                                      onTap: _showForgotPassword,
                                      canRequestFocus: false,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 2),
                                        child: Text(
                                          s.forgotPassword,
                                          style: GoogleFonts.barlow(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              TextFormField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                obscureText: _obscure,
                                style: inputStyle,
                                autovalidateMode: validateMode,
                                textInputAction: TextInputAction.done,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [AutofillHints.password],
                                decoration: _decoration(
                                  suffix: TextButton(
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14),
                                      minimumSize: const Size(44, 44),
                                      textStyle: GoogleFonts.barlow(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    child: Text(_obscure
                                        ? s.showPassword
                                        : s.hidePassword),
                                  ),
                                ),
                                validator: (v) =>
                                    v == null || v.isEmpty ? s.required : null,
                                onFieldSubmitted: (_) => _login(),
                              ),

                              AnimatedSize(
                                duration: AppAnimation.normalDuration,
                                curve: AppAnimation.enterCurve,
                                alignment: Alignment.topCenter,
                                child: _error == null
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: _Notice(
                                          text: _error!,
                                          color: AppColors.error,
                                          background: AppColors.errorLight,
                                          icon: Icons.error_outline_rounded,
                                          bottomGap: 0,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 24),

                              // The one solid thing on the page
                              SizedBox(
                                height: 54,
                                child: FilledButton(
                                  onPressed: _loading ? null : _login,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    disabledBackgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    disabledForegroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    textStyle: GoogleFonts.barlow(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: Motion.fast,
                                    child: _loading
                                        ? const SizedBox(
                                            key: ValueKey('busy'),
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(s.login, key: const ValueKey('label')),
                                  ),
                                ),
                              ),

                              if (_isAdmin)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextButton(
                                    onPressed: () => setState(() {
                                      _isAdmin = false;
                                      _error = null;
                                    }),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.textSecondary,
                                      minimumSize: const Size(0, 44),
                                      textStyle: GoogleFonts.barlow(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    child: Text(s.backToParentLogin),
                                  ),
                                ),

                              const Spacer(),
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 32, bottom: 16),
                                child: Text(
                                  '${s.appName} ${s.swimmingAcademy}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.barlow(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One quiet line with an icon: a login error, or "you were logged out".
class _Notice extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final IconData icon;
  final double bottomGap;

  const _Notice({
    required this.text,
    required this.color,
    required this.background,
    required this.icon,
    this.bottomGap = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: bottomGap),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.barlow(
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
