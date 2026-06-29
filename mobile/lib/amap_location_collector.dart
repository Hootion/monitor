import 'dart:async';
import 'dart:io' show Platform;

import 'package:amap_flutter_location/amap_flutter_location.dart';
import 'package:amap_flutter_location/amap_location_option.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class AmapLocationCollector {
  AmapLocationCollector({AMapFlutterLocation? plugin})
      : _plugin = plugin ?? AMapFlutterLocation();

  final AMapFlutterLocation _plugin;
  StreamSubscription<Map<String, Object>>? _subscription;
  bool _started = false;
  String? _activeAndroidKey;
  Future<void> Function(DeviceLocation location)? _onLocation;

  bool get isStarted => _started;

  static bool canRun(String androidKey) =>
      Platform.isAndroid && androidKey.trim().isNotEmpty;

  Future<void> start({
    required String androidKey,
    required Future<void> Function(DeviceLocation location) onLocation,
  }) async {
    final key = androidKey.trim();
    if (!canRun(key)) {
      await stop();
      return;
    }
    _onLocation = onLocation;
    if (_started && _activeAndroidKey == key) {
      return;
    }
    await stop();
    _activeAndroidKey = key;

    AMapFlutterLocation.updatePrivacyShow(true, true);
    AMapFlutterLocation.updatePrivacyAgree(true);
    AMapFlutterLocation.setApiKey(key, '');

    final option = AMapLocationOption()
      ..onceLocation = false
      ..needAddress = false
      ..geoLanguage = GeoLanguage.DEFAULT
      ..locationInterval = 15000
      ..locationMode = AMapLocationMode.Hight_Accuracy
      ..distanceFilter = 10
      ..desiredAccuracy = DesiredAccuracy.Best
      ..pausesLocationUpdatesAutomatically = false;

    _plugin.setLocationOption(option);
    _subscription = _plugin.onLocationChanged().listen(_handleLocation);
    _plugin.startLocation();
    _started = true;
  }

  Future<void> stop() async {
    if (_subscription != null) {
      await _subscription?.cancel();
      _subscription = null;
    }
    if (_started) {
      _plugin.stopLocation();
    }
    _started = false;
    _activeAndroidKey = null;
    _onLocation = null;
  }

  Future<void> dispose() async {
    await stop();
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    try {
      _plugin.destroy();
    } on MissingPluginException {
      // Widget tests and unsupported desktop hosts do not register the native plugin.
    }
  }

  void _handleLocation(Map<String, Object> result) {
    final location = _locationFromResult(result);
    final callback = _onLocation;
    if (callback == null) {
      return;
    }
    unawaited(callback(location));
  }

  DeviceLocation _locationFromResult(Map<String, Object> result) {
    final errorCode = result['errorCode']?.toString();
    final latitude = _asDouble(result['latitude']);
    final longitude = _asDouble(result['longitude']);
    final accuracy = _asDouble(result['accuracy']);
    final hasCoordinates = latitude != null && longitude != null;
    final status = hasCoordinates
        ? 'available'
        : errorCode == '12'
            ? 'unauthorized'
            : 'unavailable';

    return DeviceLocation(
      platform: 'android',
      capturedAt: DateTime.now().toIso8601String(),
      status: status,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
    );
  }
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
