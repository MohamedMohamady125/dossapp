import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';
import '../models/athlete.dart';
import '../models/bill.dart';
import '../models/receipt.dart';

class ApiService {
  static const _storage = FlutterSecureStorage();
  static String? _accessToken;
  static String? _refreshToken;

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

  static Future<http.Response> _get(String path) async {
    final resp = await http.get(
      Uri.parse('${AppConstants.baseUrl}$path'),
      headers: await _headers(),
    );
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return http.get(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: await _headers(),
        );
      }
    }
    return resp;
  }

  static Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final resp = await http.post(
      Uri.parse('${AppConstants.baseUrl}$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (resp.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return http.post(
          Uri.parse('${AppConstants.baseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        );
      }
    }
    return resp;
  }

  static Future<bool> _tryRefresh() async {
    _refreshToken ??= await _storage.read(key: 'refresh_token');
    if (_refreshToken == null) return false;

    final resp = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': _refreshToken}),
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];
      await _storage.write(key: 'access_token', value: _accessToken!);
      await _storage.write(key: 'refresh_token', value: _refreshToken!);
      return true;
    }
    return false;
  }

  static Future<void> _saveTokens(Map<String, dynamic> data) async {
    _accessToken = data['access_token'];
    _refreshToken = data['refresh_token'];
    await _storage.write(key: 'access_token', value: _accessToken!);
    await _storage.write(key: 'refresh_token', value: _refreshToken!);
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

  static Future<Map<String, dynamic>> customerLogin(String code, String password) async {
    final resp = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/customer/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'login_code': code, 'password': password}),
    );
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, jsonDecode(resp.body)['detail'] ?? 'Login failed');
    }
    final data = jsonDecode(resp.body);
    await _saveTokens(data);
    return data;
  }

  static Future<void> changePassword(String newPassword) async {
    final resp = await _post('/auth/customer/change-password', {'new_password': newPassword});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, jsonDecode(resp.body)['detail'] ?? 'Failed');
    }
  }

  // ── Admin Auth ──

  static Future<Map<String, dynamic>> adminLogin(String username, String password) async {
    final resp = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, jsonDecode(resp.body)['detail'] ?? 'Login failed');
    }
    final data = jsonDecode(resp.body);
    await _saveTokens(data);
    return data;
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
    final resp = await _post('/me/pay/paymob/intent', {});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, jsonDecode(resp.body)['detail'] ?? 'Payment failed');
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

  // ── Admin Endpoints ──

  static Future<List<Map<String, dynamic>>> getBranches() async {
    final resp = await _get('/branches');
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to load branches');
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<AthleteDetail>> getBranchAthletes(int branchId) async {
    final resp = await _get('/branches/$branchId/athletes');
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
      throw ApiException(resp.statusCode, jsonDecode(resp.body)['detail'] ?? 'Provision failed');
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
      throw ApiException(resp.statusCode, jsonDecode(resp.body)['detail'] ?? 'Re-provision failed');
    }
    return jsonDecode(resp.body);
  }

  static Future<Map<String, dynamic>> markAsPaid(int branchId, int athleteNumber) async {
    final resp = await _post('/branches/$branchId/athletes/$athleteNumber/mark-paid', {});
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, jsonDecode(resp.body)['detail'] ?? 'Failed to mark as paid');
    }
    return jsonDecode(resp.body);
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
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}
