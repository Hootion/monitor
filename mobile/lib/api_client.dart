import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, this.statusCode);

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000',
    ),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? accessToken;
  String? refreshToken;

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('accessToken');
    refreshToken = prefs.getString('refreshToken');
  }

  Future<void> saveTokens(AuthBundle bundle) async {
    accessToken = bundle.accessToken;
    refreshToken = bundle.refreshToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accessToken', bundle.accessToken);
    await prefs.setString('refreshToken', bundle.refreshToken);
  }

  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
  }

  Future<AuthBundle> register({
    required String displayName,
    required String phone,
    required String password,
  }) async {
    final json = await _request(
      'POST',
      '/auth/register',
      body: {'displayName': displayName, 'phone': phone, 'password': password},
      auth: false,
    );
    final bundle = AuthBundle.fromJson(json);
    await saveTokens(bundle);
    return bundle;
  }

  Future<AuthBundle> login({
    required String phone,
    required String password,
  }) async {
    final json = await _request(
      'POST',
      '/auth/login',
      body: {'phone': phone, 'password': password},
      auth: false,
    );
    final bundle = AuthBundle.fromJson(json);
    await saveTokens(bundle);
    return bundle;
  }

  Future<PublicUser> me() async {
    final json = await _request('GET', '/auth/me');
    return PublicUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<String> createInvite() async {
    final json = await _request('POST', '/pairing/invite');
    return (json['invite'] as Map<String, dynamic>)['code'] as String;
  }

  Future<void> acceptInvite(String code) async {
    await _request('POST', '/pairing/accept', body: {'code': code});
  }

  Future<PublicUser?> currentPartner() async {
    final json = await _request('GET', '/pairing/current');
    final partner = json['partner'];
    if (partner == null) return null;
    return PublicUser.fromJson(partner as Map<String, dynamic>);
  }

  Future<void> unpair() async {
    await _request('DELETE', '/pairing/current');
  }

  Future<void> sendTelemetry(TelemetryBatch batch) async {
    await _request('POST', '/telemetry/batch', body: batch.toJson());
  }

  Future<PartnerOverview> partnerOverview() async {
    final json = await _request('GET', '/partner/overview');
    return PartnerOverview.fromJson(json);
  }

  Future<List<AppUsageSession>> partnerAppUsage(String date) async {
    final json = await _request('GET', '/partner/app-usage?date=$date');
    return (json['sessions'] as List<dynamic>? ?? const [])
        .map((item) => AppUsageSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<OperationEvent>> partnerEvents() async {
    final json = await _request('GET', '/partner/events?limit=100');
    return (json['events'] as List<dynamic>? ?? const [])
        .map((item) => OperationEvent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PublicUser> setSharingPaused(bool paused) async {
    final json = await _request('POST', '/sharing/pause', body: {'paused': paused});
    return PublicUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<void> deleteData() async {
    await _request('POST', '/account/delete-data');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    final response = await _client.send(
      http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body),
    );
    final text = await response.stream.bytesToString();
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(decoded['message']?.toString() ?? '请求失败', response.statusCode);
    }
    return decoded;
  }
}

