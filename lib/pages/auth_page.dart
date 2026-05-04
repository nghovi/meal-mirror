import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.authService,
  });

  final AuthService authService;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isRegistering = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastPhoneNumber();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadLastPhoneNumber() async {
    final phoneNumber = await widget.authService.loadLastPhoneNumber();
    if (!mounted || phoneNumber.trim().isEmpty) {
      return;
    }

    _phoneController.text = phoneNumber;
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _isSubmitting = true;
    });

    try {
      if (_isRegistering) {
        await widget.authService.register(
          phoneNumber: _phoneController.text,
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
          displayName: _displayNameController.text,
        );
      } else {
        await widget.authService.login(
          phoneNumber: _phoneController.text,
          password: _passwordController.text,
        );
      }
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1E7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Meal Mirror',
                      style: TextStyle(
                        color: Color(0xFF7A4B2F),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isRegistering
                        ? 'Create your Meal Mirror account'
                        : 'Sign in to your Meal Mirror account',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isRegistering) ...[
                            _AuthFieldCard(
                              icon: Icons.badge_outlined,
                              label: 'Display name',
                              child: TextField(
                                controller: _displayNameController,
                                textInputAction: TextInputAction.next,
                                decoration: _authInputDecoration(
                                  hintText: 'How should Mira greet you?',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          _AuthFieldCard(
                            icon: Icons.phone_outlined,
                            label: 'Phone number',
                            child: TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: _authInputDecoration(
                                hintText: 'Example: 0912345678',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _AuthFieldCard(
                            icon: Icons.lock_outline_rounded,
                            label: 'Password',
                            child: TextField(
                              controller: _passwordController,
                              obscureText: true,
                              textInputAction: _isRegistering
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              decoration: _authInputDecoration(
                                hintText: 'At least 8 characters',
                              ),
                            ),
                          ),
                          if (_isRegistering) ...[
                            const SizedBox(height: 10),
                            _AuthFieldCard(
                              icon: Icons.verified_user_outlined,
                              label: 'Confirm password',
                              child: TextField(
                                controller: _confirmPasswordController,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                decoration: _authInputDecoration(),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFB2402E),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              child: Text(
                                _isSubmitting
                                    ? 'Please wait...'
                                    : _isRegistering
                                        ? 'Create account'
                                        : 'Sign in',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      setState(() {
                                        _isRegistering = !_isRegistering;
                                        _error = null;
                                      });
                                    },
                              child: Text.rich(
                                TextSpan(
                                  text: _isRegistering
                                      ? 'Already have an account? '
                                      : 'New here? ',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: _isRegistering
                                          ? 'Sign in'
                                          : 'Create an account',
                                      style: const TextStyle(
                                        color: Color(0xFF2E6FD8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _authInputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFFC4B6AA),
      ),
      filled: true,
      fillColor: const Color(0xFFFAF7F3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8DBCF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFFB85C38),
          width: 1.25,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
    );
  }
}

class _AuthFieldCard extends StatelessWidget {
  const _AuthFieldCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1E7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: const Color(0xFF8A664F),
                ),
              ),
              const SizedBox(width: 8),
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
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
