# Mutual Watch 移动端

状态记录更新时间：2026-06-30。

这是 Mutual Watch 的 Flutter 客户端。当前主线是 Android APK + Supabase 公网后端。

## 当前可用状态

- Android App 已连接公网 HTTPS 后端，不依赖局域网 IP、USB 反向代理或本机 NestJS 后端。
- API 地址：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api`
- 更新检查地址：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update`
- 当前线上版本：`0.2.9 (2012)`
- 当前 APK：`https://uovwpzpfdweacfftqptj.supabase.co/storage/v1/object/public/app-releases/android/mutual-watch-0.2.9-2012.apk`

## 主要能力

- 登录、注册、自动刷新 token。
- 双方配对、解除配对、暂停共享、删除已上传数据。
- 同步设备状态、最近位置、应用使用情况、操作事件和日使用报告。
- 总览页展示对方状态、地图位置、数据健康度和使用摘要。
- 应用页聚合应用使用时长和打开次数。
- 记录页展示最近操作事件。
- 我的页包含账号状态、编辑资料、设置入口和绑定入口。
- 设置页包含隐私状态、权限与可用性、退出登录和删除数据等操作。

## 0.2.4-0.2.9 关键变化

- 0.2.9 优化实时定位和地图展示：按时间/精度选择更可靠位置，Android 坐标转换为高德地图可用坐标，并支持全屏地图查看。
- 0.2.9 Android 前台服务会定期补充设备状态快照，总览刷新会先同步本机状态再刷新对方概览。
- 0.2.8 修复应用页空状态诊断，新增编辑资料和头像上传，调整总览姓名显示和设置折叠结构。
- 0.2.7 按第四版重构总览页 UI 结构：沉浸式问候、双头像关系卡、相连状态条、首屏最新动态与横向今日概览。
- 0.2.6 奠定甜美情侣向视觉主题，采用暖白玫瑰配色、柔和状态标签和底部导航。
- 地图定位精度提高，并支持手指放大缩小。
- 过滤 Mutual Watch 自身的应用使用记录，避免出现异常超长使用时间。
- 单次应用使用会话最大按 4 小时展示，单日屏幕时间最大按 24 小时展示。
- 底部导航调整为 `总览 / 应用 / 记录 / 我的`。
- 绑定入口移入 `我的` 页，隐私和账号设置移入 `我的 -> 设置`。
- 登录保持时间延长，前台 App 和后台服务同时刷新 token 时不再误退出登录。
- 更新检查不再依赖登录状态；启动和回到前台都会检查新版。

## 构建

```powershell
Set-Location "D:\codex\monitor\mobile"

$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

flutter pub get
flutter build apk --release --split-per-abi `
  --build-name=0.2.9 `
  --build-number=2012 `
  --dart-define=API_BASE_URL=https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api `
  --dart-define=APP_UPDATE_URL=https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update `
  --dart-define=APP_VERSION_CODE=2012 `
  --dart-define=APP_VERSION_NAME=0.2.9 `
  --dart-define=AMAP_ANDROID_KEY=$env:AMAP_ANDROID_KEY
```

日常发布建议使用仓库根目录的发布脚本：

```powershell
Set-Location "D:\codex\monitor"

.\scripts\publish_android_update.ps1 `
  -VersionCode 2012 `
  -VersionName "0.2.9" `
  -ReleaseNotes "优化实时定位和地图展示，新增全屏地图查看；后台定期同步电量、网络、存储等设备状态；修正总览刷新会先同步本机状态。"
```

## 安装

查看设备：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
```

安装 arm64 release APK：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s <device-id> install -r "D:\codex\monitor\mobile\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
```

启动 App：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s <device-id> shell am start -n com.mutualwatch.mutual_watch/com.mutualwatch.app.MainActivity
```

包名：

```text
com.mutualwatch.mutual_watch
```

## App 更新机制

客户端请求：

```text
https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=2011
```

如果返回 `updateAvailable: true`，App 会弹窗提示下载。Android 安装 APK 仍需要用户在系统界面确认，不能静默安装。

从 `0.2.5` 开始：

- 未登录也会检查更新。
- 登录过期停在登录页也会检查更新。
- App 启动和回到前台都会检查更新。

## 验证

```powershell
Set-Location "D:\codex\monitor\mobile"
flutter analyze
flutter test
```

最近一次验证结果：

- `flutter analyze` 通过。
- `flutter test` 通过，47 个测试。
- `flutter build apk --release --split-per-abi` 通过。

## 网络错误说明

如果 App 显示“暂时连接不上服务器，请检查网络或 API 地址。”，含义是手机端网络层没有连上 API，不一定是服务器宕机。

可先在设备浏览器中打开：

```text
https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api/health
```

如果浏览器也打不开，优先检查 Wi-Fi/蜂窝网络、VPN、私有 DNS、代理或当前网络环境。

## 保留说明

- Android 是当前主要可用端。
- iOS 工程存在，但 Windows 不能直接编译、签名、安装 iOS App。
- iOS 公开 API 不开放详细 App 使用记录、通话状态、隐藏后台监控、系统级流量明细等能力；后续 iOS 应保持轻量版。
