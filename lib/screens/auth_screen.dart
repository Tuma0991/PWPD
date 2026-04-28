// lib/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';

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
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ─── Hero Header ───────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 36),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF1E88E5), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(40),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.shield,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'GuardianNako',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Personal Wearable Protection Device',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Feature pills
                    Row(
                      children: [
                        _FeaturePill(icon: Icons.sensors, label: 'Fall Detection'),
                        const SizedBox(width: 8),
                        _FeaturePill(icon: Icons.gps_fixed, label: 'Live GPS'),
                        const SizedBox(width: 8),
                        _FeaturePill(icon: Icons.notifications_active, label: 'SOS Alerts'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ─── Auth Card ────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1565C0).withOpacity(0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tab bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicator: BoxDecoration(
                            color: const Color(0xFF1565C0),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1565C0).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          indicatorPadding: EdgeInsets.zero,
                          labelColor: Colors.white,
                          unselectedLabelColor: const Color(0xFF6B7A99),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          tabs: const [
                            Tab(text: 'Sign In'),
                            Tab(text: 'Register'),
                          ],
                        ),
                      ),
                    ),

                    // Error message
                    if (_errorMsg != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE53935).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Color(0xFFE53935), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMsg!,
                                  style: const TextStyle(
                                    color: Color(0xFFE53935),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Forms
                    SizedBox(
                      height: 420,
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
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          const Text(
            'Welcome back',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2340),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sign in to monitor your GuardianNemo and stay connected',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7A99),
            ),
          ),
          const SizedBox(height: 22),
          _GuardianTextField(
            controller: _loginEmailCtrl,
            label: 'Email address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _GuardianTextField(
            controller: _loginPassCtrl,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: _obscureLogin,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureLogin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: const Color(0xFF6B7A99),
                size: 20,
              ),
              onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Transform.scale(
                    scale: 0.85,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (v) => setState(() => _rememberMe = v ?? false),
                      activeColor: const Color(0xFF1565C0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const Text('Remember me',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99))),
                ],
              ),
              TextButton(
                onPressed: () async {
                  if (_loginEmailCtrl.text.isEmpty) {
                    _showError('Enter your email first');
                    return;
                  }
                  try {
                    await _firebase.resetPassword(_loginEmailCtrl.text.trim());
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password reset email sent!')),
                      );
                    }
                  } catch (_) {
                    _showError('Failed to send reset email.');
                  }
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: Color(0xFF1565C0),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _GuardianButton(
            label: 'Sign In',
            loading: _loading,
            onPressed: _login,
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          const Text(
            'Create account',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2340),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Set up GuardianNako and connect your GuardianNemo',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7A99),
            ),
          ),
          const SizedBox(height: 22),
          _GuardianTextField(
            controller: _regNameCtrl,
            label: 'Full Name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 14),
          _GuardianTextField(
            controller: _regEmailCtrl,
            label: 'Email address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _GuardianTextField(
            controller: _regPassCtrl,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: _obscureReg,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureReg ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: const Color(0xFF6B7A99),
                size: 20,
              ),
              onPressed: () => setState(() => _obscureReg = !_obscureReg),
            ),
          ),
          const SizedBox(height: 14),
          _GuardianTextField(
            controller: _regConfirmPassCtrl,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
            obscureText: _obscureReg,
          ),
          const SizedBox(height: 20),
          _GuardianButton(
            label: 'Create Account',
            loading: _loading,
            onPressed: _register,
          ),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ────────────────────────────────────────────────────────

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardianTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;

  const _GuardianTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF1A2340),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF6B7A99),
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF1565C0), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF7F9FF),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDDE3F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _GuardianButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const _GuardianButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}