import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
      defaultValue: 'https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api',
    ),
    this.updateUrl = const String.fromEnvironment(
      'APP_UPDATE_URL',
      defaultValue:
          'https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update',
    ),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String updateUrl;
  final http.Client _client;
  String? accessToken;
  String? refreshToken;
  Future<bool>? _refreshInFlight;

  bool get hasAccessToken => accessToken?.isNotEmpty == true;

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
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

  Future<bool> refreshSession() async {
    if (refreshToken == null || refreshToken!.isEmpty) {
      await loadTokens();
    }
    final token = refreshToken;
    if (token == null) return false;
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    _refreshInFlight = _refreshSession(token);
    try {
      return await _refreshInFlight!;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<bool> _refreshSession(String token) async {
    try {
      final json = await _request(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': token},
        auth: false,
        refreshOnUnauthorized: false,
      );
      final bundle = AuthBundle.fromJson(json);
      await saveTokens(bundle);
      return true;
    } catch (exception) {
      final recovered = await _loadTokensIfAnotherProcessRefreshed(token);
      if (recovered) {
        return true;
      }
      if (exception is ApiException && exception.statusCode == 401) {
        await clearTokens();
      }
      return false;
    }
  }

  Future<bool> _loadTokensIfAnotherProcessRefreshed(String staleToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final latestAccessToken = prefs.getString('accessToken');
    final latestRefreshToken = prefs.getString('refreshToken');
    if (latestAccessToken?.isNotEmpty == true &&
        latestRefreshToken?.isNotEmpty == true &&
        latestRefreshToken != staleToken) {
      accessToken = latestAccessToken;
      refreshToken = latestRefreshToken;
      return true;
    }
    return false;
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
    final json =
        await _request('POST', '/sharing/pause', body: {'paused': paused});
    return PublicUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<void> deleteData() async {
    await _request('POST', '/account/delete-data');
  }

  Future<PublicUser> updateProfile({
    required String displayName,
    required String gender,
    String? moodStatus,
    List<int>? avatarBytes,
    String? avatarFileName,
    String? avatarMimeType,
  }) async {
    if (avatarBytes == null) {
      final json = await _request(
        'POST',
        '/account/profile',
        body: {
          'displayName': displayName,
          'moodStatus': moodStatus,
          'gender': gender,
        },
      );
      return PublicUser.fromJson(json['user'] as Map<String, dynamic>);
    }
    final json = await _multipartProfileRequest(
      displayName: displayName,
      moodStatus: moodStatus,
      gender: gender,
      avatarBytes: avatarBytes,
      avatarFileName: avatarFileName,
      avatarMimeType: avatarMimeType,
    );
    return PublicUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<AppUpdateInfo?> checkForUpdate({
    required int currentVersionCode,
  }) async {
    final uri = Uri.parse(updateUrl).replace(queryParameters: {
      'platform': 'android',
      'currentVersionCode': currentVersionCode.toString(),
    });
    final response = await _client.get(uri);
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        decoded['message']?.toString() ?? '检查更新失败',
        response.statusCode,
      );
    }
    if (decoded['updateAvailable'] != true) {
      return null;
    }
    return AppUpdateInfo.fromJson(decoded);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool refreshOnUnauthorized = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    String? requestAccessToken;
    if (auth) {
      final token = accessToken;
      if (token == null || token.isEmpty) {
        throw const ApiException('登录已过期，请重新登录。', 401);
      }
      requestAccessToken = token;
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await _client.send(
      http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body),
    );
    final text = await response.stream.bytesToString();
    final decoded = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode == 401 &&
        auth &&
        refreshOnUnauthorized &&
        refreshToken != null) {
      final refreshed = await refreshSession();
      if (refreshed) {
        return _request(
          method,
          path,
          body: body,
          auth: auth,
          refreshOnUnauthorized: false,
        );
      }
      final staleToken = requestAccessToken;
      await loadTokens();
      if (accessToken?.isNotEmpty == true && accessToken != staleToken) {
        return _request(
          method,
          path,
          body: body,
          auth: auth,
          refreshOnUnauthorized: false,
        );
      }
    }
    if (response.statusCode >= 400) {
      throw ApiException(
          decoded['message']?.toString() ?? '请求失败', response.statusCode);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _multipartProfileRequest({
    required String displayName,
    required String gender,
    required List<int> avatarBytes,
    String? moodStatus,
    String? avatarFileName,
    String? avatarMimeType,
    bool refreshOnUnauthorized = true,
  }) async {
    final uri = Uri.parse('$baseUrl/account/profile');
    final token = accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('登录已过期，请重新登录。', 401);
    }
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['displayName'] = displayName
      ..fields['moodStatus'] = moodStatus ?? ''
      ..fields['gender'] = gender
      ..files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          avatarBytes,
          filename: avatarFileName ?? 'avatar.jpg',
          contentType: MediaType.parse(avatarMimeType ?? 'image/jpeg'),
        ),
      );
    final response = await _client.send(request);
    final text = await response.stream.bytesToString();
    final decoded = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode == 401 &&
        refreshOnUnauthorized &&
        refreshToken != null) {
      final refreshed = await refreshSession();
      if (refreshed) {
        return _multipartProfileRequest(
          displayName: displayName,
          moodStatus: moodStatus,
          gender: gender,
          avatarBytes: avatarBytes,
          avatarFileName: avatarFileName,
          avatarMimeType: avatarMimeType,
          refreshOnUnauthorized: false,
        );
      }
    }
    if (response.statusCode >= 400) {
      throw ApiException(
          decoded['message']?.toString() ?? '请求失败', response.statusCode);
    }
    return decoded;
  }
}
