import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  bool _isLoggedIn = false;
  bool _mustChangePassword = false;
  String _role = ''; // 'customer' | 'admin' | 'assistant'
  int? _branchId;

  bool get isLoggedIn => _isLoggedIn;
  bool get mustChangePassword => _mustChangePassword;
  String get role => _role;
  int? get branchId => _branchId;
  bool get isAdmin => _role == 'admin';
  bool get isAssistant => _role == 'assistant';
  bool get isCustomer => _role == 'customer';
  bool get isStaff => _role == 'admin' || _role == 'assistant';

  Future<void> init() async {
    final hasToken = await ApiService.hasToken();
    if (hasToken) {
      final role = await _storage.read(key: 'role');
      final branchId = await _storage.read(key: 'branch_id');
      if (role != null) {
        _isLoggedIn = true;
        _role = role;
        _branchId = branchId != null ? int.tryParse(branchId) : null;
        notifyListeners();
      }
    }
  }

  Future<void> customerLogin(String code, String password) async {
    final data = await ApiService.customerLogin(code, password);
    _isLoggedIn = true;
    _role = 'customer';
    _mustChangePassword = data['must_change_password'] ?? false;

    // Decode JWT to get branch info
    final parts = (data['access_token'] as String).split('.');
    if (parts.length == 3) {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      _branchId = payload['branch_id'];
    }

    await _storage.write(key: 'role', value: _role);
    if (_branchId != null) {
      await _storage.write(key: 'branch_id', value: _branchId.toString());
    }
    notifyListeners();
  }

  Future<void> adminLogin(String username, String password) async {
    final data = await ApiService.adminLogin(username, password);
    _isLoggedIn = true;

    final parts = (data['access_token'] as String).split('.');
    if (parts.length == 3) {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      _role = payload['role'] ?? 'admin';
      _branchId = payload['branch_id'];
    }

    await _storage.write(key: 'role', value: _role);
    if (_branchId != null) {
      await _storage.write(key: 'branch_id', value: _branchId.toString());
    }
    notifyListeners();
  }

  Future<void> changePassword(String newPassword) async {
    await ApiService.changePassword(newPassword);
    _mustChangePassword = false;
    notifyListeners();
  }

  Future<void> logout() async {
    await ApiService.logout();
    _isLoggedIn = false;
    _role = '';
    _branchId = null;
    _mustChangePassword = false;
    notifyListeners();
  }
}
