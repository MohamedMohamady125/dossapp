import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/locale_provider.dart';
import '../../utils/theme.dart';
import '../../utils/translations.dart';
import '../../widgets/press_feedback.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isAdmin = false;
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  late AnimationController _entranceController;
  late AnimationController _logoController;
  late Animation<double> _logoScale;
  late Animation<double> _headerFade;
  late Animation<double> _toggleFade;
  late Animation<double> _field1Fade;
  late Animation<double> _field2Fade;
  late Animation<double> _buttonFade;
  late Animation<Offset> _headerSlide;
  late Animation<Offset> _toggleSlide;
  late Animation<Offset> _field1Slide;
  late Animation<Offset> _field2Slide;
  late Animation<Offset> _buttonSlide;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: AppAnimation.bounceCurve),
    );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _headerFade = _buildFade(0.0, 0.3);
    _headerSlide = _buildSlide(0.0, 0.3);
    _toggleFade = _buildFade(0.15, 0.45);
    _toggleSlide = _buildSlide(0.15, 0.45);
    _field1Fade = _buildFade(0.3, 0.6);
    _field1Slide = _buildSlide(0.3, 0.6);
    _field2Fade = _buildFade(0.45, 0.75);
    _field2Slide = _buildSlide(0.45, 0.75);
    _buttonFade = _buildFade(0.6, 0.9);
    _buttonSlide = _buildSlide(0.6, 0.9);

    _logoController.forward();
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
    _logoController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
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
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Wave gradient header
            LayoutBuilder(builder: (context, constraints) {
              final screenH = MediaQuery.of(context).size.height;
              final headerH = (screenH * 0.3).clamp(200.0, 280.0);
              final logoSize = (headerH * 0.28).clamp(56.0, 80.0);
              return ClipPath(
                clipper: _WaveClipper(),
                child: Container(
                  height: headerH,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                  ),
                  child: SafeArea(
                    child: Stack(
                      children: [
                        // Language toggle top right
                        Positioned(
                          top: 4,
                          right: 16,
                          child: GestureDetector(
                            onTap: () => locale.toggleLanguage(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                locale.isArabic ? 'EN' : 'ع',
                                style: GoogleFonts.barlow(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Animated logo
                              ScaleTransition(
                                scale: _logoScale,
                                child: Container(
                                  width: logoSize,
                                  height: logoSize,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(logoSize * 0.27),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(logoSize * 0.27),
                                    child: Padding(
                                      padding: EdgeInsets.all(logoSize * 0.1),
                                      child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: headerH * 0.05),
                              FadeTransition(
                                opacity: _headerFade,
                                child: SlideTransition(
                                  position: _headerSlide,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      s.appName,
                                      style: GoogleFonts.barlowCondensed(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              FadeTransition(
                                opacity: _headerFade,
                                child: SlideTransition(
                                  position: _headerSlide,
                                  child: Text(
                                    s.swimmingAcademy,
                                    style: GoogleFonts.barlow(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            // Form
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),

                      // Toggle
                      FadeTransition(
                        opacity: _toggleFade,
                        child: SlideTransition(
                          position: _toggleSlide,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Row(
                              children: [
                                _tabButton(s.parentAthlete, !_isAdmin,
                                    () => setState(() => _isAdmin = false)),
                                _tabButton(s.staff, _isAdmin,
                                    () => setState(() => _isAdmin = true)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Code / Username field
                      FadeTransition(
                        opacity: _field1Fade,
                        child: SlideTransition(
                          position: _field1Slide,
                          child: TextFormField(
                            controller: _codeController,
                            decoration: InputDecoration(
                              labelText:
                                  _isAdmin ? s.username : s.loginCode,
                              prefixIcon: const Icon(Icons.person_outline,
                                  size: 20),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? s.required
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      FadeTransition(
                        opacity: _field2Fade,
                        child: SlideTransition(
                          position: _field2Slide,
                          child: TextFormField(
                            controller: _passwordController,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: s.password,
                              prefixIcon:
                                  const Icon(Icons.lock_outline, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? s.required : null,
                            onFieldSubmitted: (_) => _login(),
                          ),
                        ),
                      ),

                      // Forgot password link
                      FadeTransition(
                        opacity: _field2Fade,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: _showForgotPassword,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              s.forgotPassword,
                              style: GoogleFonts.barlow(
                                fontSize: 13,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Error display with slide-in
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
                                  padding: const EdgeInsets.only(top: 8),
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

                      const SizedBox(height: 20),

                      // Login button with gradient + press feedback
                      FadeTransition(
                        opacity: _buttonFade,
                        child: SlideTransition(
                          position: _buttonSlide,
                          child: PressFeedback(
                            onTap: _loading ? null : _login,
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
                                        s.login,
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
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: PressFeedback(
        onTap: onTap,
        scaleFactor: 0.97,
        child: AnimatedContainer(
          duration: AppAnimation.normalDuration,
          curve: AppAnimation.enterCurve,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 8),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom clipper that creates a wave shape at the bottom of the header.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 40);

    final firstControl = Offset(size.width * 0.25, size.height);
    final firstEnd = Offset(size.width * 0.5, size.height - 20);
    path.quadraticBezierTo(
        firstControl.dx, firstControl.dy, firstEnd.dx, firstEnd.dy);

    final secondControl = Offset(size.width * 0.75, size.height - 40);
    final secondEnd = Offset(size.width, size.height - 15);
    path.quadraticBezierTo(
        secondControl.dx, secondControl.dy, secondEnd.dx, secondEnd.dy);

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
