// lib/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  // Inline field-level validation errors (shown beneath each input).
  String? _loginEmailError;
  String? _loginPassError;
  String? _regNameError;
  String? _regEmailError;
  String? _regPassError;
  String? _regConfirmError;

  static final RegExp _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

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

  // ─── Client-side validation ──────────────────────────────────────────────

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    final pass = value ?? '';
    if (pass.isEmpty) return 'Password is required';
    if (pass.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(pass)) return 'Add an uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(pass)) return 'Add a lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(pass)) return 'Add a number';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(pass)) {
      return 'Add a symbol (e.g. !@#\$%)';
    }
    return null;
  }

  bool _validateLoginFields() {
    final emailError = _validateEmail(_loginEmailCtrl.text);
    final passError =
        _loginPassCtrl.text.isEmpty ? 'Password is required' : null;
    setState(() {
      _loginEmailError = emailError;
      _loginPassError = passError;
    });
    return emailError == null && passError == null;
  }

  bool _validateRegisterFields() {
    final name = _regNameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final pass = _regPassCtrl.text;
    final confirm = _regConfirmPassCtrl.text;

    String? nameError;
    if (name.isEmpty) {
      nameError = 'Full name is required';
    } else if (name.length < 2) {
      nameError = 'Name must be at least 2 characters';
    }

    final emailError = _validateEmail(email);
    final passError = _validatePassword(pass);

    String? confirmError;
    if (confirm.isEmpty) {
      confirmError = 'Confirm your password';
    } else if (passError == null && confirm != pass) {
      confirmError = 'Passwords do not match';
    }

    setState(() {
      _regNameError = nameError;
      _regEmailError = emailError;
      _regPassError = passError;
      _regConfirmError = confirmError;
    });
    return nameError == null &&
        emailError == null &&
        passError == null &&
        confirmError == null;
  }

  // ─── Auth actions ────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (!_validateLoginFields()) return;
    setState(() => _loading = true);
    try {
      await _firebase.signIn(_loginEmailCtrl.text.trim(), _loginPassCtrl.text);
      if (_rememberMe) {
        await _saveEmailPreference(_loginEmailCtrl.text.trim());
      } else {
        await _clearSavedEmail();
      }
    } catch (e) {
      _handleLoginError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (!_validateRegisterFields()) return;
    setState(() => _loading = true);
    try {
      await _firebase.register(
        _regEmailCtrl.text.trim(),
        _regPassCtrl.text,
        _regNameCtrl.text.trim(),
      );
    } catch (e) {
      _handleRegisterError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _loading = true);
    try {
      await _firebase.signInWithGoogle();
      // On success the _AuthGate auto-navigates to HomeScreen.
    } catch (e) {
      _showError(_parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Error handling ──────────────────────────────────────────────────────

  /// Maps sign-in failures onto the relevant field so the user sees exactly
  /// which credential is wrong, rather than a generic banner.
  void _handleLoginError(Object e) {
    final msg = e.toString();
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      setState(() {
        _loginEmailError = null;
        _loginPassError = 'Incorrect password';
        _errorMsg = null;
      });
    } else if (msg.contains('user-not-found')) {
      setState(() {
        _loginEmailError = 'No account found with this email';
        _loginPassError = null;
        _errorMsg = null;
      });
    } else if (msg.contains('invalid-email')) {
      setState(() {
        _loginEmailError = 'Enter a valid email address';
        _loginPassError = null;
        _errorMsg = null;
      });
    } else if (msg.contains('too-many-requests')) {
      _showError('Too many attempts. Please wait a moment and try again.');
    } else {
      _showError(_parseError(msg));
    }
  }

  void _handleRegisterError(Object e) {
    final msg = e.toString();
    if (msg.contains('email-already-in-use')) {
      setState(() {
        _regEmailError = 'Email already registered. Sign in instead.';
        _errorMsg = null;
      });
    } else if (msg.contains('invalid-email')) {
      setState(() {
        _regEmailError = 'Enter a valid email address';
        _errorMsg = null;
      });
    } else if (msg.contains('weak-password')) {
      setState(() {
        _regPassError =
            'Password is too weak. Use at least 8 characters with upper/lowercase letters, a number and a symbol.';
        _errorMsg = null;
      });
    } else if (msg.contains('too-many-requests')) {
      _showError('Too many attempts. Please wait a moment and try again.');
    } else {
      _showError(_parseError(msg));
    }
  }

  String _parseError(String error) {
    if (error.contains('user-not-found')) {
      return 'No account found with this email.';
    }
    if (error.contains('wrong-password')) {
      return 'Incorrect password.';
    }
    if (error.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (error.contains('email-already-in-use')) {
      return 'Email already registered.';
    }
    if (error.contains('account-exists-with-different-credential')) {
      return 'An account already exists with this email. Sign in with your original method.';
    }
    if (error.contains('invalid-email')) {
      return 'Invalid email address.';
    }
    if (error.contains('weak-password')) {
      return 'Password is too weak. Use at least 8 characters with letters and numbers.';
    }
    if (error.contains('network-request-failed')) {
      return 'Network error. Check connection.';
    }
    if (error.contains('too-many-requests')) {
      return 'Too many attempts. Try again later.';
    }
    if (error.contains('operation-not-allowed')) {
      return 'Google sign-in is not enabled. Enable it in Firebase Authentication.';
    }
    if (error.contains('clientConfigurationError') ||
        error.contains('providerConfigurationError')) {
      return 'Google sign-in is misconfigured. Add your app SHA-1 fingerprint in the Firebase console.';
    }
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
                    colors: [
                      Color(0xFF1565C0),
                      Color(0xFF1E88E5),
                      Color(0xFF42A5F5)
                    ],
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
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'lib/images/Logo.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
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
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Feature pills
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FeaturePill(
                            icon: Icons.sensors, label: 'Fall Detection'),
                        _FeaturePill(icon: Icons.gps_fixed, label: 'Live GPS'),
                        _FeaturePill(
                            icon: Icons.notifications_active,
                            label: 'SOS Alerts'),
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
                      color: const Color(0xFF1565C0).withValues(alpha: 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
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
                                color: const Color(0xFF1565C0)
                                    .withValues(alpha: 0.3),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFFE53935)
                                    .withValues(alpha: 0.3)),
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

                    // Google sign-in
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              Expanded(
                                child: Divider(color: Color(0xFFDDE3F0)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6B7A99),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: Color(0xFFDDE3F0)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _GoogleButton(
                            loading: _loading,
                            onPressed: _loginWithGoogle,
                          ),
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
            errorText: _loginEmailError,
            onChanged: (_) {
              if (_loginEmailError != null) {
                setState(() => _loginEmailError = null);
              }
            },
          ),
          const SizedBox(height: 14),
          _GuardianTextField(
            controller: _loginPassCtrl,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: _obscureLogin,
            errorText: _loginPassError,
            onChanged: (_) {
              if (_loginPassError != null) {
                setState(() => _loginPassError = null);
              }
            },
            suffixIcon: IconButton(
              icon: Icon(
                _obscureLogin
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
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
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? false),
                      activeColor: const Color(0xFF1565C0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const Text('Remember me',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99))),
                ],
              ),
              TextButton(
                onPressed: () async {
                  final email = _loginEmailCtrl.text.trim();
                  final emailError = _validateEmail(email);
                  if (emailError != null) {
                    setState(() => _loginEmailError = emailError);
                    return;
                  }
                  try {
                    await _firebase.resetPassword(email);
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
            textCapitalization: TextCapitalization.words,
            errorText: _regNameError,
            onChanged: (_) {
              if (_regNameError != null) setState(() => _regNameError = null);
            },
          ),
          const SizedBox(height: 14),
          _GuardianTextField(
            controller: _regEmailCtrl,
            label: 'Email address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            errorText: _regEmailError,
            onChanged: (_) {
              if (_regEmailError != null) setState(() => _regEmailError = null);
            },
          ),
          const SizedBox(height: 14),
          _GuardianTextField(
            controller: _regPassCtrl,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: _obscureReg,
            errorText: _regPassError,
            onChanged: (_) {
              if (_regPassError != null) setState(() => _regPassError = null);
            },
            suffixIcon: IconButton(
              icon: Icon(
                _obscureReg
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
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
            errorText: _regConfirmError,
            onChanged: (_) {
              if (_regConfirmError != null) {
                setState(() => _regConfirmError = null);
              }
            },
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
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
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
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextCapitalization? textCapitalization;

  const _GuardianTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.errorText,
    this.onChanged,
    this.textCapitalization,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      textCapitalization: textCapitalization ?? TextCapitalization.none,
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
        errorText: errorText,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE53935), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _GoogleButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1A2340),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFDDE3F0), width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Color(0xFF1565C0),
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.string(_googleLogo, width: 20, height: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A2340),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

const String _googleLogo = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z"/>
  <path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z"/>
  <path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.211 35.091 26.715 36 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z"/>
  <path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303c-.792 2.237-2.231 4.166-4.087 5.571.001-.001.002-.001.003-.002l6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z"/>
</svg>
''';
