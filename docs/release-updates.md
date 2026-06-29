# Android 更新发布流程

客户端不是系统级静默推送，而是启动后检查 `app-update`。发布新版时需要把 APK 放到 HTTPS 地址，并登记到 `mutual_watch.app_releases`。

## 一次性线上准备

1. 应用 Supabase migrations，包含 `202606290005_app_release_storage_bucket.sql`，它会创建公开下载 bucket：`app-releases`。
2. 重新部署 `supabase/functions/app-update`。
3. 生成一个本机发布 token，并把 token 的 SHA-256 hash 写入 `mutual_watch.app_release_admin_tokens`。当前仓库根目录的 `.env.release.local` 已用于保存本机 token；该文件被 `.gitignore` 忽略。

## 本地发布新版

在本地 PowerShell 里设置这些变量，不要写入仓库：

```powershell
$env:SUPABASE_URL="https://uovwpzpfdweacfftqptj.supabase.co"
$env:AMAP_ANDROID_KEY="你的高德 Android Key"
```

发布一个新版：

```powershell
Set-Location "D:\codex\monitor"

.\scripts\publish_android_update.ps1 `
  -VersionCode 2 `
  -VersionName "0.2.0" `
  -ReleaseNotes "新增实时地图定位、后台位置更新、应用名称显示优化。"
```

脚本会执行：

- `flutter build apk --release`
- 注入 `API_BASE_URL`、`APP_UPDATE_URL`、`APP_VERSION_CODE`、`APP_VERSION_NAME`、`AMAP_ANDROID_KEY`
- 通过 `app-update` 发布接口上传 APK 到 Supabase Storage：`app-releases/android/...apk`
- 调用 `app-update` 的 POST 管理接口写入 release 记录
- 用旧版本号请求一次更新检查作为验证

如果 APK 已经有公开 HTTPS 地址，可以跳过上传：

```powershell
.\scripts\publish_android_update.ps1 `
  -VersionCode 2 `
  -VersionName "0.2.0" `
  -SkipBuild `
  -ApkPath "D:\codex\monitor\mobile\build\app\outputs\flutter-apk\app-release.apk" `
  -ApkUrl "https://example.com/mutual-watch-0.2.0.apk" `
  -ReleaseNotes "更新说明"
```

## 验证

```powershell
curl.exe -s "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update?platform=android&currentVersionCode=1"
```

如果最新发布版本号大于 `currentVersionCode`，应返回 `updateAvailable: true`。旧版 App 下次启动或手动检查更新时会弹出下载提示；Android 安装 APK 仍需要用户在系统安装界面确认。
