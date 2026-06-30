# Mutual Watch

状态记录更新时间：2026-06-30。

Mutual Watch 是一个双方明确同意后使用的情侣/家人手机状态共享 App MVP。它不是隐藏监控工具，不做远程控制，也不采集短信、联系人、通话录音、截图、键盘输入、账号密码或私密内容。

## 当前状态

- Android 主线已连接公网 HTTPS 后端，不依赖局域网、本机 NestJS 后端或 `adb reverse`。
- 线上后端使用 Supabase 项目 `uovwpzpfdweacfftqptj`。
- 主业务 API：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api`
- App 更新检查 API：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update`
- 当前线上 Android 版本：`0.2.7 (2010)`
- 当前 APK：`https://uovwpzpfdweacfftqptj.supabase.co/storage/v1/object/public/app-releases/android/mutual-watch-0.2.7-2010.apk`

## 项目结构

- `mobile/`：Flutter 客户端，Android 是当前主要可用端。
- `supabase/`：线上 Supabase schema migrations 和 Edge Functions。
- `backend/`：旧 NestJS 本地后端，保留为本地参考和测试对照。
- `scripts/`：发布和维护脚本。
- `docs/`：发布流程和工作记录。

## 线上后端

Supabase 私有业务 schema 为 `mutual_watch`，包含用户、refresh tokens、配对邀请码、配对关系、同意日志、设备快照、位置快照、应用使用记录、日使用报告、事件、App 发布版本等表。

已部署 Edge Functions：

- `api`：App 使用的 REST 路由，包括 `/auth/*`、`/pairing/*`、`/telemetry/batch`、`/partner/*`、`/sharing/pause`、`/account/*`。
- `app-update`：读取 `mutual_watch.app_releases`，给 Android 返回是否有新版 APK，也支持发布脚本上传 APK 和写入 release 记录。

关键约定：

- `api` 使用自定义鉴权，`verify_jwt=false`；公开路由仅限注册、登录、刷新和健康检查。
- Access token 默认 1 天有效，refresh token 默认 180 天有效。
- Refresh token 不再在刷新时立即删除，避免前台 App 和 Android 前台服务同时刷新导致误退出登录。
- 应用使用数据会过滤 Mutual Watch 自身包名，并限制单次应用使用会话最大 4 小时、单日总屏幕时间最大 24 小时。

## 移动端要点

- 默认 `API_BASE_URL` 指向线上 Supabase `api` 函数。
- 默认 `APP_UPDATE_URL` 指向线上 Supabase `app-update` 函数。
- Android 原生桥接支持设备状态、应用使用情况、最近位置、事件、系统设置、APK 下载链接。
- 位置采集使用更高精度配置；前台位置上报和后台位置服务频率已提高。
- 地图支持手指缩放，并默认使用更近的缩放级别。
- 底部导航为 `总览 / 应用 / 记录 / 我的`；绑定入口在 `我的` 页，隐私和账号设置在 `我的 -> 设置`。
- 从 `0.2.5` 开始，更新检查不再依赖登录状态；启动和回到前台都会检查新版本。

## 最近发布

### 0.2.7 (2010)

- 真正按第四版重构情侣向首页 UI：移动端总览改为沉浸式问候页、双头像关系卡、相连状态条、首屏最新动态与横向今日概览。
- 验证：`currentVersionCode=2009` 返回 `0.2.7 / 2010`，`currentVersionCode=2010` 返回 `updateAvailable: false`。

### 0.2.6 (2009)

- 甜美情侣向界面更新：采用第四版视觉方案，优化暖白玫瑰主题、情侣状态头卡、底部导航、状态标签、今日概览和定位面板质感。
- 验证：`currentVersionCode=2008` 返回 `0.2.6 / 2009`，`currentVersionCode=2009` 返回 `updateAvailable: false`。

### 0.2.5 (2008)

- 修复未登录、登录失效或停留在登录页时不会检查更新的问题。
- App 启动和回到前台都会检查新版本。
- 验证：`currentVersionCode=2007` 返回 `0.2.5 / 2008`，`currentVersionCode=2008` 返回 `updateAvailable: false`。

### 0.2.4 (2007)

- 提高定位精度并支持地图手势缩放。
- 修复应用使用时长异常，过滤 Mutual Watch 自身使用记录。
- 将 `绑定` 从底部栏移入 `我的`，将设置和隐私信息放入 `我的 -> 设置`。
- 优化登录保持状态，减少刷新 token 竞态导致的误退出登录。

### 0.2.3 (2006)

- 修复实时定位地图页在部分真机上闪退的问题。
- 保留高德 SDK R8 规则，并在 x86/x64 模拟器上降级显示，避免加载不兼容 native 地图。

## 发布 Android 更新

发布脚本会构建 APK、注入 API/版本/高德 Key 参数、上传 APK 到 Supabase Storage，并写入 `app-update` release 记录。

```powershell
Set-Location "D:\codex\monitor"

.\scripts\publish_android_update.ps1 `
  -VersionCode 2010 `
  -VersionName "0.2.7" `
  -ReleaseNotes "真正按第四版重构情侣向首页 UI：移动端总览改为沉浸式问候页、双头像关系卡、相连状态条、首屏最新动态与横向今日概览，并保留同步、定位和使用数据能力。"
```

如果 APK 已经构建完成，可以加 `-SkipBuild`。

本地发布凭据保存在 `.env.release.local`，该文件被 `.gitignore` 忽略，不应提交。

## 常用验证

```powershell
Set-Location "D:\codex\monitor\mobile"
flutter analyze
flutter test
```

检查线上 API：

```powershell
Invoke-RestMethod -Uri "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api/health"
```

检查更新接口：

```powershell
Invoke-RestMethod -Uri "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=2007"
Invoke-RestMethod -Uri "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=2008"
Invoke-RestMethod -Uri "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=2009"
Invoke-RestMethod -Uri "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=2010"
```

检查 APK 下载地址：

```powershell
curl.exe -I -L "https://uovwpzpfdweacfftqptj.supabase.co/storage/v1/object/public/app-releases/android/mutual-watch-0.2.7-2010.apk"
```

## 文档

- [Android 更新发布流程](docs/release-updates.md)
- [2026-06-30 工作记录](docs/2026-06-30-worklog.md)
- [移动端说明](mobile/README.md)

## iOS 说明

Windows 不能直接编译、签名、安装 iOS App。iOS 真机测试需要 Mac、远程 Mac 或云端 macOS CI。并且 iOS 公开 API 不允许获取详细 App 使用记录、通话状态、隐藏后台监控、系统级流量明细等能力；后续 iOS 端应保持轻量版。
