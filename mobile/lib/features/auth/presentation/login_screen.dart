import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/brand/app_brand.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _createAccount = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(authStateProvider.notifier);
    final success = _createAccount && AppConfig.useFirebase
        ? await notifier.register(_emailController.text.trim(), _passwordController.text)
        : await notifier.login(_emailController.text.trim(), _passwordController.text);

    if (!success && mounted) {
      final error = ref.read(authStateProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Invalid credentials. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppBrand.accent.withValues(alpha: 0.06),
              AppTheme.background,
              AppTheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const BrandLogo(
                      size: 96,
                      showTagline: true,
                      tagline: AppBrand.taglineLogin,
                      useRasterIcon: true,
                    ),
                    if (AppConfig.useFirebase) ...[
                      const SizedBox(height: 8),
                      Text(
                        AppBrand.tagline,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppBrand.accent.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) =>
                        v != null && v.contains('@') ? null : 'Enter a valid email',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) =>
                        v != null && v.length >= 8 ? null : 'Minimum 8 characters',
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: authState.isLoading ? null : _handleSubmit,
                      child: authState.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_createAccount && AppConfig.useFirebase ? 'Create account' : 'Sign In'),
                    ),
                  ),
                  if (AppConfig.useFirebase) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: authState.isLoading
                          ? null
                          : () => setState(() => _createAccount = !_createAccount),
                      child: Text(
                        _createAccount
                            ? 'Already have an account? Sign in'
                            : 'New enumerator? Create account',
                      ),
                    ),
                  ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
