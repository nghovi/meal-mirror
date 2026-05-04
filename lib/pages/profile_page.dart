import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/meal_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.authService,
    required this.repository,
  });

  final AuthService authService;
  final MealRepository repository;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _nicknameController = TextEditingController(
    text: widget.authService.session?.displayName ?? '',
  );
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _feedbackController = TextEditingController();

  bool _isSavingNickname = false;
  bool _isSavingPassword = false;
  bool _isLoggingOut = false;
  bool _isSendingFeedback = false;
  bool _accountExpanded = false;
  bool _passwordExpanded = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _saveNickname() async {
    setState(() {
      _isSavingNickname = true;
    });

    try {
      await widget.authService.updateDisplayName(_nicknameController.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nickname updated.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingNickname = false;
        });
      }
    }
  }

  Future<void> _savePassword() async {
    setState(() {
      _isSavingPassword = true;
    });

    try {
      await widget.authService.updatePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPassword = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to keep using Meal Mirror.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay here'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await widget.authService.logout();
      await widget.repository.clearLocalAppState();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  Future<void> _sendFeedback() async {
    final message = _feedbackController.text.trim();
    if (message.isEmpty) {
      return;
    }

    setState(() {
      _isSendingFeedback = true;
    });

    try {
      await widget.authService.sendFeedback(message);
      _feedbackController.clear();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you for your feedback!')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingFeedback = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.authService.session;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () =>
                        setState(() => _accountExpanded = !_accountExpanded),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1E7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              color: Color(0xFF7A4B2F),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Account',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if ((session?.phoneNumber ?? '').isNotEmpty)
                                  Text(
                                    session!.phoneNumber,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF6E6257),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          AnimatedRotation(
                            turns: _accountExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFF8A664F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_accountExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        children: [
                          _ProfileInputCard(
                            icon: Icons.badge_outlined,
                            label: 'Nickname',
                            hintText: 'How should Mira greet you?',
                            child: TextField(
                              controller: _nicknameController,
                              decoration: _profileFieldDecoration(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed:
                                  _isSavingNickname ? null : _saveNickname,
                              child: Text(
                                _isSavingNickname
                                    ? 'Saving...'
                                    : 'Update nickname',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () =>
                        setState(() => _passwordExpanded = !_passwordExpanded),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1E7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: Color(0xFF7A4B2F),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Password',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          AnimatedRotation(
                            turns: _passwordExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFF8A664F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_passwordExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        children: [
                          _ProfileInputCard(
                            icon: Icons.key_rounded,
                            label: 'Current password',
                            child: TextField(
                              controller: _currentPasswordController,
                              obscureText: true,
                              decoration: _profileFieldDecoration(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ProfileInputCard(
                            icon: Icons.lock_reset_rounded,
                            label: 'New password',
                            child: TextField(
                              controller: _newPasswordController,
                              obscureText: true,
                              decoration: _profileFieldDecoration(
                                hintText: 'At least 8 characters',
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ProfileInputCard(
                            icon: Icons.verified_user_outlined,
                            label: 'Confirm new password',
                            child: TextField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              decoration: _profileFieldDecoration(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed:
                                  _isSavingPassword ? null : _savePassword,
                              child: Text(
                                _isSavingPassword
                                    ? 'Saving...'
                                    : 'Update password',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1E7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.feedback_outlined,
                            color: Color(0xFF7A4B2F),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Send Feedback',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _feedbackController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: _profileFieldDecoration(
                        hintText: 'What do you think? Any bugs or ideas?',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSendingFeedback ? null : _sendFeedback,
                        child: Text(
                          _isSendingFeedback ? 'Sending...' : 'Send',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoggingOut ? null : _logout,
                icon: _isLoggingOut
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(_isLoggingOut ? 'Logging out...' : 'Log out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _profileFieldDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: const Color(0xFFF8F3EE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE8DBCF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFB85C38),
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    );
  }
}

class _ProfileInputCard extends StatelessWidget {
  const _ProfileInputCard({
    required this.icon,
    required this.label,
    required this.child,
    this.hintText,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9DDD2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8EEE4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: const Color(0xFF8A664F),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF5E5147),
                  ),
                ),
              ),
            ],
          ),
          if ((hintText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hintText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8B7B6E),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
