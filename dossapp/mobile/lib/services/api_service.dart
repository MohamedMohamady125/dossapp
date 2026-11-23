import 'package:flutter/foundation.dart';
import '../utils/app_error.dart';
import 'app_refresh.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';
import '../models/athlete.dart';
import '../models/bill.dart';
import '../models/receipt.dart';
import '../models/reinstatement.dart';
import '../models/report.dart';

class ApiService {
  static const _storage = FlutterSecureStorage();
  static String? _accessToken;
  static String? _refreshToken;
  static const _timeout = Duration(seconds: 30);

  // ── Auth ──

  static Future<Map<String, String>> _headers() async {
    if (_accessToken == null) {
      _accessToken = await _storage.read(key: 'access_token');
    }
    return {
      'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
  }

  /// True while the last request could not reach the server. The app shows
  /// a small "no internet" strip instead of failing silently.
  static final ValueNotifier<bool> offline = ValueNotifier(false);

  /// Wraps network failures into an [ApiException] the screens can show.
  static Future<http.Response> _safeRequest(
    Future<http.Response> Function() request, {
    Duration timeout = _timeout,
  }) async {
    try {
      final resp = await request().timeout(timeout);
      offline.value = false;
      return resp;
    } on TimeoutException {
      throw ApiException(0, null).._timedOut = true;
    } on SocketException {
      offline.value = true;
      throw ApiException(0, null);
    } on HttpException {
      offline.value = true;
      throw ApiException(0, null);
    } on HandshakeException {
      throw ApiException(0, null);
    } on http.ClientException {
      // What the http package throws when the connection drops mid-request
      offline.value = true;
      throw ApiException(0, null);
    }
  }

  /// Called when the server refuses to renew the session (expired, or the
  /// account was disabled). The app must return to the login screen; a
  /// network failure never triggers this.
  static void Function()? onSessionExpired;

  static Future<http.Response> _get(String path) async {
    final resp = await _safeRequest(() async => http.get(
      Uri.parse('${AppConstants.baseUrl}$path'),
      headers: await _headers(),
    ));
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _safeRequest(() async => http.get(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: await _headers(),
        ));
      }
    }
    return resp;
  }

  // Requests that change nothing a screen shows: signing in, registering the
  // phone for pushes, marking an alert read, opening the payment page.
  static final _quietPaths = RegExp(r'^/(auth/|devices|staff/devices|notifications|me/pay/|me/switch-profile)');

  /// After anything is changed from this phone, every open screen reloads
  /// itself, so nobody has to pull to refresh to see their own action.
  static http.Response _announce(String path, http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300 && !_quietPaths.hasMatch(path)) {
      AppRefresh.dataChanged();
    }
    return resp;
  }

  static Future<http.Response> _post(String path, Map<String, dynamic> body) async =>
      _announce(path, await _postRaw(path, body));
  static Future<http.Response> _delete(String path) async => _announce(path, await _deleteRaw(path));
  static Future<http.Response> _put(String path, Map<String, dynamic> body) async =>
      _announce(path, await _putRaw(path, body));

  static Future<http.Response> _postRaw(String path, Map<String, dynamic> body) async {
    final resp = await _safeRequest(() async => http.post(
      Uri.parse('${AppConstants.baseUrl}$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    ));
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _safeRequest(() async => http.post(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        ));
      }
    }
    return resp;
  }

  static Future<http.Response> _deleteRaw(String path) async {
    final resp = await _safeRequest(() async => http.delete(
      Uri.parse('${AppConstants.baseUrl}$path'),
      headers: await _headers(),
    ));
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _safeRequest(() async => http.delete(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: await _headers(),
        ));
      }
    }
    return resp;
  }

  static Future<http.Response> _putRaw(String path, Map<String, dynamic> body) async {
    final resp = await _safeRequest(() async => http.put(
      Uri.parse('${AppConstants.baseUrl}$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    ));
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _safeRequest(() async => http.put(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        ));
      }
    }
    return resp;
  }

  static Completer<bool>? _refreshLock;

  static Future<bool> _tryRefresh() async {
    // Prevent concurrent refresh calls — reuse in-flight request
    if (_refreshLock != null) return _refreshLock!.future;
    _refreshLock = Completer<bool>();

    try {
      _refreshToken ??= await _storage.read(key: 'refresh_token');
      if (_refreshToken == null) {
        _refreshLock!.complete(false);
        return false;
      }

      final resp = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      ).timeout(_timeout);

      if (resp.statusCode == 200) {
        final data = _safeJsonDecode(resp.body);
        if (data != null && data['access_token'] != null && data['refresh_token'] != null) {
          _accessToken = data['access_token'];
          _refreshToken = data['refresh_token'];
          await _storage.write(key: 'access_token', value: _accessToken!);
          await _storage.write(key: 'refresh_token', value: _refreshToken!);
          _refreshLock!.complete(true);
          return true;
        }
      }
      // The session ends ONLY when our own server answers, in JSON, that
      // this login is no longer valid. A gateway error page, a server crash,
      // a timeout or a storage hiccup never signs anyone out.
      final refusal = (resp.statusCode == 401 || resp.statusCode == 403) ? _safeJsonDecode(resp.body) : null;
      if (refusal != null && refusal['detail'] is String) {
        _accessToken = null;
        _refreshToken = null;
        await _clearSessionKeys();
        onSessionExpired?.call();
      }
      _refreshLock!.complete(false);
      return false;
    } catch (_) {
      _refreshLock!.complete(false);
      return false;
    } finally {
      _refreshLock = null;
    }
  }

  static Map<String, dynamic>? _safeJsonDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveTokens(Map<String, dynamic> data) async {
    _accessToken = data['access_token'] as String?;
    _refreshToken = data['refresh_token'] as String?;
    if (_accessToken != null) {
      await _storage.write(key: 'access_token', value: _accessToken!);
    }
    if (_refreshToken != null) {
      await _storage.write(key: 'refresh_token', value: _refreshToken!);
    }
  }

  static Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    await _clearSessionKeys();
  }

  /// Only the session. The chosen language stays, so logging out does not
  /// flip the app (and the next account's pushes) back to English.
  static Future<void> _clearSessionKeys() async {
    for (final key in const ['access_token', 'refresh_token', 'role', 'branch_id', 'must_change_password']) {
      await _storage.delete(key: key);
    }
  }

  static Future<bool> hasToken() async {
    final token = await _storage.read(key: 'access_token');
    return token != null;
  }

  // ── Customer Auth ──

  /// What the server said for the user, or null when it said nothing a
  /// person can read (the app then uses its own words for that failure).
  /// FastAPI sends either a sentence or, for a badly shaped request, a list
  /// of field problems; only a sentence is passed on.
  static String? _extractError(http.Response resp, [String? unused]) {
    try {
      final detail = jsonDecode(resp.body)['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
    } catch (_) {
      // Not JSON (a gateway page, an empty body)
    }
    return null;
  }

  static Future<Map<String, dynamic>> customerLogin(String code, String password) async {
    final resp = await _safeRequest(() async => http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/customer/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'login_code': code, 'password': password}),
    ));
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Login failed'));
    }
    final data = jsonDecode(resp.body);
    await _saveTokens(data);
    return data;
  }

  /// Every swimmer this parent can open (same verified email).
  static Future<List<Map<String, dynamic>>> getProfiles() async {
    final resp = await _get('/me/profiles');
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to load swimmers'));
    }
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  /// Add another child to this parent using the login details the front desk
  /// gave for that child. Returns the parent's swimmers, new one included.
  static Future<List<Map<String, dynamic>>> linkSwimmer(String loginCode, String password) async {
    final resp = await _post('/me/link-swimmer', {'login_code': loginCode, 'password': password});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Could not add this swimmer'));
    }
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  /// Open another swimmer of the same parent. Replaces the stored session.
  static Future<Map<String, dynamic>> switchProfile(int accountId) async {
    final resp = await _post('/me/switch-profile', {'account_id': accountId});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Could not switch swimmer'));
    }
    final data = jsonDecode(resp.body);
    await _saveTokens(data);
    return data;
  }

  static Future<void> changePassword(String newPassword) async {
    final resp = await _post('/auth/customer/change-password', {'new_password': newPassword});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed'));
    }
  }

  // ── Email Verification (Onboarding) ──

  static Future<void> sendVerificationCode(String email) async {
    final resp = await _post('/auth/customer/send-verification', {'email': email});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to send code'));
    }
  }

  static Future<bool> verifyCode(String email, String code) async {
    final data = await verifyCodeDetailed(email, code);
    return data['verified'] == true;
  }

  /// Same check, with the server's full answer: `joined_family` is true when
  /// this email already has swimmers set up, and `profiles` lists them.
  static Future<Map<String, dynamic>> verifyCodeDetailed(String email, String code) async {
    final resp = await _post('/auth/customer/verify-code', {'email': email, 'code': code});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Verification failed'));
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<void> completeOnboarding(String email, String code, String newPassword) async {
    final resp = await _post('/auth/customer/complete-onboarding', {
      'email': email, 'code': code, 'new_password': newPassword,
    });
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to complete setup'));
    }
  }

  // ── Forgot Password ──

  static Future<void> forgotPasswordSendCode(String email) async {
    final resp = await _safeRequest(() async => http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/forgot-password/send-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    ));
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed'));
    }
  }

  static Future<bool> forgotPasswordVerify(String email, String code) async {
    final resp = await _safeRequest(() async => http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/forgot-password/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    ));
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Verification failed'));
    }
    return true;
  }

  static Future<void> forgotPasswordReset(String email, String code, String newPassword) async {
    final resp = await _safeRequest(() async => http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/forgot-password/reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'code': code, 'new_password': newPassword,
      }),
    ));
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Password reset failed'));
    }
  }

  // ── Admin Auth ──

  static Future<Map<String, dynamic>> adminLogin(String username, String password) async {
    final resp = await _safeRequest(() async => http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ));
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Login failed'));
    }
    final data = jsonDecode(resp.body);
    await _saveTokens(data);
    return data;
  }

  static Future<void> staffChangePassword(String newPassword) async {
    final resp = await _post('/auth/staff/change-password', {'new_password': newPassword});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed'));
    }
  }

  // ── Profile Updates ──

  static Future<void> updateEmail(String email) async {
    final resp = await _put('/me/email', {'email': email});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to update email'));
    }
  }

  static Future<void> updatePassword(String oldPassword, String newPassword) async {
    final resp = await _put('/me/password', {'old_password': oldPassword, 'new_password': newPassword});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to change password'));
    }
  }

  static Future<void> staffUpdatePassword(String oldPassword, String newPassword) async {
    final resp = await _post('/auth/staff/update-password', {'old_password': oldPassword, 'new_password': newPassword});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to change password'));
    }
  }

  // ── Coach Endpoints ──

  static Future<Map<String, dynamic>> getCoachSchedule() async {
    final resp = await _get('/coach/schedule');
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to load schedule'));
    }
    return jsonDecode(resp.body);
  }

  // ── Customer Endpoints ──

  static Future<AthleteProfile> getProfile() async {
    final resp = await _get('/me/');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return AthleteProfile.fromJson(jsonDecode(resp.body));
  }

  static Future<Bill> getBill() async {
    final resp = await _get('/me/bill');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return Bill.fromJson(jsonDecode(resp.body));
  }

  static Future<Map<String, dynamic>> createPaymentIntent() async {
    final resp = await _post('/me/pay/easykash/checkout', {});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Payment failed'));
    }
    return jsonDecode(resp.body);
  }

  static Future<List<Receipt>> getReceipts() async {
    final resp = await _get('/me/receipts');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((r) => Receipt.fromJson(r)).toList();
  }

  static Future<void> resendReceipt(int receiptId) async {
    final resp = await _post('/me/receipts/$receiptId/resend', {});
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
  }

  static String receiptPdfUrl(int receiptId) {
    return '${AppConstants.baseUrl}/me/receipts/$receiptId/pdf';
  }

  static Future<List<int>> downloadReceiptPdf(int receiptId) async {
    final resp = await _safeRequest(() async => http.get(
      Uri.parse('${AppConstants.baseUrl}/me/receipts/$receiptId/pdf'),
      headers: await _headers(),
    ));
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        final retryResp = await _safeRequest(() async => http.get(
          Uri.parse('${AppConstants.baseUrl}/me/receipts/$receiptId/pdf'),
          headers: await _headers(),
        ));
        if (retryResp.statusCode != 200) {
          throw ApiException(retryResp.statusCode, 'Failed to download PDF');
        }
        return retryResp.bodyBytes;
      }
    }
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp));
    }
    return resp.bodyBytes;
  }

  // ── Notifications ──

  static Future<void> registerDevice(String token, String platform, {String language = 'en'}) async {
    final resp = await _post('/me/devices', {'token': token, 'platform': platform, 'language': language});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Device registration failed'));
    }
  }

  static Future<void> unregisterDevice(String token) async {
    final resp = await _delete('/me/devices/$token');
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Device unregistration failed'));
    }
  }

  /// Staff phones register separately so they get staff alerts (online
  /// payments, reinstatement requests) instead of a parent's.
  static Future<void> registerStaffDevice(String token, String platform, {String language = 'en'}) async {
    final resp = await _post('/staff/devices', {'token': token, 'platform': platform, 'language': language});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to register device'));
    }
  }

  static Future<void> unregisterStaffDevice(String token) async {
    final resp = await _delete('/staff/devices/$token');
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to unregister device'));
    }
  }

  static Future<List<Map<String, dynamic>>> getNotifications({int limit = 50, int offset = 0}) async {
    final resp = await _get('/me/notifications?limit=$limit&offset=$offset');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<int> getUnreadCount() async {
    final resp = await _get('/me/notifications/unread-count');
    if (resp.statusCode != 200) return 0;
    return jsonDecode(resp.body)['unread'] ?? 0;
  }

  static Future<void> markNotificationRead(int id) async {
    final resp = await _post('/me/notifications/$id/read', {});
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
  }

  static Future<void> markAllNotificationsRead() async {
    final resp = await _post('/me/notifications/read-all', {});
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
  }

  // ── Reinstatement ──

  static Future<ReinstatementStatus> getReinstatementStatus() async {
    final resp = await _get('/me/reinstatement');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return ReinstatementStatus.fromJson(jsonDecode(resp.body));
  }

  static Future<void> requestReinstatement({String? message}) async {
    final resp = await _post('/me/reinstatement', {if (message != null) 'message': message});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to submit request'));
    }
  }

  // ── Monthly Reports ──

  static Future<List<MonthlyReport>> getMyReports() async {
    final resp = await _get('/me/reports');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).map((r) => MonthlyReport.fromJson(r)).toList();
  }

  static Future<Map<String, dynamic>> getReportSwimmers({int? branchId}) async {
    var path = '/staff/reports/swimmers';
    if (branchId != null) path += '?branch_id=$branchId';
    final resp = await _get(path);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to load swimmers'));
    }
    return jsonDecode(resp.body);
  }

  static Future<List<MonthlyReport>> getAthleteReports(int branchId, int athleteNumber) async {
    final resp = await _get('/staff/reports?branch_id=$branchId&athlete_number=$athleteNumber');
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to load reports'));
    }
    return (jsonDecode(resp.body) as List).map((r) => MonthlyReport.fromJson(r)).toList();
  }

  /// Send a written note as the month's report.
  static Future<MonthlyReport> sendReportNote({
    required int branchId,
    required int athleteNumber,
    required String period,
    required String note,
  }) async {
    final resp = await _put('/staff/reports', {
      'branch_id': branchId,
      'athlete_number': athleteNumber,
      'period': period,
      'coach_notes': note,
    });
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to send report'));
    }
    return MonthlyReport.fromJson(jsonDecode(resp.body));
  }

  /// Send a PDF (with an optional note) as the month's report.
  static Future<MonthlyReport> uploadReportPdf({
    required int branchId,
    required int athleteNumber,
    required String period,
    required List<int> bytes,
    required String filename,
    String? note,
  }) async {
    Future<http.Response> send() async {
      final req = http.MultipartRequest('POST', Uri.parse('${AppConstants.baseUrl}/staff/reports/pdf'));
      final headers = await _headers()..remove('Content-Type');
      req.headers.addAll(headers);
      req.fields['branch_id'] = '$branchId';
      req.fields['athlete_number'] = '$athleteNumber';
      req.fields['period'] = period;
      if (note != null && note.isNotEmpty) req.fields['note'] = note;
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      return http.Response.fromStream(await req.send());
    }

    // A 10 MB PDF on mobile data needs longer than an ordinary request
    const uploadTimeout = Duration(seconds: 120);
    var resp = await _safeRequest(send, timeout: uploadTimeout);
    if (resp.statusCode == 401 && await _tryRefresh()) {
      resp = await _safeRequest(send, timeout: uploadTimeout);
    }
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to upload PDF'));
    }
    return MonthlyReport.fromJson(jsonDecode(resp.body));
  }

  /// The PDF of a report. [staff] picks the staff or the athlete endpoint.
  static Future<List<int>> downloadReportPdf(int reportId, {required bool staff}) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/${staff ? 'staff' : 'me'}/reports/$reportId/pdf');
    var resp = await _safeRequest(() async => http.get(uri, headers: await _headers()));
    if (resp.statusCode == 401 && await _tryRefresh()) {
      resp = await _safeRequest(() async => http.get(uri, headers: await _headers()));
    }
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to open the PDF'));
    }
    return resp.bodyBytes;
  }

  static Future<void> deleteReport(int reportId) async {
    final resp = await _delete('/staff/reports/$reportId');
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to delete report'));
    }
  }

  // ── Account Deletion ──

  static Future<void> deleteAccount(String password) async {
    final resp = await _safeRequest(() async => http.delete(
      Uri.parse('${AppConstants.baseUrl}/me/account'),
      headers: await _headers(),
      body: jsonEncode({'password': password}),
    ));
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        final retryResp = await _safeRequest(() async => http.delete(
          Uri.parse('${AppConstants.baseUrl}/me/account'),
          headers: await _headers(),
          body: jsonEncode({'password': password}),
        ));
        if (retryResp.statusCode != 200) {
          throw ApiException(retryResp.statusCode, _extractError(retryResp, 'Failed to delete account'));
        }
        return;
      }
    }
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to delete account'));
    }
  }

  // ── Admin Endpoints ──

  static Future<List<Map<String, dynamic>>> getBranches() async {
    final resp = await _get('/branches');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<AthleteDetail>> getBranchAthletes(int branchId, {String? search}) async {
    var path = '/branches/$branchId/athletes';
    if (search != null && search.isNotEmpty) path += '?search=${Uri.encodeComponent(search)}';
    final resp = await _get(path);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((a) => AthleteDetail.fromJson(a)).toList();
  }

  static Future<AthleteDetail> getAthleteDetail(int branchId, int athleteNumber) async {
    final resp = await _get('/branches/$branchId/athletes/$athleteNumber');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return AthleteDetail.fromJson(jsonDecode(resp.body));
  }

  static Future<Map<String, dynamic>> provisionAccount(
    int branchId, int athleteNumber, String deliveryMethod,
  ) async {
    final resp = await _post(
      '/branches/$branchId/athletes/$athleteNumber/provision',
      {'delivery_method': deliveryMethod},
    );
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Provision failed'));
    }
    return jsonDecode(resp.body);
  }

  static Future<Map<String, dynamic>> reprovisionAccount(
    int branchId, int athleteNumber, String deliveryMethod,
  ) async {
    final resp = await _post(
      '/branches/$branchId/athletes/$athleteNumber/reprovision',
      {'delivery_method': deliveryMethod},
    );
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Re-provision failed'));
    }
    return jsonDecode(resp.body);
  }

  static Future<Map<String, dynamic>> markAsPaid(int branchId, int athleteNumber, {String paymentMethod = 'cash'}) async {
    final resp = await _post('/branches/$branchId/athletes/$athleteNumber/mark-paid', {'payment_method': paymentMethod});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to mark as paid'));
    }
    return jsonDecode(resp.body);
  }

  static Future<void> setAthleteBill(int branchId, int athleteNumber, double amount) async {
    final resp = await _post('/branches/$branchId/athletes/$athleteNumber/set-bill', {'amount': amount});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to set bill'));
    }
  }

  static Future<void> refreshBranch(int branchId) async {
    final resp = await _post('/branches/$branchId/refresh', {});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Refresh failed'));
    }
  }

  static Future<List<Map<String, dynamic>>> getBranchPayments(
    int branchId, {String? period, String? status}
  ) async {
    var path = '/branches/$branchId/payments';
    final params = <String>[];
    if (period != null) params.add('period=$period');
    if (status != null) params.add('status=$status');
    if (params.isNotEmpty) path += '?${params.join('&')}';

    final resp = await _get(path);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> adminResendReceipt(int receiptId) async {
    final resp = await _post('/admin/receipts/$receiptId/resend', {});
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
  }

  static Future<Map<String, dynamic>> getAnalytics({
    String scope = 'branch', int? branchId, String? period,
  }) async {
    var path = '/admin/analytics?scope=$scope';
    if (branchId != null) path += '&branch_id=$branchId';
    if (period != null) path += '&period=$period';
    final resp = await _get(path);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return jsonDecode(resp.body);
  }

  static Future<Map<String, dynamic>> getExcelHealth() async {
    final resp = await _get('/admin/health/excel');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return jsonDecode(resp.body);
  }

  static Future<List<Map<String, dynamic>>> getManageBranches() async {
    final resp = await _get('/admin/branches/manage');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createBranch({
    required String name, required String displayName, String? driveFileId,
  }) async {
    final resp = await _post('/admin/branches', {
      'name': name, 'display_name': displayName,
      if (driveFileId != null && driveFileId.isNotEmpty) 'drive_file_id': driveFileId,
    });
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to create branch'));
    }
    return jsonDecode(resp.body);
  }

  static Future<Map<String, dynamic>> updateBranch(int branchId, {
    String? displayName, String? driveFileId,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (driveFileId != null) body['drive_file_id'] = driveFileId;
    final resp = await _put('/admin/branches/$branchId', body);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to update branch'));
    }
    return jsonDecode(resp.body);
  }

  static Future<void> deleteBranch(int branchId) async {
    final resp = await _delete('/admin/branches/$branchId');
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to delete branch'));
    }
  }

  // ── Admin Reinstatement ──

  static Future<List<Map<String, dynamic>>> getReinstatementRequests({String? statusFilter}) async {
    var path = '/admin/reinstatement-requests';
    if (statusFilter != null) path += '?status_filter=$statusFilter';
    final resp = await _get(path);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> approveReinstatement(int requestId) async {
    final resp = await _post('/admin/reinstatement-requests/$requestId/approve', {});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to approve'));
    }
  }

  static Future<void> declineReinstatement(int requestId, {String? adminNote}) async {
    final resp = await _post('/admin/reinstatement-requests/$requestId/decline', {
      if (adminNote != null) 'admin_note': adminNote,
    });
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to decline'));
    }
  }

  static Future<List<int>> adminDownloadReceiptPdf(int receiptId) async {
    final resp = await _safeRequest(() async => http.get(
      Uri.parse('${AppConstants.baseUrl}/admin/receipts/$receiptId/pdf'),
      headers: await _headers(),
    ));
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        final retryResp = await _safeRequest(() async => http.get(
          Uri.parse('${AppConstants.baseUrl}/admin/receipts/$receiptId/pdf'),
          headers: await _headers(),
        ));
        if (retryResp.statusCode != 200) {
          throw ApiException(retryResp.statusCode, 'Failed to download PDF');
        }
        return retryResp.bodyBytes;
      }
    }
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp));
    }
    return resp.bodyBytes;
  }

  // ── Branch Admin Management ──

  static Future<Map<String, dynamic>> createBranchAdmin({
    required String email,
    required int branchId,
  }) async {
    final resp = await _post('/admin/branch-admins', {
      'email': email,
      'branch_id': branchId,
    });
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to create branch admin'));
    }
    return jsonDecode(resp.body);
  }

  static Future<List<Map<String, dynamic>>> getBranchAdmins() async {
    final resp = await _get('/admin/branch-admins');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> toggleBranchAdminActive(int adminId) async {
    final resp = await _put('/admin/branch-admins/$adminId/toggle-active', {});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to update'));
    }
  }

  static Future<Map<String, dynamic>> resetBranchAdminPassword(int adminId) async {
    final resp = await _post('/admin/branch-admins/$adminId/reset-password', {});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to reset password'));
    }
    return jsonDecode(resp.body);
  }

  // ── Price Catalog ──

  static Future<List<Map<String, dynamic>>> getMissingPrices() async {
    final resp = await _get('/admin/price-catalog/missing');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getPriceCatalog({int? branchId}) async {
    final path = branchId != null ? '/admin/price-catalog?branch_id=$branchId' : '/admin/price-catalog';
    final resp = await _get(path);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractError(resp));
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createPriceCatalogEntry({
    required int branchId, required String programName, required String price,
    String? segment, String? sessions,
  }) async {
    final resp = await _post('/admin/price-catalog', {
      'branch_id': branchId, 'program_name': programName, 'price': price,
      if (segment != null && segment.isNotEmpty) 'segment': segment,
      if (sessions != null && sessions.isNotEmpty) 'sessions': sessions,
    });
    if (resp.statusCode != 201) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to create catalog entry'));
    }
    return jsonDecode(resp.body);
  }

  static Future<Map<String, dynamic>> updatePriceCatalogEntry(int entryId, {
    String? programName, String? segment, String? sessions, String? price, bool? isActive,
  }) async {
    final body = <String, dynamic>{};
    if (programName != null) body['program_name'] = programName;
    if (segment != null) body['segment'] = segment;
    if (sessions != null) body['sessions'] = sessions;
    if (price != null) body['price'] = price;
    if (isActive != null) body['is_active'] = isActive;
    final resp = await _put('/admin/price-catalog/$entryId', body);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to update catalog entry'));
    }
    return jsonDecode(resp.body);
  }

  static Future<void> deletePriceCatalogEntry(int entryId) async {
    final resp = await _delete('/admin/price-catalog/$entryId');
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to delete catalog entry'));
    }
  }
}

class ApiException implements Exception, HasAppError {
  final int statusCode;
  final String? _serverMessage;

  /// [message] is what the server said for the user, or null when the app
  /// should use its own words for this kind of failure.
  ApiException(this.statusCode, String? message) : _serverMessage = message;

  bool get isNetwork => statusCode == 0;
  bool get isAuth => statusCode == 401 || statusCode == 403;
  bool get isServer => statusCode >= 500;
  bool get isNotFound => statusCode == 404;
  bool get isSuspended => statusCode == 423;

  @override
  AppError get appError {
    // The network layer raises status 0 for both "offline" and "too slow"
    if (statusCode == 0) {
      // A screen raised this itself, with its own sentence
      if (_serverMessage != null) return AppError(ErrorKind.rejected, _serverMessage);
      return AppError(_timedOut ? ErrorKind.timeout : ErrorKind.offline);
    }
    final kind = AppError.kindForStatus(statusCode);
    // A broken server's own text is never shown; everything else is
    return AppError(kind, kind == ErrorKind.server || kind == ErrorKind.tooMany ? null : _serverMessage);
  }

  bool _timedOut = false;

  /// Always safe to show: resolved in the app's current language.
  String get message => appError.message;

  @override
  String toString() => message;
}
