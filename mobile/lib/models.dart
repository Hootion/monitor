class PublicUser {
  const PublicUser({
    required this.id,
    required this.displayName,
    required this.sharingPaused,
    this.phone,
    this.createdAt,
  });

  final String id;
  final String displayName;
  final bool sharingPaused;
  final String? phone;
  final String? createdAt;

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '未命名',
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

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.platform,
    required this.capturedAt,
    this.wifiBytesToday,
    this.mobileBytesToday,
    this.networkSpeedKbps,
    this.networkType,
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
        capturedAt: json['capturedAt'] as String? ?? DateTime.now().toIso8601String(),
        wifiBytesToday: _asInt(json['wifiBytesToday']),
        mobileBytesToday: _asInt(json['mobileBytesToday']),
        networkSpeedKbps: _asInt(json['networkSpeedKbps']),
        networkType: json['networkType'] as String?,
        bluetoothState: json['bluetoothState'] as String?,
        volumePercent: _asInt(json['volumePercent']),
        batteryPercent: _asInt(json['batteryPercent']),
        batteryCharging: json['batteryCharging'] as bool?,
        model: json['model'] as String?,
        osVersion: json['osVersion'] as String?,
        storageUsedBytes: _asInt(json['storageUsedBytes']),
        storageTotalBytes: _asInt(json['storageTotalBytes']),
        unsupported: (json['unsupported'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'capturedAt': capturedAt,
        'wifiBytesToday': wifiBytesToday,
        'mobileBytesToday': mobileBytesToday,
        'networkSpeedKbps': networkSpeedKbps,
        'networkType': networkType,
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

  factory DailyUsageReport.fromJson(Map<String, dynamic> json) => DailyUsageReport(
        date: json['date'] as String? ?? DateTime.now().toIso8601String().substring(0, 10),
        platform: json['platform'] as String? ?? 'android',
        screenTimeMs: _asInt(json['screenTimeMs']) ?? 0,
        pickupCount: _asInt(json['pickupCount']) ?? 0,
        longestContinuousMs: _asInt(json['longestContinuousMs']) ?? 0,
        firstUseAt: json['firstUseAt'] as String?,
        unsupported: (json['unsupported'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
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

class AppUsageSession {
  const AppUsageSession({
    required this.packageName,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.platform,
    this.appName,
    this.openCount,
  });

  final String packageName;
  final String? appName;
  final String startedAt;
  final String endedAt;
  final int durationMs;
  final int? openCount;
  final String platform;

  factory AppUsageSession.fromJson(Map<String, dynamic> json) => AppUsageSession(
        packageName: json['packageName'] as String? ?? 'unknown',
        appName: json['appName'] as String?,
        startedAt: json['startedAt'] as String? ?? DateTime.now().toIso8601String(),
        endedAt: json['endedAt'] as String? ?? DateTime.now().toIso8601String(),
        durationMs: _asInt(json['durationMs']) ?? 0,
        openCount: _asInt(json['openCount']),
        platform: json['platform'] as String? ?? 'android',
      );

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'appName': appName,
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
        clientEventId: json['clientEventId'] as String? ?? json['id'] as String?,
        type: json['type'] as String? ?? 'app_opened',
        occurredAt: json['occurredAt'] as String? ?? DateTime.now().toIso8601String(),
        platform: json['platform'] as String? ?? 'android',
        details: json['details'] == null ? null : Map<String, dynamic>.from(json['details'] as Map),
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
    this.appUsageSessions = const [],
    this.dailyReport,
    this.events = const [],
  });

  final DeviceSnapshot? deviceSnapshot;
  final List<AppUsageSession> appUsageSessions;
  final DailyUsageReport? dailyReport;
  final List<OperationEvent> events;

  Map<String, dynamic> toJson() => {
        'deviceSnapshot': deviceSnapshot?.toJson(),
        'appUsageSessions': appUsageSessions.map((item) => item.toJson()).toList(),
        'dailyReport': dailyReport?.toJson(),
        'events': events.map((item) => item.toJson()).toList(),
      };
}

class PartnerOverview {
  const PartnerOverview({
    required this.partner,
    this.latestSnapshot,
    this.dailyReport,
    this.latestEvents = const [],
  });

  final PublicUser partner;
  final DeviceSnapshot? latestSnapshot;
  final DailyUsageReport? dailyReport;
  final List<OperationEvent> latestEvents;

  factory PartnerOverview.fromJson(Map<String, dynamic> json) => PartnerOverview(
        partner: PublicUser.fromJson(json['partner'] as Map<String, dynamic>),
        latestSnapshot: json['latestSnapshot'] == null
            ? null
            : DeviceSnapshot.fromJson(json['latestSnapshot'] as Map<String, dynamic>),
        dailyReport: json['dailyReport'] == null
            ? null
            : DailyUsageReport.fromJson(json['dailyReport'] as Map<String, dynamic>),
        latestEvents: (json['latestEvents'] as List<dynamic>? ?? const [])
            .map((item) => OperationEvent.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}
