// lib/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _firebase = FirebaseService();
  late TabController _tabController;

  // Login controllers
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();

  // Register controllers
  final _regNameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  final _regConfirmPassCtrl = TextEditingController();

  bool _loading = false;
  bool _obscureLogin = true;
  bool _obscureReg = true;
  bool _rememberMe = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _regNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    _regConfirmPassCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    setState(() => _errorMsg = msg);
    Future.delayed(const Duration(seconds: 4),
        () => mounted ? setState(() => _errorMsg = null) : null);
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('savedEmail') ?? '';
    if (!mounted) return;
    setState(() {
      _loginEmailCtrl.text = savedEmail;
      _rememberMe = savedEmail.isNotEmpty;
    });
  }

  Future<void> _saveEmailPreference(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedEmail', email);
  }

  Future<void> _clearSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('savedEmail');
  }

  Future<void> _login() async {
    if (_loginEmailCtrl.text.isEmpty || _loginPassCtrl.text.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }
    setState(() => _loading = true);
    try {
      await _firebase.signIn(_loginEmailCtrl.text.trim(), _loginPassCtrl.text);
      if (_rememberMe) {
        await _saveEmailPreference(_loginEmailCtrl.text.trim());
      } else {
        await _clearSavedEmail();
      }
      // Let _AuthGate handle navigation when auth state changes.
    } catch (e) {
      _showError(_parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (_regNameCtrl.text.isEmpty ||
        _regEmailCtrl.text.isEmpty ||
        _regPassCtrl.text.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }
    if (_regPassCtrl.text != _regConfirmPassCtrl.text) {
      _showError('Passwords do not match');
      return;
    }
    if (_regPassCtrl.text.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }
    setState(() => _loading = true);
    try {
      await _firebase.register(
        _regEmailCtrl.text.trim(),
        _regPassCtrl.text,
        _regNameCtrl.text.trim(),
      );
      // Let _AuthGate handle navigation when auth state changes.
    } catch (e) {
      _showError(_parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(String error) {
    if (error.contains('user-not-found')) return 'No account found with this email.';
    if (error.contains('wrong-password')) return 'Incorrect password.';
    if (error.contains('email-already-in-use')) return 'Email already registered.';
    if (error.contains('invalid-email')) return 'Invalid email address.';
    if (error.contains('network-request-failed')) return 'Network error. Check connection.';
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top Banner ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primary, AppTheme.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Guardian',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w800,
                      fontSize: 32,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Secure your wearable and stay connected with live alerts.',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: AppTheme.cardShadow,
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      indicator: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      indicatorPadding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 4,
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppTheme.textSecondary,
                      labelStyle: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      tabs: const [
                        Tab(text: 'Login'),
                        Tab(text: 'Register'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        Expanded(
                          child: _FeatureChip(
                            icon: Icons.flash_on,
                            label: 'Fast login',
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _FeatureChip(
                            icon: Icons.lock,
                            label: 'Secure',
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _FeatureChip(
                            icon: Icons.check_circle,
                            label: 'Easy setup',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_errorMsg != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppTheme.danger.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppTheme.danger, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMsg!,
                                style: const TextStyle(
                                  color: AppTheme.danger,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildLoginForm(),
                          _buildRegisterForm(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Welcome back',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Login to manage your wearable device, alerts, and contacts.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _loginEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _loginPassCtrl,
              obscureText: _obscureLogin,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscureLogin
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () =>
                      setState(() => _obscureLogin = !_obscureLogin),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              visualDensity: const VisualDensity(vertical: -4),
              controlAffinity: ListTileControlAffinity.leading,
              value: _rememberMe,
              onChanged: (value) =>
                  setState(() => _rememberMe = value ?? false),
              title: const Text('Remember my email'),
              subtitle: const Text('Prefill your email next time on this device'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  if (_loginEmailCtrl.text.isEmpty) {
                    _showError('Enter your email first');
                    return;
                  }
                  try {
                    await _firebase.resetPassword(_loginEmailCtrl.text.trim());
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Password reset email sent!')),
                      );
                    }
                  } catch (_) {
                    _showError('Failed to send reset email.');
                  }
                },
                child: const Text('Forgot Password?',
                    style: TextStyle(color: AppTheme.primary, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Login', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Need help? Contact support if you have trouble logging in.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withOpacity(0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterForm() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Create account',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Set up your account and connect your wearable device in a few steps.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _regNameCtrl,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: const Icon(Icons.person_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _regEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _regPassCtrl,
              obscureText: _obscureReg,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscureReg
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscureReg = !_obscureReg),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _regConfirmPassCtrl,
              obscureText: _obscureReg,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Create Account', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'A secure login keeps your wearable and alerts protected.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withOpacity(0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
