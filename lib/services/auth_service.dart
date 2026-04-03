import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.phoneNumber,
    required this.displayName,
  });

  final String token;
  final String userId;
  final String phoneNumber;
  final String displayName;

  Map<String, dynamic> toMap() {
    return {
      'token': token,
      'userId': userId,
      'phoneNumber': phoneNumber,
      'displayName': displayName,
    };
  }

  factory AuthSession.fromMap(Map<String, dynamic> map) {
    return AuthSession(
      token: map['token'] as String? ?? '',
      userId: '${map['userId'] ?? ''}',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'Meal Mirror User',
    );
  }
}

class AuthService extends ChangeNotifier {
  AuthService({
    http.Client? client,
    String? apiBaseUrl,
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ??
            const String.fromEnvironment(
              'MEAL_MIRROR_API_BASE_URL',
              defaultValue: '',
            );

  static final AuthService instance = AuthService();

  static const _storage = FlutterSecureStorage();
  static const _sessionStorageKey = 'meal_mirror_auth_session_v1';

  final http.Client _client;
  final String _apiBaseUrl;

  AuthSession? _session;
  bool _isLoading = false;
  bool _hasLoaded = false;

  AuthSession? get session => _session;
  bool get isAuthenticated => _session != null;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String get authToken => _session?.token ?? '';

  Future<void> loadSession() async {
    if (_hasLoaded) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    final raw = await _storage.read(key: _sessionStorageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _session = AuthSession.fromMap(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        _session = null;
      }
    }

    _isLoading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  Future<void> register({
    required String phoneNumber,
    required String password,
    required String confirmPassword,
    String displayName = '',
  }) async {
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    if (!_isValidPhoneNumber(normalizedPhone)) {
      throw Exception('Please enter a valid phone number.');
    }
    if (password.trim().length < 8) {
      throw Exception('Password must be at least 8 characters.');
    }
    if (password != confirmPassword) {
      throw Exception('Password confirmation does not match.');
    }

    await _authenticate(
      '/auth/register',
      body: {
        'phoneNumber': normalizedPhone,
        'password': password,
        'confirmPassword': confirmPassword,
        'displayName': displayName.trim(),
      },
    );
  }

  Future<void> login({
    required String phoneNumber,
    required String password,
  }) async {
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    if (!_isValidPhoneNumber(normalizedPhone)) {
      throw Exception('Please enter a valid phone number.');
    }
    if (password.trim().isEmpty) {
      throw Exception('Password is required.');
    }

    await _authenticate(
      '/auth/login',
      body: {
        'phoneNumber': normalizedPhone,
        'password': password,
      },
    );
  }

  Future<void> logout() async {
    final token = authToken;
    if (_apiBaseUrl.isNotEmpty && token.isNotEmpty) {
      try {
        await _client.post(
          Uri.parse('$_apiBaseUrl/auth/logout'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      } catch (_) {
        // Best effort only.
      }
    }

    _session = null;
    await _storage.delete(key: _sessionStorageKey);
    notifyListeners();
  }

  Future<void> _authenticate(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    if (_apiBaseUrl.isEmpty) {
      throw Exception('Meal Mirror auth is not configured.');
    }

    final response = await _client.post(
      Uri.parse('$_apiBaseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    final payload = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        payload['error'] as String? ?? 'Authentication failed.',
      );
    }

    final session = AuthSession.fromMap(payload);
    _session = session;
    await _storage.write(
      key: _sessionStorageKey,
      value: jsonEncode(session.toMap()),
    );
    notifyListeners();
  }

  String _normalizePhoneNumber(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  bool _isValidPhoneNumber(String value) {
    return RegExp(r'^0\d{9,10}$').hasMatch(value);
  }
}
