import AVFoundation
import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let monitor = NWPathMonitor()
  private let monitorQueue = DispatchQueue(label: "mutual_watch_network")
  private var networkType = "unknown"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UIDevice.current.isBatteryMonitoringEnabled = true
    startNetworkMonitor()

    let controller = window?.rootViewController as? FlutterViewController
    let channel = FlutterMethodChannel(
      name: "app.mutual_watch/device",
      binaryMessenger: controller!.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "native_error", message: "App delegate unavailable", details: nil))
        return
      }
      switch call.method {
      case "hasUsageAccess":
        result(true)
      case "openUsageAccessSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        result(nil)
      case "startForegroundCollection":
        result(nil)
      case "getDeviceSnapshot":
        result(self.deviceSnapshot())
      case "getTodayUsageReport":
        result(self.todayUsageReport())
      case "getAppUsage":
        result([])
      case "getRecentEvents":
        result([])
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startNetworkMonitor() {
    monitor.pathUpdateHandler = { [weak self] path in
      if path.status != .satisfied {
        self?.networkType = "offline"
      } else if path.usesInterfaceType(.wifi) {
        self?.networkType = "wifi"
      } else if path.usesInterfaceType(.cellular) {
        self?.networkType = "cellular"
      } else if path.usesInterfaceType(.wiredEthernet) {
        self?.networkType = "ethernet"
      } else {
        self?.networkType = "unknown"
      }
    }
    monitor.start(queue: monitorQueue)
  }

  private func deviceSnapshot() -> [String: Any?] {
    let device = UIDevice.current
    let storage = storageInfo()
    let batteryPercent: Int? = device.batteryLevel >= 0 ? Int(device.batteryLevel * 100) : nil
    let volume = Int(AVAudioSession.sharedInstance().outputVolume * 100)

    return [
      "platform": "ios",
      "capturedAt": isoNow(),
      "wifiBytesToday": nil,
      "mobileBytesToday": nil,
      "networkSpeedKbps": nil,
      "networkType": networkType,
      "bluetoothState": "unsupported",
      "volumePercent": volume,
      "batteryPercent": batteryPercent,
      "batteryCharging": device.batteryState == .charging || device.batteryState == .full,
      "model": "\(device.model)",
      "osVersion": "\(device.systemName) \(device.systemVersion)",
      "storageUsedBytes": storage.used,
      "storageTotalBytes": storage.total,
      "unsupported": [
        "ios_app_usage_details_unavailable",
        "ios_call_state_unavailable",
        "ios_daily_network_traffic_unavailable",
        "ios_bluetooth_state_unavailable"
      ]
    ]
  }

  private func todayUsageReport() -> [String: Any?] {
    let date = String(isoNow().prefix(10))
    return [
      "date": date,
      "platform": "ios",
      "screenTimeMs": 0,
      "pickupCount": 0,
      "firstUseAt": nil,
      "longestContinuousMs": 0,
      "unsupported": [
        "screen_time_data_requires_family_controls_entitlement",
        "app_usage_details_unavailable_on_ios"
      ]
    ]
  }

  private func storageInfo() -> (total: Int64?, used: Int64?) {
    do {
      let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
      let total = (attrs[.systemSize] as? NSNumber)?.int64Value
      let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value
      let used = total.flatMap { totalValue in free.map { totalValue - $0 } }
      return (total, used)
    } catch {
      return (nil, nil)
    }
  }

  private func isoNow() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
  }
}

