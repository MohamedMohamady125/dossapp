import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isAdmin = false;
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final auth = context.read<AuthProvider>();
      if (_isAdmin) {
        await auth.adminLogin(_codeController.text.trim(), _passwordController.text);
      } else {
        await auth.customerLogin(_codeController.text.trim(), _passwordController.text);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 40),
                    // Logo
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: const Icon(Icons.pool, size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    const Text('Aqua Athletic', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    const Text('Swimming Academy', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    const SizedBox(height: 40),

                    // Toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          _tabButton('Parent / Athlete', !_isAdmin, () => setState(() => _isAdmin = false)),
                          _tabButton('Staff', _isAdmin, () => setState(() => _isAdmin = true)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    TextFormField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: _isAdmin ? 'Username' : 'Login Code',
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      onFieldSubmitted: (_) => _login(),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Log In'),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)] : null,
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
