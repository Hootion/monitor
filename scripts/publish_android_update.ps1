#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int] $VersionCode,

    [Parameter(Mandatory = $true)]
    [string] $VersionName,

    [string] $ReleaseNotes = "",
    [string] $ReleaseNotesFile = "",
    [string] $Abi = "arm64-v8a",
    [switch] $Required,
    [switch] $DebugBuild,
    [switch] $SkipBuild,

    [string] $ApiBaseUrl = $env:API_BASE_URL,
    [string] $AppUpdateUrl = $env:APP_UPDATE_URL,
    [string] $AmapAndroidKey = $env:AMAP_ANDROID_KEY,

    [string] $SupabaseUrl = $env:SUPABASE_URL,
    [string] $SupabaseServiceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY,
    [string] $ReleaseBucket = $env:SUPABASE_RELEASE_BUCKET,
    [string] $ReleaseToken = $env:APP_RELEASE_ADMIN_TOKEN,

    [string] $ApkPath = "",
    [string] $ApkUrl = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Join-Url {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Base,
        [Parameter(Mandatory = $true)]
        [string] $Path
    )
    return $Base.TrimEnd("/") + "/" + $Path.TrimStart("/")
}

function Get-SupabaseUrlFromFunctionUrl {
    param([string] $FunctionUrl)
    if ($FunctionUrl -match "^(https://[^/]+)/functions/v1/") {
        return $Matches[1]
    }
    return ""
}

function New-UpdateCheckUri {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BaseUrl,
        [Parameter(Mandatory = $true)]
        [int] $CurrentVersionCode
    )
    $builder = [System.UriBuilder]::new($BaseUrl)
    $builder.Query = "platform=android&currentVersionCode=$CurrentVersionCode"
    return $builder.Uri.AbsoluteUri
}

function Invoke-Flutter {
    param([string[]] $Arguments)
    $displayArguments = $Arguments | ForEach-Object {
        if ($_.StartsWith("--dart-define=AMAP_ANDROID_KEY=")) {
            "--dart-define=AMAP_ANDROID_KEY=[redacted]"
        } else {
            $_
        }
    }
    Write-Host "flutter $($displayArguments -join ' ')"
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter command failed with exit code $LASTEXITCODE."
    }
}

function Require-Value {
    param(
        [string] $Name,
        [string] $Value,
        [string] $Hint
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name is required. $Hint"
    }
}

function Import-EnvFile {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
            return
        }
        $separator = $line.IndexOf("=")
        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($key -and -not [Environment]::GetEnvironmentVariable($key, "Process")) {
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

function Publish-ReleaseWithFunctionUpload {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Url,
        [Parameter(Mandatory = $true)]
        [string] $Token,
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $true)]
        [int] $Code,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Notes,
        [Parameter(Mandatory = $true)]
        [bool] $IsRequired
    )

    $curlArgs = @(
        "-sS",
        "-X", "POST",
        $Url,
        "-H", "Authorization: Bearer $Token",
        "-F", "platform=android",
        "-F", "versionCode=$Code",
        "-F", "versionName=$Name",
        "-F", "releaseNotes=$Notes",
        "-F", "required=$($IsRequired.ToString().ToLowerInvariant())",
        "-F", "publishedAt=$([DateTimeOffset]::UtcNow.ToString("o"))",
        "-F", "apk=@$FilePath;type=application/vnd.android.package-archive"
    )

    Write-Host "Uploading APK through app-update function"
    $responseText = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
        throw "curl upload failed with exit code $LASTEXITCODE."
    }
    if ([string]::IsNullOrWhiteSpace($responseText)) {
        throw "Release publish returned an empty response."
    }
    return $responseText | ConvertFrom-Json
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile"
Import-EnvFile -Path (Join-Path $repoRoot ".env.release.local")

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) { $ApiBaseUrl = $env:API_BASE_URL }
if ([string]::IsNullOrWhiteSpace($AppUpdateUrl)) { $AppUpdateUrl = $env:APP_UPDATE_URL }
if ([string]::IsNullOrWhiteSpace($AmapAndroidKey)) { $AmapAndroidKey = $env:AMAP_ANDROID_KEY }
if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) { $SupabaseUrl = $env:SUPABASE_URL }
if ([string]::IsNullOrWhiteSpace($SupabaseServiceRoleKey)) { $SupabaseServiceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY }
if ([string]::IsNullOrWhiteSpace($ReleaseBucket)) { $ReleaseBucket = $env:SUPABASE_RELEASE_BUCKET }
if ([string]::IsNullOrWhiteSpace($ReleaseToken)) { $ReleaseToken = $env:APP_RELEASE_ADMIN_TOKEN }

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/api"
}
if ([string]::IsNullOrWhiteSpace($AppUpdateUrl)) {
    $AppUpdateUrl = "https://uovwpzpfdweacfftqptj.supabase.co/functions/v1/app-update"
}
if ([string]::IsNullOrWhiteSpace($SupabaseUrl)) {
    $SupabaseUrl = Get-SupabaseUrlFromFunctionUrl -FunctionUrl $AppUpdateUrl
}
if ([string]::IsNullOrWhiteSpace($ReleaseBucket)) {
    $ReleaseBucket = "app-releases"
}
if ($ReleaseNotesFile) {
    $ReleaseNotes = Get-Content -LiteralPath $ReleaseNotesFile -Raw
}
if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
    $ReleaseNotes = "Android update $VersionName ($VersionCode)."
}

