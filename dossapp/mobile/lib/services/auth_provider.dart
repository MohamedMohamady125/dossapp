import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'notification_service.dart';

/// One swimmer a parent can open. A parent with several children has one of
/// these per child, all under the same email.
class SwimmerProfile {
  final int accountId;
  final int athleteNumber;
  final String name;
  final String branchName;
  final String loginCode;
  final bool isCurrent;

  SwimmerProfile({
    required this.accountId,
    required this.athleteNumber,
    required this.name,
    required this.branchName,
    required this.loginCode,
    required this.isCurrent,
  });

  factory SwimmerProfile.fromJson(Map<String, dynamic> json) => SwimmerProfile(
        accountId: json['account_id'],
        athleteNumber: json['athlete_number'],
        name: json['name'] ?? '',
        branchName: json['branch_name'] ?? '',
        loginCode: json['login_code'] ?? '',
        isCurrent: json['is_current'] ?? false,
      );
}

class AuthProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  bool _isLoggedIn = false;
  bool _mustChangePassword = false;
  String _role = ''; // 'customer' | 'admin' | 'assistant' | 'coach'
  int? _branchId;
  List<SwimmerProfile> _profiles = [];
  bool _needsProfileChoice = false;
  int _sessionKey = 0;
  bool _sessionExpired = false;

  AuthProvider() {
    ApiService.onSessionExpired = _onSessionExpired;
  }

  /// True after the server ended the session; the login screen says so once.
  bool get sessionExpired => _sessionExpired;

  void _onSessionExpired() {
    if (!_isLoggedIn) return;
    _clearLocalSession();
    _sessionExpired = true;
    notifyListeners();
  }

  void _clearLocalSession() {
    _isLoggedIn = false;
    _role = '';
    _branchId = null;
    _mustChangePassword = false;
    _profiles = [];
    _needsProfileChoice = false;
  }

  /// Changes each time a different swimmer is opened.
  int get sessionKey => _sessionKey;

  /// Every swimmer this parent can open. One entry for a single-child family.
  List<SwimmerProfile> get profiles => _profiles;
  bool get hasSeveralSwimmers => _profiles.length > 1;

  /// True right after sign-in when the parent has several swimmers and has
  /// not said which one to open yet.
  bool get needsProfileChoice => _needsProfileChoice;

  SwimmerProfile? get currentProfile {
    for (final p in _profiles) {
      if (p.isCurrent) return p;
    }
    return null;
  }

  void _readSession(Map<String, dynamic> data) {
    _mustChangePassword = data['must_change_password'] ?? false;
    _profiles = ((data['profiles'] as List?) ?? [])
        .map((p) => SwimmerProfile.fromJson(p as Map<String, dynamic>))
        .toList();
    // Decode JWT to get branch info
    try {
      final parts = (data['access_token'] as String).split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        _branchId = payload['branch_id'];
      }
    } catch (_) {
      // Malformed token: continue without branch info
    }
  }

  Future<void> _storeSession() async {
    await _storage.write(key: 'role', value: _role);
    if (_branchId != null) {
      await _storage.write(key: 'branch_id', value: _branchId.toString());
    }
    await _storage.write(key: 'must_change_password', value: _mustChangePassword.toString());
  }

  /// Open one of the parent's swimmers: from the picker after sign-in, or
  /// from the switcher on the home screen.
  Future<void> chooseProfile(int accountId) async {
    if (currentProfile?.accountId != accountId) {
      final data = await ApiService.switchProfile(accountId);
      _readSession(data);
      await _storeSession();
      _sessionKey++;
      // Pushes follow the parent, but the inbox badge is per swimmer
      NotificationService.registerToken();
    }
    _needsProfileChoice = false;
    notifyListeners();
  }

  /// Adds a child with the front desk's login details. Returns the child's
  /// name so the screen can confirm it.
  Future<String> addSwimmer(String loginCode, String password) async {
    final before = _profiles.map((p) => p.accountId).toSet();
    final list = await ApiService.linkSwimmer(loginCode.trim(), password);
    _profiles = list.map(SwimmerProfile.fromJson).toList();
    notifyListeners();
    final added = _profiles.where((p) => !before.contains(p.accountId));
    return added.isEmpty ? '' : added.first.name;
  }

  Future<void> _refreshProfiles() async {
    try {
      final list = await ApiService.getProfiles();
      _profiles = list.map(SwimmerProfile.fromJson).toList();
      notifyListeners();
    } catch (_) {
      // Older server or offline: the switcher just stays hidden
    }
  }

  bool get isLoggedIn => _isLoggedIn;
  bool get mustChangePassword => _mustChangePassword;
  String get role => _role;
  int? get branchId => _branchId;
  bool get isAdmin => _role == 'admin';
  bool get isAssistant => _role == 'assistant';
  bool get isCustomer => _role == 'customer';
  bool get isCoach => _role == 'coach';
  bool get isStaff => _role == 'admin' || _role == 'assistant';

  Future<void> init() async {
    // Reading the keychain can fail right after the phone restarts (before
    // the first unlock). That is not a logout: try again instead of showing
    // the login screen to someone who is signed in.
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await _restoreSession();
        return;
      } catch (e) {
        debugPrint('Session restore failed (attempt ${attempt + 1}): $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _restoreSession() async {
    final hasToken = await ApiService.hasToken();
    if (hasToken) {
      final role = await _storage.read(key: 'role');
      final branchId = await _storage.read(key: 'branch_id');
      final mustChange = await _storage.read(key: 'must_change_password');
      if (role != null) {
        _isLoggedIn = true;
        _role = role;
        _branchId = branchId != null ? int.tryParse(branchId) : null;
        _mustChangePassword = mustChange == 'true';
        notifyListeners();
        NotificationService.registerToken(staff: _role != 'customer');
        if (_role == 'customer') _refreshProfiles();
      }
    }
  }

  /// [identifier] is the login code or the email the parent verified.
  Future<void> customerLogin(String identifier, String password) async {
    final data = await ApiService.customerLogin(identifier, password);
    _sessionExpired = false;
    _isLoggedIn = true;
    _role = 'customer';
    _readSession(data);
    // Several swimmers on this email: ask which one before showing a home
    // screen that might be the wrong child's.
    _needsProfileChoice = _profiles.length > 1 && !_mustChangePassword;
    await _storeSession();
    notifyListeners();
    NotificationService.registerToken();
  }

  Future<void> adminLogin(String username, String password) async {
    final data = await ApiService.adminLogin(username, password);
    _sessionExpired = false;
    _isLoggedIn = true;
    _mustChangePassword = data['must_change_password'] ?? false;

    try {
      final parts = (data['access_token'] as String).split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        _role = payload['role'] ?? 'customer';
        _branchId = payload['branch_id'];
      }
    } catch (_) {
      _role = 'customer';
    }

    // Remember a forced password change, so closing the app cannot skip it
    await _storeSession();
    notifyListeners();
    NotificationService.registerToken(staff: _role != 'customer');
  }

  Future<void> changePassword(String newPassword) async {
    if (isCoach) {
      await ApiService.staffChangePassword(newPassword);
    } else {
      await ApiService.changePassword(newPassword);
    }
    _mustChangePassword = false;
    await _storage.write(key: 'must_change_password', value: 'false');
    notifyListeners();
  }

  /// First login for a child whose parent already uses the app: the email
  /// code was enough, the child joined the family and no new password is
  /// needed. Goes straight to "Who is swimming?".
  Future<void> joinedFamily(List<dynamic> profiles) async {
    _mustChangePassword = false;
    await _storage.write(key: 'must_change_password', value: 'false');
    _profiles = profiles.map((p) => SwimmerProfile.fromJson(p as Map<String, dynamic>)).toList();
    _needsProfileChoice = _profiles.length > 1;
    notifyListeners();
  }

  Future<void> completeOnboarding(String email, String code, String newPassword) async {
    await ApiService.completeOnboarding(email, code, newPassword);
    _mustChangePassword = false;
    await _storage.write(key: 'must_change_password', value: 'false');
    notifyListeners();
  }

  Future<void> logout() async {
    // Stop pushes to this phone for whoever is logging out, staff or parent.
    // Give it a few seconds at most: logging out must work on a bad
    // connection too (the server also moves the phone on the next login).
    try {
      await NotificationService.unregisterToken().timeout(const Duration(seconds: 5));
    } catch (_) {}
    await ApiService.logout();
    _clearLocalSession();
    notifyListeners();
  }
}
