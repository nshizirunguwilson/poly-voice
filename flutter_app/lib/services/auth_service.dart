import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/user_model.dart';

class AuthService extends ChangeNotifier {
  UserModel? _currentUser;
  String? _token;
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && _currentUser != null;

  // ── Headers ──
  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ── Initialize from stored token ──
  Future<bool> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    if (_token == null) return false;

    try {
      final res = await http.get(
        Uri.parse(AppConfig.authMe),
        headers: _authHeaders,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _currentUser = UserModel.fromJson(data['user']);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
    }

    // Token invalid — clear
    await _clearAuth();
    return false;
  }

  // ── Register ──
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
    required String displayName,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final res = await http.post(
        Uri.parse(AppConfig.authRegister),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'role': role,
          'displayName': displayName,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 201) {
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveToken();
        notifyListeners();
        return {'success': true};
      }

      return {'success': false, 'error': data['error'] ?? 'Registration failed'};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Login ──
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final res = await http.post(
        Uri.parse(AppConfig.authLogin),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveToken();
        notifyListeners();
        return {'success': true};
      }

      return {'success': false, 'error': data['error'] ?? 'Login failed'};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Logout ──
  Future<void> logout() async {
    try {
      await http.patch(
        Uri.parse(AppConfig.usersStatus),
        headers: _authHeaders,
        body: jsonEncode({'isOnline': false}),
      );
    } catch (_) {}

    await _clearAuth();
    notifyListeners();
  }

  // ── Fetch Users ──
  Future<List<UserModel>> fetchUsers() async {
    try {
      final res = await http.get(Uri.parse(AppConfig.usersList), headers: _authHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['users'] as List).map((u) => UserModel.fromJson(u)).toList();
      }
    } catch (e) {
      debugPrint('Fetch users error: $e');
    }
    return [];
  }

  // ── Storage Helpers ──
  Future<void> _saveToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString('auth_token', _token!);
  }

  Future<void> _clearAuth() async {
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }
}
