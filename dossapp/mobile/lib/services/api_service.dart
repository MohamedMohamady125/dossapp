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

  /// Wraps network exceptions into user-friendly ApiException.
  static Future<http.Response> _safeRequest(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on SocketException {
      throw ApiException(0, 'No internet connection. Check your network and try again.');
    } on TimeoutException {
      throw ApiException(0, 'Server is taking too long to respond. Please try again.');
    } on HttpException {
      throw ApiException(0, 'Could not connect to the server. Please try again later.');
    } on HandshakeException {
      throw ApiException(0, 'Secure connection failed. Please try again later.');
    }
  }

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

  static Future<http.Response> _post(String path, Map<String, dynamic> body) async {
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

  static Future<http.Response> _delete(String path) async {
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

  static Future<http.Response> _put(String path, Map<String, dynamic> body) async {
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
    await _storage.deleteAll();
  }

  static Future<bool> hasToken() async {
    final token = await _storage.read(key: 'access_token');
    return token != null;
  }

  // ── Customer Auth ──

  static String _extractError(http.Response resp, String fallback) {
    try {
      return jsonDecode(resp.body)['detail'] ?? fallback;
    } catch (_) {
      return fallback;
    }
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
    final resp = await _post('/auth/customer/verify-code', {'email': email, 'code': code});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Verification failed'));
    }
    final data = jsonDecode(resp.body);
    return data['verified'] == true;
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
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load profile');
    return AthleteProfile.fromJson(jsonDecode(resp.body));
  }

  static Future<Bill> getBill() async {
    final resp = await _get('/me/bill');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load bill');
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
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load receipts');
    final list = jsonDecode(resp.body) as List;
    return list.map((r) => Receipt.fromJson(r)).toList();
  }

  static Future<void> resendReceipt(int receiptId) async {
    final resp = await _post('/me/receipts/$receiptId/resend', {});
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Resend failed');
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
      throw ApiException(resp.statusCode, 'Failed to download PDF');
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

  static Future<List<Map<String, dynamic>>> getNotifications({int limit = 50, int offset = 0}) async {
    final resp = await _get('/me/notifications?limit=$limit&offset=$offset');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load notifications');
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<int> getUnreadCount() async {
    final resp = await _get('/me/notifications/unread-count');
    if (resp.statusCode != 200) return 0;
    return jsonDecode(resp.body)['unread'] ?? 0;
  }

  static Future<void> markNotificationRead(int id) async {
    final resp = await _post('/me/notifications/$id/read', {});
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to mark read');
  }

  static Future<void> markAllNotificationsRead() async {
    final resp = await _post('/me/notifications/read-all', {});
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to mark all read');
  }

  // ── Reinstatement ──

  static Future<ReinstatementStatus> getReinstatementStatus() async {
    final resp = await _get('/me/reinstatement');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load reinstatement status');
    return ReinstatementStatus.fromJson(jsonDecode(resp.body));
  }

  static Future<void> requestReinstatement({String? message}) async {
    final resp = await _post('/me/reinstatement', {if (message != null) 'message': message});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _extractError(resp, 'Failed to submit request'));
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
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load branches');
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<AthleteDetail>> getBranchAthletes(int branchId, {String? search}) async {
    var path = '/branches/$branchId/athletes';
    if (search != null && search.isNotEmpty) path += '?search=${Uri.encodeComponent(search)}';
    final resp = await _get(path);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load athletes');
    final list = jsonDecode(resp.body) as List;
    return list.map((a) => AthleteDetail.fromJson(a)).toList();
  }

  static Future<AthleteDetail> getAthleteDetail(int branchId, int athleteNumber) async {
    final resp = await _get('/branches/$branchId/athletes/$athleteNumber');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load athlete');
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
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load payments');
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> adminResendReceipt(int receiptId) async {
    final resp = await _post('/admin/receipts/$receiptId/resend', {});
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Resend failed');
  }

  static Future<Map<String, dynamic>> getAnalytics({
    String scope = 'branch', int? branchId, String? period,
  }) async {
    var path = '/admin/analytics?scope=$scope';
    if (branchId != null) path += '&branch_id=$branchId';
    if (period != null) path += '&period=$period';
    final resp = await _get(path);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load analytics');
    return jsonDecode(resp.body);
  }

  static Future<Map<String, dynamic>> getExcelHealth() async {
    final resp = await _get('/admin/health/excel');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load health');
    return jsonDecode(resp.body);
  }

  static Future<List<Map<String, dynamic>>> getManageBranches() async {
    final resp = await _get('/admin/branches/manage');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load branches');
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
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load requests');
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
      throw ApiException(resp.statusCode, 'Failed to download PDF');
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
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load branch admins');
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
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load missing prices');
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getPriceCatalog({int? branchId}) async {
    final path = branchId != null ? '/admin/price-catalog?branch_id=$branchId' : '/admin/price-catalog';
    final resp = await _get(path);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load price catalog');
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

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  bool get isNetwork => statusCode == 0;
  bool get isAuth => statusCode == 401 || statusCode == 403;
  bool get isServer => statusCode >= 500;
  bool get isNotFound => statusCode == 404;
  bool get isSuspended => statusCode == 423;

  @override
  String toString() => message;
}
