# 双端手机状态共享 App MVP

状态记录更新时间：2026-06-23。

这是一个双方明确同意后使用的情侣/家人手机状态共享 App MVP。它不是隐藏监控工具，不做远程控制，也不采集短信、联系人、通话录音、截图、键盘输入、账号密码或私密内容。

## 项目结构

- `backend/`：NestJS 后端，包含登录、绑定、数据上传、查看对方数据、暂停共享、删除数据和 WebSocket 通知。当前 MVP 用内存存储。
- `mobile/`：Flutter 客户端，包含 Android Kotlin 原生采集桥接和 iOS Swift 原生桥接。
- `infra/`：后续接 PostgreSQL、Redis 的 Docker Compose 配置。

## 当前进度

- 后端可以构建并运行在 `3000` 端口。
- Android debug APK 已经构建成功，文件在：
  `D:\codex\monitor_mobile_build\build\app\outputs\flutter-apk\app-debug.apk`
- Gradle wrapper 下载慢/超时问题已经处理，已换成腾讯 Gradle 镜像。
- Flutter Android 引擎依赖下载问题已经处理，使用 `https://storage.flutter-io.cn`。
- Android Kotlin 流量统计编译错误已经修复。
- iOS 的 `Info.plist` 已经加了本地网络权限说明和本地 HTTP 测试放行。
- Windows 不能直接构建、签名、安装 iOS App；iOS 测试需要 Mac、远程 Mac 或云端 macOS CI。

## 后端启动

从仓库根目录执行：

```powershell
Set-Location backend
npm install
npm test
npm run build
npm run start:dev
```

如果要启动一个持续运行的本地后端：

```powershell
Set-Location backend
npm run build
node dist/main.js
```

今天 Android 调试时使用的后端地址：

```text
http://172.18.24.31:3000
```

如果明天电脑 IP 变了，用这个命令查新的局域网 IP：

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
  Select-Object InterfaceAlias,IPAddress
```

## Android 测试

PowerShell 里不要用 CMD 的 `cd /d`。

错误写法：

```powershell
cd /d D:\codex\monitor_mobile_build
```

正确写法：

```powershell
Set-Location "D:\codex\monitor_mobile_build"
```

建议每次构建前先设置这些环境变量：

```powershell
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
$env:JAVA_HOME="C:\Program Files\Java\jdk-21.0.10"
$env:Path="$env:JAVA_HOME\bin;$env:Path"
```

构建 APK：

```powershell
Set-Location "D:\codex\monitor_mobile_build"
flutter pub get
flutter build apk --debug --dart-define=API_BASE_URL=http://172.18.24.31:3000
```

安装到已连接的 Android 手机：

```powershell
Set-Location "D:\codex\monitor_mobile_build"
flutter devices
flutter install -d 23078KRD5C
```

如果提示找不到 `adb`，用完整路径安装：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r "D:\codex\monitor_mobile_build\build\app\outputs\flutter-apk\app-debug.apk"
```

## iOS 测试

Windows 不能编译、签名、安装 iOS App，这是苹果工具链限制，不是 Flutter 或项目代码的问题。

没有 Mac 的可选方案：

- 用 Codemagic、Bitrise、GitHub Actions macOS runner 云端构建 iOS。
- 租远程 Mac，然后在远程 Mac 上跑 Flutter 和 Xcode。
- 有 Apple Developer 账号后，用 TestFlight 测真机。
- 先继续做 Android 测试；iOS 本来只能做系统允许的轻量版。

在 Mac 上测试时执行：

```bash
cd /path/to/mobile
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
flutter run --dart-define=API_BASE_URL=http://172.18.24.31:3000
```

如果是真机 iPhone 测试：

```bash
open ios/Runner.xcworkspace
```

然后在 Xcode 里：

- `Signing & Capabilities` 选择你的 Apple Team。
- 如果 bundle id 冲突，把 `com.mutualwatch.mutualWatch` 改成唯一的。
- iPhone 上点“信任此电脑”。
- iOS 弹出“允许本地网络”时点允许。

重要限制：

- iOS 公开 API 不允许获取详细 App 使用记录、通话状态、系统级流量、隐藏后台监控等数据。
- iOS 端遇到系统不开放的字段，应显示“不支持”或“未授权”。

## 今天已修复的问题

- 避免从 `C:\WINDOWS\System32` 运行 Flutter。
- 关闭了当前不需要的 Flutter Web 和 Windows Desktop 下载。
- Gradle wrapper 已换成腾讯镜像：
  `https://mirrors.cloud.tencent.com/gradle/gradle-9.1.0-bin.zip`
- Android 工程已加入 Flutter Maven 镜像：
  `https://storage.flutter-io.cn/download.flutter.io`
- `flutter precache --android` 已成功跑完。
- 为了避开中文路径构建问题，使用了英文路径副本：
  `D:\codex\monitor_mobile_build`
- 修复了 Android Kotlin 流量统计类型错误。
- Android debug APK 已构建成功。
- iOS `Info.plist` 已加入本地网络测试配置。

## 明天继续清单

1. 确认后端还在 `3000` 端口运行。
2. 确认电脑当前局域网 IP，如果变了就更新 `API_BASE_URL`。
3. 安装 Android APK，测试登录、绑定、数据上传、对方概览。
4. 决定 iOS 方案：云端 macOS 构建、租远程 Mac，或先暂缓 iOS 真机测试。
5. 如果走云端 iOS 构建，再添加 CI 配置和 Apple 签名配置。
