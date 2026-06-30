import 'dart:convert';

class PublicUser {
  const PublicUser({
    required this.id,
    required this.displayName,
    required this.sharingPaused,
    this.avatarUrl,
    this.moodStatus,
    this.gender = 'unspecified',
    this.phone,
    this.createdAt,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? moodStatus;
  final String gender;
  final bool sharingPaused;
  final String? phone;
  final String? createdAt;

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '未命名',
        avatarUrl: json['avatarUrl'] as String?,
        moodStatus: json['moodStatus'] as String?,
        gender: json['gender'] as String? ?? 'unspecified',
        sharingPaused: json['sharingPaused'] as bool? ?? false,
        phone: json['phone'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class AuthBundle {
  const AuthBundle({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final PublicUser user;
  final String accessToken;
  final String refreshToken;

  factory AuthBundle.fromJson(Map<String, dynamic> json) => AuthBundle(
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      );
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseNotes,
    required this.required,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String releaseNotes;
  final bool required;

  bool get hasDownload => apkUrl.trim().isNotEmpty;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        versionName: json['versionName'] as String? ?? '',
        versionCode: _asInt(json['versionCode']) ?? 0,
        apkUrl: json['apkUrl'] as String? ?? '',
        releaseNotes: json['releaseNotes'] as String? ?? '',
        required: json['required'] as bool? ?? false,
      );
}

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.platform,
    required this.capturedAt,
    this.wifiBytesToday,
    this.mobileBytesToday,
    this.networkSpeedKbps,
    this.networkType,
    this.networkName,
    this.bluetoothState,
    this.volumePercent,
    this.batteryPercent,
    this.batteryCharging,
    this.model,
    this.osVersion,
    this.storageUsedBytes,
    this.storageTotalBytes,
    this.unsupported = const [],
  });

  final String platform;
  final String capturedAt;
  final int? wifiBytesToday;
  final int? mobileBytesToday;
  final int? networkSpeedKbps;
  final String? networkType;
  final String? networkName;
  final String? bluetoothState;
  final int? volumePercent;
  final int? batteryPercent;
  final bool? batteryCharging;
  final String? model;
  final String? osVersion;
  final int? storageUsedBytes;
  final int? storageTotalBytes;
  final List<String> unsupported;

  factory DeviceSnapshot.fromJson(Map<String, dynamic> json) => DeviceSnapshot(
        platform: json['platform'] as String? ?? 'android',
        capturedAt:
            json['capturedAt'] as String? ?? DateTime.now().toIso8601String(),
        wifiBytesToday: _asInt(json['wifiBytesToday']),
        mobileBytesToday: _asInt(json['mobileBytesToday']),
        networkSpeedKbps: _asInt(json['networkSpeedKbps']),
        networkType: json['networkType'] as String?,
        networkName: json['networkName'] as String?,
        bluetoothState: json['bluetoothState'] as String?,
        volumePercent: _asInt(json['volumePercent']),
        batteryPercent: _asInt(json['batteryPercent']),
        batteryCharging: json['batteryCharging'] as bool?,
        model: json['model'] as String?,
        osVersion: json['osVersion'] as String?,
        storageUsedBytes: _asInt(json['storageUsedBytes']),
        storageTotalBytes: _asInt(json['storageTotalBytes']),
        unsupported: (json['unsupported'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'capturedAt': capturedAt,
        'wifiBytesToday': wifiBytesToday,
        'mobileBytesToday': mobileBytesToday,
        'networkSpeedKbps': networkSpeedKbps,
        'networkType': networkType,
        'networkName': networkName,
        'bluetoothState': bluetoothState,
        'volumePercent': volumePercent,
        'batteryPercent': batteryPercent,
        'batteryCharging': batteryCharging,
        'model': model,
        'osVersion': osVersion,
        'storageUsedBytes': storageUsedBytes,
        'storageTotalBytes': storageTotalBytes,
        'unsupported': unsupported,
      };
}

class DailyUsageReport {
  const DailyUsageReport({
    required this.date,
    required this.platform,
    required this.screenTimeMs,
    required this.pickupCount,
    required this.longestContinuousMs,
    this.firstUseAt,
    this.unsupported = const [],
  });

  final String date;
  final String platform;
  final int screenTimeMs;
  final int pickupCount;
  final int longestContinuousMs;
  final String? firstUseAt;
  final List<String> unsupported;

  factory DailyUsageReport.fromJson(Map<String, dynamic> json) =>
      DailyUsageReport(
        date: json['date'] as String? ??
            DateTime.now().toIso8601String().substring(0, 10),
        platform: json['platform'] as String? ?? 'android',
        screenTimeMs: _asInt(json['screenTimeMs']) ?? 0,
        pickupCount: _asInt(json['pickupCount']) ?? 0,
        longestContinuousMs: _asInt(json['longestContinuousMs']) ?? 0,
        firstUseAt: json['firstUseAt'] as String?,
        unsupported: (json['unsupported'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'platform': platform,
        'screenTimeMs': screenTimeMs,
        'pickupCount': pickupCount,
        'firstUseAt': firstUseAt,
        'longestContinuousMs': longestContinuousMs,
        'unsupported': unsupported,
      };
}

class DeviceLocation {
  const DeviceLocation({
    required this.platform,
    required this.capturedAt,
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  });

  final String platform;
  final String capturedAt;
  final String status;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  factory DeviceLocation.fromJson(Map<String, dynamic> json) => DeviceLocation(
        platform: json['platform'] as String? ?? 'android',
        capturedAt:
            json['capturedAt'] as String? ?? DateTime.now().toIso8601String(),
        status: json['status'] as String? ?? 'unknown',
        latitude: _asDouble(json['latitude']),
        longitude: _asDouble(json['longitude']),
        accuracyMeters: _asDouble(json['accuracyMeters']),
      );

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'capturedAt': capturedAt,
        'status': status,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
      };
}

class AppUsageSession {
  const AppUsageSession({
    required this.packageName,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.platform,
    this.appName,
    this.clientSessionId,
    this.openCount,
  });

  final String packageName;
  final String? appName;
  final String? clientSessionId;
  final String startedAt;
  final String endedAt;
  final int durationMs;
  final int? openCount;
  final String platform;

  factory AppUsageSession.fromJson(Map<String, dynamic> json) =>
      AppUsageSession(
        packageName: json['packageName'] as String? ?? 'unknown',
        appName: json['appName'] as String?,
        clientSessionId: json['clientSessionId'] as String?,
        startedAt:
            json['startedAt'] as String? ?? DateTime.now().toIso8601String(),
        endedAt: json['endedAt'] as String? ?? DateTime.now().toIso8601String(),
        durationMs: _asInt(json['durationMs']) ?? 0,
        openCount: _asInt(json['openCount']),
        platform: json['platform'] as String? ?? 'android',
      );

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'appName': appName,
        'clientSessionId': clientSessionId,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'durationMs': durationMs,
        'openCount': openCount,
        'platform': platform,
      };
}

class OperationEvent {
  const OperationEvent({
    required this.type,
    required this.occurredAt,
    required this.platform,
    this.clientEventId,
    this.details,
  });

  final String? clientEventId;
  final String type;
  final String occurredAt;
  final String platform;
  final Map<String, dynamic>? details;

  factory OperationEvent.fromJson(Map<String, dynamic> json) => OperationEvent(
        clientEventId:
            json['clientEventId'] as String? ?? json['id'] as String?,
        type: json['type'] as String? ?? 'app_opened',
        occurredAt:
            json['occurredAt'] as String? ?? DateTime.now().toIso8601String(),
        platform: json['platform'] as String? ?? 'android',
        details: _asStringMap(json['details']),
      );

  Map<String, dynamic> toJson() => {
        'clientEventId': clientEventId,
        'type': type,
        'occurredAt': occurredAt,
        'platform': platform,
        'details': details,
      };
}

class TelemetryBatch {
  const TelemetryBatch({
    this.deviceSnapshot,
    this.locationSnapshot,
    this.appUsageSessions = const [],
    this.dailyReport,
    this.events = const [],
  });

  final DeviceSnapshot? deviceSnapshot;
  final DeviceLocation? locationSnapshot;
  final List<AppUsageSession> appUsageSessions;
  final DailyUsageReport? dailyReport;
  final List<OperationEvent> events;

  Map<String, dynamic> toJson() => {
        'deviceSnapshot': deviceSnapshot?.toJson(),
        'locationSnapshot': locationSnapshot?.toJson(),
        'appUsageSessions':
            appUsageSessions.map((item) => item.toJson()).toList(),
        'dailyReport': dailyReport?.toJson(),
        'events': events.map((item) => item.toJson()).toList(),
      };
}

class PartnerOverview {
  const PartnerOverview({
    required this.partner,
    this.latestSnapshot,
    this.latestLocation,
    this.dailyReport,
    this.latestEvents = const [],
  });

  final PublicUser partner;
  final DeviceSnapshot? latestSnapshot;
  final DeviceLocation? latestLocation;
  final DailyUsageReport? dailyReport;
  final List<OperationEvent> latestEvents;

  factory PartnerOverview.fromJson(Map<String, dynamic> json) =>
      PartnerOverview(
        partner: PublicUser.fromJson(json['partner'] as Map<String, dynamic>),
        latestSnapshot: json['latestSnapshot'] == null
            ? null
            : DeviceSnapshot.fromJson(
                json['latestSnapshot'] as Map<String, dynamic>),
        latestLocation: json['latestLocation'] == null
            ? null
            : DeviceLocation.fromJson(
                json['latestLocation'] as Map<String, dynamic>),
        dailyReport: json['dailyReport'] == null
            ? null
            : DailyUsageReport.fromJson(
                json['dailyReport'] as Map<String, dynamic>),
        latestEvents: (json['latestEvents'] as List<dynamic>? ?? const [])
            .map(
                (item) => OperationEvent.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value == null) return null;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return null;
    }
  }
  return null;
}
