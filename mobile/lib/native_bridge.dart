import 'dart:io';

import 'package:flutter/services.dart';

import 'models.dart';

class NativeBridge {
  static const _channel = MethodChannel('app.mutual_watch/device');

  Future<bool> hasUsageAccess() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
  }

  Future<void> openUsageAccessSettings() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openUsageAccessSettings');
    }
  }

  Future<void> startForegroundCollection() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('startForegroundCollection');
    }
  }

  Future<TelemetryBatch> collectTelemetryBatch() async {
    final snapshot = await _mapCall('getDeviceSnapshot');
    final report = await _mapCall('getTodayUsageReport');
    final usage = await _listCall('getAppUsage');
    final events = await _listCall('getRecentEvents');

    return TelemetryBatch(
      deviceSnapshot: snapshot == null ? _fallbackSnapshot() : DeviceSnapshot.fromJson(snapshot),
      dailyReport: report == null ? _fallbackReport() : DailyUsageReport.fromJson(report),
      appUsageSessions: usage.map(AppUsageSession.fromJson).toList(),
      events: events.map(OperationEvent.fromJson).toList(),
    );
  }

  Future<Map<String, dynamic>?> _mapCall(String method) async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(method);
      return value == null ? null : Map<String, dynamic>.from(value);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _listCall(String method) async {
    try {
      final value = await _channel.invokeListMethod<dynamic>(method) ?? const [];
      return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  DeviceSnapshot _fallbackSnapshot() => DeviceSnapshot(
        platform: Platform.isIOS ? 'ios' : 'android',
        capturedAt: DateTime.now().toIso8601String(),
        unsupported: const ['native_bridge_unavailable'],
      );

  DailyUsageReport _fallbackReport() => DailyUsageReport(
        date: DateTime.now().toIso8601String().substring(0, 10),
        platform: Platform.isIOS ? 'ios' : 'android',
        screenTimeMs: 0,
        pickupCount: 0,
        longestContinuousMs: 0,
        unsupported: const ['usage_report_unavailable'],
      );
}

