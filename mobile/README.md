# Mutual Watch 移动端

状态记录更新时间：2026-06-29。

这是 Mutual Watch 的 Flutter 客户端。当前主线是 Android APK + Supabase 公网后端。

## 当前可用状态

- Android App 已连接公网 HTTPS 后端，不再依赖局域网 IP、USB 反向代理或本机 NestJS 后端。
- API 地址：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api`
- 更新检查地址：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update`
- 当前 debug APK：`D:\codex\monitor\mobile\build\app\outputs\flutter-apk\app-debug.apk`
- 已安装设备：
  - 真机 `TOEIYXVCOZ8L559D` / `23078RKD5C`
  - MuMu 模拟器 `127.0.0.1:7555` / `CET_AL00`

## 今日完成

2026-06-29 完成事项：

- 默认 `API_BASE_URL` 改为 Supabase Edge Function。
- 移除 Socket.IO 客户端依赖和实时连接逻辑。
- 保留打开 App、手动刷新、5 分钟定时同步。
- 接入 `app-update` 更新检查；发现新版后弹窗并打开 APK 下载链接。
- Android 原生桥接新增 `openUrl`，用于打开下载链接。
- 修复事件 `details` 为 JSON 字符串时的类型转换错误。
- 新增测试覆盖 `AppUpdateInfo` 和 JSON 字符串 `OperationEvent.details`。
- `flutter analyze` 通过。
- `flutter test` 38/38 通过。
- `flutter build apk --debug` 通过。
- 新版 APK 已覆盖安装到真机和 MuMu 模拟器。

## 构建

```powershell
Set-Location "D:\codex\monitor\mobile"

$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

flutter pub get
flutter build apk --debug `
  --dart-define=API_BASE_URL=https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api `
  --dart-define=APP_UPDATE_URL=https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update `
  --dart-define=APP_VERSION_CODE=1 `
  --dart-define=APP_VERSION_NAME=0.1.0
```

## 安装

查看设备：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
```

真机覆盖安装：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s TOEIYXVCOZ8L559D install -r -d "D:\codex\monitor\mobile\build\app\outputs\flutter-apk\app-debug.apk"
```

MuMu 覆盖安装：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" connect 127.0.0.1:7555
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s 127.0.0.1:7555 install -r -d "D:\codex\monitor\mobile\build\app\outputs\flutter-apk\app-debug.apk"
```

启动：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s TOEIYXVCOZ8L559D shell am start -n com.mutualwatch.mutual_watch/com.mutualwatch.app.MainActivity
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s 127.0.0.1:7555 shell am start -n com.mutualwatch.mutual_watch/com.mutualwatch.app.MainActivity
```

包名：

```text
com.mutualwatch.mutual_watch
```

## App 更新机制

客户端会请求：

```text
https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=1
```

如果返回 `updateAvailable: true`，App 会弹窗提示下载。Android 安装 APK 仍需要用户在系统界面确认，不能静默安装。

发布新版时：

1. 提升 `pubspec.yaml` 里的版本号，例如 `0.2.0+2`。
2. 构建 APK。
3. 把 APK 上传到公网 HTTPS 地址。
4. 在 Supabase `mutual_watch.app_releases` 插入对应记录。

## 验证

```powershell
Set-Location "D:\codex\monitor\mobile"
flutter analyze
flutter test
```

检查安装是否存在：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s TOEIYXVCOZ8L559D shell pm list packages | Select-String -Pattern "com.mutualwatch.mutual_watch"
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s 127.0.0.1:7555 shell pm list packages | Select-String -Pattern "com.mutualwatch.mutual_watch"
```

检查最近是否还有类型转换错误：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s TOEIYXVCOZ8L559D logcat -d -t 300 | Select-String -Pattern "type 'String'|Map<dynamic|type cast|Unhandled Exception|FlutterError"
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s 127.0.0.1:7555 logcat -d -t 300 | Select-String -Pattern "type 'String'|Map<dynamic|type cast|Unhandled Exception|FlutterError"
```

## 保留说明

- Android 是当前主要可用端。
- iOS 工程存在，但 Windows 不能直接编译、签名、安装 iOS App。
- iOS 公开 API 不开放详细 App 使用记录、通话状态、隐藏后台监控、系统级流量明细等能力；后续 iOS 应保持轻量版。
