import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../widgets/press_feedback.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  late AnimationController _entranceController;
  late Animation<double> _iconFade;
  late Animation<double> _iconScale;
  late Animation<double> _descFade;
  late Animation<Offset> _descSlide;
  late Animation<double> _field1Fade;
  late Animation<Offset> _field1Slide;
  late Animation<double> _field2Fade;
  late Animation<Offset> _field2Slide;
  late Animation<double> _buttonFade;
  late Animation<Offset> _buttonSlide;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _iconFade = _buildFade(0.0, 0.25);
    _iconScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.35, curve: Curves.elasticOut),
      ),
    );
    _descFade = _buildFade(0.1, 0.35);
    _descSlide = _buildSlide(0.1, 0.35);
    _field1Fade = _buildFade(0.25, 0.55);
    _field1Slide = _buildSlide(0.25, 0.55);
    _field2Fade = _buildFade(0.4, 0.7);
    _field2Slide = _buildSlide(0.4, 0.7);
    _buttonFade = _buildFade(0.55, 0.85);
    _buttonSlide = _buildSlide(0.55, 0.85);

    _entranceController.forward();
  }

  Animation<double> _buildFade(double begin, double end) {
    return Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(begin, end, curve: AppAnimation.enterCurve),
      ),
    );
  }

  Animation<Offset> _buildSlide(double begin, double end) {
    return Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(begin, end, curve: AppAnimation.enterCurve),
      ),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read<AuthProvider>().changePassword(_passwordController.text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
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
    switch (_passwordStrength) {
      case 0:
        return AppColors.textMuted;
      case 1:
        return AppColors.error;
      case 2:
        return AppColors.warning;
      case 3:
        return AppColors.accent;
      case 4:
        return AppColors.success;
      case 5:
        return AppColors.success;
      default:
        return AppColors.textMuted;
    }
  }

  String _strengthLabel(S s) {
    switch (_passwordStrength) {
      case 0:
        return '';
      case 1:
        return s.weak;
      case 2:
        return s.fair;
      case 3:
        return s.good;
      case 4:
        return s.strong;
      case 5:
        return s.veryStrong;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Gradient header with wave
          Builder(builder: (context) {
            final screenH = MediaQuery.of(context).size.height;
            final headerH = (screenH * 0.22).clamp(150.0, 200.0);
            return ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: headerH,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 20),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 4),
                        Image.asset('assets/images/logo.png', height: 36, width: 36),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            s.changePassword,
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // Form body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),

                      // Lock icon
                      FadeTransition(
                        opacity: _iconFade,
                        child: ScaleTransition(
                          scale: _iconScale,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                width: 2,
                              ),
                            ),
                            child: const Icon(Icons.lock_reset_rounded,
                                size: 36, color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Description
                      FadeTransition(
                        opacity: _descFade,
                        child: SlideTransition(
                          position: _descSlide,
                          child: Text(
                            s.createNewPassword,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.barlow(
                              fontSize: 15,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // New Password
                      FadeTransition(
                        opacity: _field1Fade,
                        child: SlideTransition(
                          position: _field1Slide,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: s.newPassword,
                                  prefixIcon: const Icon(
                                      Icons.lock_outline,
                                      size: 20),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.length < 6) {
                                    return s.passwordTooShort;
                                  }
                                  return null;
                                },
                              ),
                              // Password strength indicator
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
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  _strengthColor),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _strengthLabel(s),
                                      style: GoogleFonts.barlow(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _strengthColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Use 6+ characters with uppercase, numbers & symbols',
                                  style: GoogleFonts.barlow(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Confirm Password
                      FadeTransition(
                        opacity: _field2Fade,
                        child: SlideTransition(
                          position: _field2Slide,
                          child: TextFormField(
                            controller: _confirmController,
                            obscureText: _obscureConfirm,
                            decoration: InputDecoration(
                              labelText: s.confirmPassword,
                              prefixIcon: const Icon(
                                  Icons.lock_outline, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm),
                              ),
                            ),
                            validator: (v) {
                              if (v != _passwordController.text) {
                                return s.passwordsMustMatch;
                              }
                              return null;
                            },
                          ),
                        ),
                      ),

                      // Error display
                      AnimatedSize(
                        duration: AppAnimation.normalDuration,
                        curve: AppAnimation.enterCurve,
                        alignment: Alignment.topCenter,
                        child: _error != null
                            ? AnimatedSwitcher(
                                duration: AppAnimation.normalDuration,
                                transitionBuilder: (child, animation) {
                                  return SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, -0.3),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(
                                      parent: animation,
                                      curve: AppAnimation.enterCurve,
                                    )),
                                    child: FadeTransition(
                                        opacity: animation, child: child),
                                  );
                                },
                                child: Padding(
                                  key: ValueKey(_error),
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorLight,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.error
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline,
                                            size: 18, color: AppColors.error),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _error!,
                                            style: GoogleFonts.barlow(
                                              color: AppColors.error,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 24),

                      // Submit button
                      FadeTransition(
                        opacity: _buttonFade,
                        child: SlideTransition(
                          position: _buttonSlide,
                          child: PressFeedback(
                            onTap: _loading ? null : _submit,
                            scaleFactor: 0.96,
                            child: Container(
                              width: double.infinity,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: _loading
                                    ? LinearGradient(colors: [
                                        AppColors.primary
                                            .withValues(alpha: 0.5),
                                        AppColors.secondary
                                            .withValues(alpha: 0.5),
                                      ])
                                    : AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: _loading
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: Center(
                                child: _loading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        s.setPassword,
                                        style: GoogleFonts.barlow(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom clipper that creates a wave shape at the bottom of the header.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 30);

    final firstControl = Offset(size.width * 0.25, size.height);
    final firstEnd = Offset(size.width * 0.5, size.height - 15);
    path.quadraticBezierTo(
        firstControl.dx, firstControl.dy, firstEnd.dx, firstEnd.dy);

    final secondControl = Offset(size.width * 0.75, size.height - 30);
    final secondEnd = Offset(size.width, size.height - 10);
    path.quadraticBezierTo(
        secondControl.dx, secondControl.dy, secondEnd.dx, secondEnd.dy);

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
