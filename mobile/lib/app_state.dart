import 'dart:async';

import 'package:flutter/foundation.dart';

import 'amap_location_collector.dart';
import 'api_client.dart';
import 'models.dart';
import 'native_bridge.dart';

class AppState extends ChangeNotifier {
  AppState({
    ApiClient? api,
    NativeBridge? bridge,
    AmapLocationCollector? locationCollector,
  })  : api = api ?? ApiClient(),
        bridge = bridge ?? NativeBridge(),
        locationCollector = locationCollector ?? AmapLocationCollector();

  final ApiClient api;
  final NativeBridge bridge;
  final AmapLocationCollector locationCollector;

  PublicUser? user;
  PublicUser? partner;
  PartnerOverview? overview;
  List<AppUsageSession> appUsage = const [];
  List<OperationEvent> events = const [];
  bool loading = true;
  bool syncing = false;
  bool usageAccessGranted = true;
  String? inviteCode;
  String? error;
  DateTime? lastSyncedAt;
  DateTime? lastRefreshedAt;
  AppUpdateInfo? updateInfo;
  bool checkingForUpdate = false;
  bool updatePromptShown = false;

  Timer? _syncTimer;
  Timer? _partnerLiveRefreshTimer;
  bool _partnerLiveRefreshEnabled = false;
  bool _partnerLiveRefreshInFlight = false;
  bool _foregroundLocationInFlight = false;
  DateTime? _lastForegroundLocationSentAt;

  static const currentVersionCode =
      int.fromEnvironment('APP_VERSION_CODE', defaultValue: 1);
  static const currentVersionName =
      String.fromEnvironment('APP_VERSION_NAME', defaultValue: '0.1.0');
  static const amapAndroidKey =
      String.fromEnvironment('AMAP_ANDROID_KEY', defaultValue: '');
  static const sessionExpiredMessage = '登录已过期，请重新登录。';

  Future<void> bootstrap() async {
    loading = true;
    notifyListeners();
    await api.loadTokens();
    if (api.accessToken == null && api.refreshToken != null) {
      await api.refreshSession();
    }
    if (api.accessToken != null) {
      try {
        user = await api.me();
        partner = await api.currentPartner();
        await _startForegroundCollection();
        await _updateForegroundLocationCollector();
        await syncTelemetry();
        await refreshPartner();
      } catch (exception) {
        if (exception is ApiException && exception.statusCode == 401) {
          await _expireSession();
        } else {
          error = exception.toString();
          await api.clearTokens();
          user = null;
        }
      }
    }
    loading = false;
    _startPeriodicSync();
    notifyListeners();
  }

  Future<void> register(String name, String phone, String password) async {
    await _run(() async {
      final bundle = await api.register(
          displayName: name, phone: phone, password: password);
      user = bundle.user;
      partner = await api.currentPartner();
      await _startForegroundCollection();
      await _updateForegroundLocationCollector();
    });
  }

  Future<void> login(String phone, String password) async {
    await _run(() async {
      final bundle = await api.login(phone: phone, password: password);
      user = bundle.user;
      partner = await api.currentPartner();
      await _startForegroundCollection();
      await _updateForegroundLocationCollector();
      await refreshPartner();
    });
  }

  Future<void> logout() async {
    user = null;
    partner = null;
    overview = null;
    appUsage = const [];
    events = const [];
    inviteCode = null;
    error = null;
    loading = false;
    syncing = false;
    lastSyncedAt = null;
    lastRefreshedAt = null;
    updateInfo = null;
    updatePromptShown = false;
    setPartnerLiveRefreshEnabled(false);
    await locationCollector.stop();
    await api.clearTokens();
    notifyListeners();
  }

  Future<void> createInvite() async {
    await _run(() async {
      inviteCode = await api.createInvite();
    });
  }

  Future<void> acceptInvite(String code) async {
    await _run(() async {
      await api.acceptInvite(code);
      partner = await api.currentPartner();
      inviteCode = null;
      await refreshPartner();
    });
  }

  Future<void> unpair() async {
    await _run(() async {
      await api.unpair();
      partner = null;
      overview = null;
      appUsage = const [];
      events = const [];
      inviteCode = null;
      lastRefreshedAt = null;
      setPartnerLiveRefreshEnabled(false);
    });
  }

  Future<void> setSharingPaused(bool paused) async {
    await _run(() async {
      user = await api.setSharingPaused(paused);
      await _updateForegroundLocationCollector();
    });
  }

  Future<void> deleteMyData() async {
    await _run(() async {
      await api.deleteData();
    });
  }

  Future<void> openUsageAccessSettings() async {
    await bridge.openUsageAccessSettings();
    await refreshUsageAccess();
  }