if (-not $SkipBuild) {
    Push-Location $mobileDir
    try {
        $mode = if ($DebugBuild) { "debug" } else { "release" }
        $flutterArgs = @(
            "build",
            "apk",
            "--$mode",
            "--build-name=$VersionName",
            "--build-number=$VersionCode",
            "--dart-define=API_BASE_URL=$ApiBaseUrl",
            "--dart-define=APP_UPDATE_URL=$AppUpdateUrl",
            "--dart-define=APP_VERSION_CODE=$VersionCode",
            "--dart-define=APP_VERSION_NAME=$VersionName",
            "--dart-define=AMAP_ANDROID_KEY=$AmapAndroidKey"
        )
        if (-not $DebugBuild) {
            $flutterArgs += "--split-per-abi"
        }
        Invoke-Flutter -Arguments $flutterArgs
    } finally {
        Pop-Location
    }
}

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $apkFileName = if ($DebugBuild) { "app-debug.apk" } else { "app-$Abi-release.apk" }
    $ApkPath = Join-Path $mobileDir "build\app\outputs\flutter-apk\$apkFileName"
}
$resolvedApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
Require-Value -Name "APP_RELEASE_ADMIN_TOKEN" -Value $ReleaseToken -Hint "Set it in .env.release.local or in your shell."

$publishResponse = $null
if ([string]::IsNullOrWhiteSpace($ApkUrl)) {
    if (-not [string]::IsNullOrWhiteSpace($SupabaseServiceRoleKey)) {
        Require-Value -Name "SUPABASE_URL" -Value $SupabaseUrl -Hint "Set SUPABASE_URL or pass -SupabaseUrl."

        $safeVersion = ($VersionName -replace "[^A-Za-z0-9._-]", "-")
        $objectPath = "android/mutual-watch-$safeVersion-$VersionCode.apk"
        $uploadUrl = Join-Url -Base $SupabaseUrl -Path "storage/v1/object/$ReleaseBucket/$objectPath"

        Write-Host "Uploading APK to $uploadUrl"
        $headers = @{
            "apikey" = $SupabaseServiceRoleKey
            "x-upsert" = "true"
        }
        if (-not $SupabaseServiceRoleKey.StartsWith("sb_secret_")) {
            $headers["Authorization"] = "Bearer $SupabaseServiceRoleKey"
        }
        Invoke-RestMethod `
            -Method Post `
            -Uri $uploadUrl `
            -Headers $headers `
            -ContentType "application/vnd.android.package-archive" `
            -InFile $resolvedApkPath | Out-Null

        $ApkUrl = Join-Url -Base $SupabaseUrl -Path "storage/v1/object/public/$ReleaseBucket/$objectPath"
    } else {
        $publishResponse = Publish-ReleaseWithFunctionUpload `
            -Url $AppUpdateUrl `
            -Token $ReleaseToken `
            -FilePath $resolvedApkPath `
            -Code $VersionCode `
            -Name $VersionName `
            -Notes $ReleaseNotes `
            -IsRequired $Required.IsPresent
        $releaseProperty = $publishResponse.PSObject.Properties["release"]
        if ($null -eq $releaseProperty -or $null -eq $releaseProperty.Value) {
            $responseJson = $publishResponse | ConvertTo-Json -Depth 6
            throw "Release publish did not return release metadata: $responseJson"
        }
        $ApkUrl = $releaseProperty.Value.apkUrl
    }
}

if ($null -eq $publishResponse) {
    $payload = @{
        platform = "android"
        versionCode = $VersionCode
        versionName = $VersionName
        apkUrl = $ApkUrl
        releaseNotes = $ReleaseNotes
        required = $Required.IsPresent
        publishedAt = [DateTimeOffset]::UtcNow.ToString("o")
    } | ConvertTo-Json -Depth 4

    Write-Host "Publishing release metadata to $AppUpdateUrl"
    $publishResponse = Invoke-RestMethod `
        -Method Post `
        -Uri $AppUpdateUrl `
        -Headers @{
            "Authorization" = "Bearer $ReleaseToken"
            "Content-Type" = "application/json"
        } `
        -Body $payload
}

$probeVersion = [Math]::Max(0, $VersionCode - 1)
$checkUrl = New-UpdateCheckUri -BaseUrl $AppUpdateUrl -CurrentVersionCode $probeVersion
$checkResponse = Invoke-RestMethod -Method Get -Uri $checkUrl
if ($checkResponse.updateAvailable -ne $true) {
    Write-Warning "Release was published, but update check did not report updateAvailable=true for currentVersionCode=$probeVersion."
}

Write-Host ""
Write-Host "Published Android update:"
Write-Host "  version: $VersionName ($VersionCode)"
Write-Host "  apkUrl:  $ApkUrl"
Write-Host "  check:   $checkUrl"
$publishResponse | ConvertTo-Json -Depth 6
