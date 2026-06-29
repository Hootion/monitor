# Mutual Watch

状态记录更新时间：2026-06-29。

Mutual Watch 是一个双方明确同意后使用的情侣/家人手机状态共享 App MVP。它不是隐藏监控工具，不做远程控制，也不采集短信、联系人、通话录音、截图、键盘输入、账号密码或私密内容。

## 当前状态

- Android 已可通过公网 HTTPS 后端使用，不再依赖电脑局域网、本机 NestJS 后端或 `adb reverse`。
- 线上后端使用 Supabase Free 项目 `Hootion's Project`，项目 ID：`uovwpzpfdweacfftqptj`。
- 主业务 API：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api`
- App 更新检查 API：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update`
- 当前 APK：`D:\codex\monitor\mobile\build\app\outputs\flutter-apk\app-debug.apk`
- 已覆盖安装到真机 `TOEIYXVCOZ8L559D` 和 MuMu 模拟器 `127.0.0.1:7555`。

## 项目结构

- `mobile/`：Flutter 客户端，Android 为当前主要可用端。
- `supabase/`：线上 Supabase schema migration 和 Edge Functions。
- `backend/`：旧 NestJS 本地后端，仅保留为本地参考，不再作为手机日常使用后端。
- `infra/`：早期本地基础设施草稿，当前线上方案不依赖它。

## 线上后端

Supabase 侧已创建私有业务 schema `mutual_watch`，包含用户、refresh tokens、配对邀请码、配对关系、同意日志、设备快照、位置快照、应用使用、日报、事件、App 发布版本等表。

已部署 Edge Functions：

- `api`：保留 App 使用的 REST 路由，包括 `/auth/*`、`/pairing/*`、`/telemetry/batch`、`/partner/*`、`/sharing/pause`、`/account/*`。
- `app-update`：读取 `mutual_watch.app_releases`，给 Android 返回是否有新版 APK。

后端要点：

- `api` 使用自定义鉴权，`verify_jwt=false`；公开路由只限注册、登录、刷新、健康检查。
- 密码哈希使用 WebCrypto PBKDF2-SHA256。
- Access token 15 分钟，refresh token 30 天；刷新时轮换并删除旧 refresh token。
- 明细 telemetry 保留 30 天，日报保留 180 天，控制免费数据库占用。
- Socket.IO 实时推送已取消；App 通过打开、手动刷新和 5 分钟定时同步保持更新。

## 移动端

- 默认 `API_BASE_URL` 已指向线上 Supabase `api` 函数。
- 已移除 `socket_io_client` 依赖和连接逻辑。
- App 支持自动 refresh token，401 时能刷新并重试；缺少 token 时回到登录页。
- Android 原生桥接支持设备状态、使用情况、最近位置、事件、打开系统设置、打开 APK 下载链接。
- 事件 `details` 现在兼容 Map 和 JSON 字符串，避免 `type 'String' is not a subtype of type 'Map<dynamic, dynamic>'` 类型转换错误。

## 今日完成

2026-06-29 完成事项：

- 迁移到 Supabase Postgres + Edge Functions 公网后端，手机不再需要本机局域网后端。
- 创建并应用迁移：
  - `supabase/migrations/202606290001_mutual_watch_edge_backend.sql`
  - `supabase/migrations/202606290002_mutual_watch_advisor_cleanup.sql`
  - `supabase/migrations/202606290003_app_update_releases.sql`
- 部署 `api` Edge Function，并完成注册、登录、刷新、配对、上传 telemetry、查看对方总览、暂停共享、删除数据的线上 HTTP 验证。
- 部署 `app-update` Edge Function，完成临时新版记录验证；测试记录已删除，当前不会弹测试更新。
- 手机端接入线上 API、取消 Socket.IO、保留 5 分钟同步。
- 增加 App 内更新提示：发现更高 `version_code` 后弹窗，点击后打开 APK 下载链接；Android 仍由系统要求用户确认安装。
- 修复 `OperationEvent.details` 字符串 JSON 导致的 Map 类型转换错误。
- 重新构建 APK，并覆盖安装到真机和 MuMu 模拟器。
- Supabase security/performance advisors 均无提醒。
- `flutter analyze` 通过。
- `flutter test` 38/38 通过。
- `flutter build apk --debug` 通过。

## 构建 Android APK

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

## 安装到设备

ADB 完整路径：

```text
C:\Users\Hootion\AppData\Local\Android\Sdk\platform-tools\adb.exe
```

查看设备：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
```

真机安装：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s TOEIYXVCOZ8L559D install -r -d "D:\codex\monitor\mobile\build\app\outputs\flutter-apk\app-debug.apk"
```

MuMu 模拟器连接和安装：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" connect 127.0.0.1:7555
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s 127.0.0.1:7555 install -r -d "D:\codex\monitor\mobile\build\app\outputs\flutter-apk\app-debug.apk"
```

启动 App：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s TOEIYXVCOZ8L559D shell am start -n com.mutualwatch.mutual_watch/com.mutualwatch.app.MainActivity
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s 127.0.0.1:7555 shell am start -n com.mutualwatch.mutual_watch/com.mutualwatch.app.MainActivity
```

## 发布下一个 APK 更新

后续发新版时需要做三件事：

1. 在 `mobile/pubspec.yaml` 提升版本号，例如从 `0.1.0+1` 改到 `0.2.0+2`。
2. 构建新版 APK，并把 APK 放到一个公网 HTTPS 下载地址。
3. 向 `mutual_watch.app_releases` 插入更高 `version_code` 的发布记录。

示例 SQL：

```sql
insert into mutual_watch.app_releases (
  platform,
  version_code,
  version_name,
  apk_url,
  release_notes,
  required,
  published_at
) values (
  'android',
  2,
  '0.2.0',
  'https://example.com/mutual-watch-0.2.0.apk',
  '更新说明写在这里。',
  false,
  now()
);
```

旧版 App 打开后会请求 `app-update`，如果发现 `version_code` 更高，就提示下载更新。

## 常用验证

```powershell
Set-Location "D:\codex\monitor\mobile"
flutter analyze
flutter test
```

检查线上更新接口：

```powershell
curl.exe -s "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=1"
```

当前没有正式新版记录时应返回：

```json
{"updateAvailable":false}
```

## iOS 说明

Windows 不能直接编译、签名、安装 iOS App。iOS 真机测试需要 Mac、远程 Mac 或云端 macOS CI。并且 iOS 公开 API 不允许获取详细 App 使用记录、通话状态、隐藏后台监控、系统级流量明细等能力；iOS 端应保持轻量版。