  Future<void> openAppSettings() async {
    await bridge.openAppSettings();
    await refreshUsageAccess();
  }

  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (checkingForUpdate) {
      return updateInfo;
    }
    if (!force && (updatePromptShown || !api.hasAccessToken)) {
      return updateInfo;
    }
    checkingForUpdate = true;
    notifyListeners();
    try {
      updateInfo = await api.checkForUpdate(
        currentVersionCode: currentVersionCode,
      );
      if (updateInfo != null) {
        updatePromptShown = true;
      }
      return updateInfo;
    } catch (_) {
      return null;
    } finally {
      checkingForUpdate = false;
      notifyListeners();
    }
  }

  Future<void> openUpdateDownload(AppUpdateInfo update) async {
    await bridge.openUrl(update.apkUrl);
  }

  void dismissUpdatePrompt() {
    updatePromptShown = true;
    notifyListeners();
  }

  Future<void> refreshUsageAccess() async {
    usageAccessGranted = await bridge.hasUsageAccess();
    notifyListeners();
  }

  void clearError() {
    if (error == null) {
      return;
    }
    error = null;
    notifyListeners();
  }

  Future<void> syncTelemetry() async {
    if (user == null || user?.sharingPaused == true || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      await _startForegroundCollection();
      usageAccessGranted = await bridge.hasUsageAccess();
      final batch = await bridge.collectTelemetryBatch();
      await api.sendTelemetry(batch);
      lastSyncedAt = DateTime.now();
    } catch (exception) {
      await _handleException(exception);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshPartner() async {
    if (partner == null) {
      try {
        partner = await api.currentPartner();
      } catch (_) {
        partner = null;
      }
    }
    if (partner == null) {
      overview = null;
      appUsage = const [];
      events = const [];
      lastRefreshedAt = null;
      notifyListeners();
      return;
    }
    await _run(() async {
      overview = await api.partnerOverview();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      appUsage = await api.partnerAppUsage(date);
      events = await api.partnerEvents();
      partner = overview?.partner ?? partner;
      lastRefreshedAt = DateTime.now();
    }, setLoading: false);
  }

  void setPartnerLiveRefreshEnabled(bool enabled) {
    if (_partnerLiveRefreshEnabled == enabled) {
      return;
    }
    _partnerLiveRefreshEnabled = enabled;
    _partnerLiveRefreshTimer?.cancel();
    _partnerLiveRefreshTimer = null;
    if (!enabled) {
      return;
    }
    _partnerLiveRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) async {
      await _liveRefreshPartner();
    });
  }

  Future<void> _liveRefreshPartner() async {
    if (!_partnerLiveRefreshEnabled ||
        _partnerLiveRefreshInFlight ||
        user == null ||
        partner == null) {
      return;
    }
    _partnerLiveRefreshInFlight = true;
    try {
      await refreshPartner();
    } finally {
      _partnerLiveRefreshInFlight = false;
    }
  }

  Future<void> _run(Future<void> Function() task,
      {bool setLoading = true}) async {
    if (setLoading) {
      loading = true;
      notifyListeners();
    }
    error = null;
    try {
      await task();
    } catch (exception) {
      await _handleException(exception);
    } finally {
      if (setLoading) {
        loading = false;
      }
      notifyListeners();
    }
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await syncTelemetry();
      await refreshPartner();
    });
  }

  Future<void> _handleException(Object exception) async {
    if (exception is ApiException &&
        exception.statusCode == 401 &&
        user != null) {
      await _expireSession();
      return;
    }
    error = exception.toString();
  }

  Future<void> _expireSession() async {
    setPartnerLiveRefreshEnabled(false);
    await locationCollector.stop();
    user = null;
    partner = null;
    overview = null;
    appUsage = const [];
    events = const [];
    inviteCode = null;
    syncing = false;
    lastSyncedAt = null;
    lastRefreshedAt = null;
    updateInfo = null;
    updatePromptShown = false;
    await api.clearTokens();
    error = sessionExpiredMessage;
  }

  Future<void> _startForegroundCollection() {
    return bridge.startForegroundCollection(
      apiBaseUrl: api.baseUrl,
      accessToken: api.accessToken,
      refreshToken: api.refreshToken,
    );
  }

  Future<void> _updateForegroundLocationCollector() async {
    if (user == null ||
        user?.sharingPaused == true ||
        !AmapLocationCollector.canRun(amapAndroidKey)) {
      await locationCollector.stop();
      return;
    }
    await locationCollector.start(
      androidKey: amapAndroidKey,
      onLocation: _uploadForegroundLocation,
    );
  }

  Future<void> _uploadForegroundLocation(DeviceLocation location) async {
    if (user == null || user?.sharingPaused == true) {
      return;
    }
    final now = DateTime.now();
    final previous = _lastForegroundLocationSentAt;
    if (_foregroundLocationInFlight ||
        (previous != null &&
            now.difference(previous) < const Duration(seconds: 5))) {
      return;
    }
    _foregroundLocationInFlight = true;
    try {
      await api.sendTelemetry(TelemetryBatch(locationSnapshot: location));
      _lastForegroundLocationSentAt = now;
      lastSyncedAt = DateTime.now();
      notifyListeners();
    } catch (exception) {
      await _handleException(exception);
    } finally {
      _foregroundLocationInFlight = false;
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _partnerLiveRefreshTimer?.cancel();
    unawaited(locationCollector.dispose());
    super.dispose();
  }
}
