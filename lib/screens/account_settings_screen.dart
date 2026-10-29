// lib/screens/account_settings_screen.dart

import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/toast_notification.dart';

/// Lets the signed-in user edit their own account: display name, email and
/// password. Email/password changes require re-authentication with the current
/// password (Firebase requires a recent login for sensitive changes).
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _firebase = FirebaseService();
  bool _saving = false;

  static final RegExp _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  void _toast(String title, String message,
      {IconData icon = Icons.check_circle_outline,
      Color color = const Color(0xFF2E7D32),
      Color background = const Color(0xFFE8F5E9)}) {
    if (!mounted) return;
    ToastNotification.show(
      context,
      title: title,
      message: message,
      icon: icon,
      color: color,
      background: background,
    );
  }

  String _parseError(Object e) {
    final msg = e.toString();
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return 'Current password is incorrect.';
    }
    if (msg.contains('requires-recent-login')) {
      return 'For your security, sign out and sign in again before changing this.';
    }
    if (msg.contains('email-already-in-use')) {
      return 'That email is already in use.';
    }
    if (msg.contains('invalid-email')) return 'Enter a valid email address.';
    if (msg.contains('weak-password')) {
      return 'New password is too weak. Use at least 8 characters with upper/lowercase letters, a number and a symbol.';
    }
    if (msg.contains('network-request-failed')) {
      return 'Network error. Check your connection.';
    }
    return 'Something went wrong. Please try again.';
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

  // ─── Edit name ───────────────────────────────────────────────────────────

  Future<void> _editName() async {
    final controller =
        TextEditingController(text: _firebase.currentUser?.displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display name',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null) return;

    if (newName.isEmpty) {
      _toast('Name not updated', 'Name cannot be empty.',
          icon: Icons.error_outline,
          color: const Color(0xFFD32F2F),
          background: const Color(0xFFFDECEA));
      return;
    }

    await _runSaving(() => _firebase.updateProfileName(newName),
        success: 'Name updated to "$newName".');
  }

  // ─── Change email ────────────────────────────────────────────────────────

  Future<void> _changeEmail() async {
    final passCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String? emailError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change email',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'New email',
                  errorText: emailError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final email = emailCtrl.text.trim();
                if (!_emailRegex.hasMatch(email)) {
                  setDialogState(
                      () => emailError = 'Enter a valid email address');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    final password = passCtrl.text;
    final newEmail = emailCtrl.text.trim();
    if (confirmed != true) return;

    await _runSaving(
      () async {
        await _firebase.reauthenticate(password);
        await _firebase.requestEmailChange(newEmail);
      },
      success:
          'A verification link was sent to $newEmail. Your email will change once you click it.',
    );
  }

  // ─── Change password ─────────────────────────────────────────────────────

  Future<void> _changePassword() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? newError;
    String? confirmError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New password',
                  errorText: newError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  errorText: confirmError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newPass = newCtrl.text;
                final newErr = _validatePassword(newPass);
                String? confErr;
                if (newErr == null && confirmCtrl.text != newPass) {
                  confErr = 'Passwords do not match';
                }
                setDialogState(() {
                  newError = newErr;
                  confirmError = confErr;
                });
                if (newErr == null && confErr == null) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    final currentPassword = currentCtrl.text;
    final newPassword = newCtrl.text;
    if (confirmed != true) return;

    await _runSaving(
      () async {
        await _firebase.reauthenticate(currentPassword);
        await _firebase.updatePassword(newPassword);
      },
      success: 'Password updated.',
    );
  }

  Future<void> _runSaving(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _saving = true);
    try {
      await action();
      _toast('Success', success);
    } catch (e) {
      _toast('Update failed', _parseError(e),
          icon: Icons.error_outline,
          color: const Color(0xFFD32F2F),
          background: const Color(0xFFFDECEA));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _firebase.currentUser;
    final name = user?.displayName;
    final email = user?.email;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Account',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Profile summary ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor:
                      const Color(0xFF1565C0).withValues(alpha: 0.12),
                  child: Text(
                    name != null && name.isNotEmpty
                        ? name.characters.first.toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Color(0xFF1565C0),
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name != null && name.isNotEmpty
                            ? name
                            : 'Guardian user',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2340),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email ?? 'No email',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7A99),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ─── Display name ───────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading:
                  const Icon(Icons.person_outline, color: Color(0xFF1565C0)),
              title: const Text('Display name',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                name != null && name.isNotEmpty ? name : 'Not set',
                style: const TextStyle(color: Color(0xFF5C6B7A)),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving ? null : _editName,
            ),
          ),
          const SizedBox(height: 12),

          // ─── Email ──────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading:
                  const Icon(Icons.email_outlined, color: Color(0xFF1565C0)),
              title: const Text('Email address',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                email ?? 'Not set',
                style: const TextStyle(color: Color(0xFF5C6B7A)),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving ? null : _changeEmail,
            ),
          ),
          const SizedBox(height: 12),

          // ─── Password ───────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const Icon(Icons.lock_outline, color: Color(0xFF1565C0)),
              title: const Text('Password',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Change your sign-in password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving ? null : _changePassword,
            ),
          ),

          if (_saving) ...[
            const SizedBox(height: 20),
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)),
            ),
          ],
        ],
      ),
    );
  }
}
