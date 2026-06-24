# Mutual Watch 移动端

这是双端手机状态共享 App 的 Flutter 客户端。

## 当前状态

- Android debug APK 已经可以从 `D:\codex\monitor_mobile_build` 构建成功。
- iOS 工程已经存在，但 iOS 构建/真机测试需要 Mac 或云端 macOS CI。
- Android 端包含完整 MVP 采集流程。
- iOS 端是轻量版，因为 iOS 公开 API 不开放详细 App 使用记录、通话状态、隐藏监控、系统级流量明细等能力。

## Android 命令

```powershell
Set-Location "D:\codex\monitor_mobile_build"

$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
$env:JAVA_HOME="C:\Program Files\Java\jdk-21.0.10"
$env:Path="$env:JAVA_HOME\bin;$env:Path"

flutter pub get
flutter build apk --debug --dart-define=API_BASE_URL=http://172.18.24.31:3000
flutter devices
flutter install -d 23078KRD5C
```

如果提示找不到 `adb`：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r "D:\codex\monitor_mobile_build\build\app\outputs\flutter-apk\app-debug.apk"
```

## iOS 在 Mac 上的命令

```bash
cd /path/to/mobile
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
flutter run --dart-define=API_BASE_URL=http://172.18.24.31:3000
```

如果要真机签名测试：

```bash
open ios/Runner.xcworkspace
```

然后在 Xcode 里选择 Apple Team，并设置唯一的 bundle id。

## 注意事项

- PowerShell 里用 `Set-Location`，不要用 `cd /d`。
- 如果电脑局域网 IP 变了，要同步修改 `API_BASE_URL`。
- iOS 本地 HTTP 测试已经在 `ios/Runner/Info.plist` 里放行。
