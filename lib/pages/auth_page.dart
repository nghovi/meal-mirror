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
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    super.dispose();
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
                  const SizedBox(height: 10),
                  Text(
                    'Your meals, drinks, and Mira chat will live on the server, not only on this phone.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF6E6257),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isRegistering) ...[
                            TextField(
                              controller: _displayNameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Display name',
                                hintText: 'How should Mira greet you?',
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                              hintText: 'Example: 0912345678',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: _isRegistering
                                ? TextInputAction.next
                                : TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              hintText: 'At least 8 characters',
                            ),
                          ),
                          if (_isRegistering) ...[
                            const SizedBox(height: 14),
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFB2402E),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
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
                              child: Text(
                                _isRegistering
                                    ? 'Already have an account? Sign in'
                                    : 'New here? Create an account',
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
}
