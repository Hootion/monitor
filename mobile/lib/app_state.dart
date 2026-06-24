import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_client.dart';
import 'models.dart';
import 'native_bridge.dart';

class AppState extends ChangeNotifier {
  AppState({
    ApiClient? api,
    NativeBridge? bridge,
  })  : api = api ?? ApiClient(),
        bridge = bridge ?? NativeBridge();

  final ApiClient api;
  final NativeBridge bridge;

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

  Timer? _syncTimer;
  io.Socket? _socket;

  Future<void> bootstrap() async {
    loading = true;
    notifyListeners();
    await api.loadTokens();
    if (api.accessToken != null) {
      try {
        user = await api.me();
        partner = await api.currentPartner();
        await bridge.startForegroundCollection();
        await syncTelemetry();
        await refreshPartner();
        _connectRealtime();
      } catch (exception) {
        error = exception.toString();
        await api.clearTokens();
        user = null;
      }
    }
    loading = false;
    _startPeriodicSync();
    notifyListeners();
  }

  Future<void> register(String name, String phone, String password) async {
    await _run(() async {
      final bundle = await api.register(displayName: name, phone: phone, password: password);
      user = bundle.user;
      partner = await api.currentPartner();
      await bridge.startForegroundCollection();
      _connectRealtime();
    });
  }

  Future<void> login(String phone, String password) async {
    await _run(() async {
      final bundle = await api.login(phone: phone, password: password);
      user = bundle.user;
      partner = await api.currentPartner();
      await bridge.startForegroundCollection();
      await refreshPartner();
      _connectRealtime();
    });
  }

  Future<void> logout() async {
    _socket?.dispose();
    _socket = null;
    user = null;
    partner = null;
    overview = null;
    appUsage = const [];
    events = const [];
    inviteCode = null;
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
    });
  }

  Future<void> setSharingPaused(bool paused) async {
    await _run(() async {
      user = await api.setSharingPaused(paused);
    });
  }

  Future<void> deleteMyData() async {
    await _run(() async {
      await api.deleteData();
    });
  }

  Future<void> openUsageAccessSettings() async {
    await bridge.openUsageAccessSettings();
    usageAccessGranted = await bridge.hasUsageAccess();
    notifyListeners();
  }

  Future<void> syncTelemetry() async {
    if (user == null || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      usageAccessGranted = await bridge.hasUsageAccess();
      final batch = await bridge.collectTelemetryBatch();
      await api.sendTelemetry(batch);
    } catch (exception) {
      error = exception.toString();
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
      notifyListeners();
      return;
    }
    await _run(() async {
      overview = await api.partnerOverview();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      appUsage = await api.partnerAppUsage(date);
      events = await api.partnerEvents();
      partner = overview?.partner ?? partner;
    }, setLoading: false);
  }

  Future<void> _run(Future<void> Function() task, {bool setLoading = true}) async {
    if (setLoading) {
      loading = true;
      notifyListeners();
    }
    error = null;
    try {
      await task();
    } catch (exception) {
      error = exception.toString();
    } finally {
      loading = false;
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

  void _connectRealtime() {
    _socket?.dispose();
    if (api.accessToken == null) return;
    _socket = io.io(
      api.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': api.accessToken})
          .build(),
    );
    _socket!
      ..on('partner.updated', (_) => refreshPartner())
      ..connect();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _socket?.dispose();
    super.dispose();
  }
}

