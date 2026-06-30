# Android 更新发布流程

状态记录更新时间：2026-06-30。

客户端不是系统级静默推送，而是请求 `app-update` 接口检查新版本。Android 安装 APK 仍需要用户在系统安装界面确认。

## 当前线上版本

- 版本名：`0.2.7`
- 版本码：`2010`
- APK：`https://uovwpzpfdweacfftqptj.supabase.co/storage/v1/object/public/app-releases/android/mutual-watch-0.2.7-2010.apk`
- 更新接口：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update`

从 `0.2.5` 开始，App 会在启动和回到前台时检查更新，并且检查更新不要求用户已经登录。更旧版本如果停在登录页、登录失效或网络异常，可能不会自动弹出更新框，可以直接使用 APK 链接安装。

## 一次性线上准备

这些准备已经完成，只在重新建项目或迁移环境时需要再做：

1. 应用 Supabase migrations，包含 `202606290005_app_release_storage_bucket.sql`，创建公开下载 bucket：`app-releases`。
2. 部署 `supabase/functions/app-update`。
3. 生成发布 token，将 SHA-256 hash 写入 `mutual_watch.app_release_admin_tokens`。
4. 在本机 `.env.release.local` 保存发布所需变量。该文件被 `.gitignore` 忽略，不应提交。

`.env.release.local` 至少需要：

```powershell
SUPABASE_URL=https://uovwpzpfdweacfftqptj.supabase.co
APP_UPDATE_URL=https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update
APP_RELEASE_ADMIN_TOKEN=...
AMAP_ANDROID_KEY=...
```

不要把 token 或真实 Key 写进仓库文档、提交记录或日志。

## 发布新版本

在仓库根目录运行：

```powershell
Set-Location "D:\codex\monitor"

.\scripts\publish_android_update.ps1 `
  -VersionCode 2010 `
  -VersionName "0.2.7" `
  -ReleaseNotes "真正按第四版重构情侣向首页 UI：移动端总览改为沉浸式问候页、双头像关系卡、相连状态条、首屏最新动态与横向今日概览，并保留同步、定位和使用数据能力。"
```

脚本会执行：

- `flutter build apk --release --split-per-abi`
- 注入 `API_BASE_URL`、`APP_UPDATE_URL`、`APP_VERSION_CODE`、`APP_VERSION_NAME`、`AMAP_ANDROID_KEY`
- 选择默认 `arm64-v8a` release APK
- 通过 `app-update` 发布接口上传 APK 到 Supabase Storage
- 写入 `mutual_watch.app_releases`
- 用旧版本号请求一次更新接口做验证

## 复用已构建 APK

如果 release APK 已经构建完成，可以跳过构建：

```powershell
.\scripts\publish_android_update.ps1 `
  -VersionCode 2010 `
  -VersionName "0.2.7" `
  -SkipBuild `
  -ReleaseNotes "真正按第四版重构情侣向首页 UI：移动端总览改为沉浸式问候页、双头像关系卡、相连状态条、首屏最新动态与横向今日概览，并保留同步、定位和使用数据能力。"
```

如果 APK 已经有外部 HTTPS 地址，可以同时传入 `-ApkUrl`。

## 验证

检查旧版本是否能看到新版本：

```powershell
Invoke-RestMethod -Uri "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=2009"
```

预期返回 `updateAvailable: true`，并包含：

```json
{
  "versionCode": 2010,
  "versionName": "0.2.7"
}
```

检查当前版本不会重复提示：

```powershell
Invoke-RestMethod -Uri "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=2010"
```

预期：

```json
{"updateAvailable":false}
```

检查 APK 下载：

```powershell
curl.exe -I -L "https://uovwpzpfdweacfftqptj.supabase.co/storage/v1/object/public/app-releases/android/mutual-watch-0.2.7-2010.apk"
```

预期返回 `HTTP/1.1 200 OK`，`Content-Type: application/vnd.android.package-archive`。

## 常见问题

### 设备没有弹更新框

先确认设备当前安装版本。如果是 `0.2.4` 或更旧版本，旧客户端可能只有进入主界面后才检查更新。处理方式：

1. 直接安装当前 APK：`https://uovwpzpfdweacfftqptj.supabase.co/storage/v1/object/public/app-releases/android/mutual-watch-0.2.7-2010.apk`
2. 安装到 `0.2.7` 后，后续启动和回到前台都会检查更新。

### 显示“暂时连接不上服务器”

这通常是手机网络层错误，不一定是服务器故障。可能原因包括 DNS 解析失败、连接超时、网络不可达、VPN/私有 DNS/运营商网络对 Supabase 或 Cloudflare 访问不稳定。

排查顺序：

1. 用浏览器打开 API 健康检查地址：`https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api/health`
2. 切换 Wi-Fi/蜂窝网络。
3. 关闭或更换 VPN、私有 DNS、代理。
4. 直接打开 APK 下载链接确认网络能访问 Supabase Storage。
