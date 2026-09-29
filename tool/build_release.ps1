# Сборка release APK вне OneDrive (OneDrive блокирует build/ и .dart_tool/) и выкладка в GitHub Releases.
#
#   .\tool\build_release.ps1                          # только собрать
#   .\tool\build_release.ps1 -Publish -Notes "- ..."  # собрать и выложить
#   .\tool\build_release.ps1 -Publish -Force -Notes "- ..."  # обязательное обновление ([force])
#
# Версия берётся из pubspec.yaml — поднимите +build перед выкладкой.

param(
    [switch]$Publish,
    [switch]$Force,
    [string]$Notes = '',
    [string]$BuildDir = 'C:\temp\stoox_employee_app_build',
    [string]$Repo = 'GriZZli1975/employee_app'
)

$ErrorActionPreference = 'Stop'

# SHA-256 сертификата, которым подписаны все выпущенные APK. Другой ключ = обновление не встанет поверх.
$ExpectedCertSha256 = '7d05b643b9298209984703ed09b849b0e36b3148153d9d9224df459b2a1c4706'

$Source = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path (Join-Path $Source 'android\key.properties'))) {
    throw "Нет android\key.properties и ключа android\keystore\*.jks — без них релиз подписать нельзя."
}

$versionLine = Select-String -Path (Join-Path $Source 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw 'Не найдена version в pubspec.yaml' }
$Version = $versionLine.Matches[0].Groups[1].Value
$VersionName = $Version.Split('+')[0]
Write-Host "Версия: $Version"

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = 'C:\flutter\bin\flutter.bat' }
if (-not (Test-Path $flutter)) { throw 'Flutter не найден (PATH или C:\flutter\bin\flutter.bat)' }

Write-Host "Копирую проект в $BuildDir ..."
New-Item -ItemType Directory -Force $BuildDir | Out-Null
# /MIR с /XD: кэши сборки не трогаем (быстрее), остальное зеркалим, включая удаление лишнего
robocopy $Source $BuildDir /MIR /NFL /NDL /NJH /NJS /NP /XD build .dart_tool .gradle .idea dist | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy завершился с кодом $LASTEXITCODE" }

Push-Location $BuildDir
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get упал' }
    & $flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk упал' }
} finally {
    Pop-Location
}

$apk = Join-Path $BuildDir 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apk)) { throw "Нет $apk" }

$buildTools = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools') -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -Last 1
if ($buildTools) {
    $certs = & (Join-Path $buildTools.FullName 'apksigner.bat') verify --print-certs $apk 2>&1 | Out-String
    if ($certs -notmatch $ExpectedCertSha256) {
        throw "APK подписан НЕ тем ключом, что прошлые релизы. Не выкладывать!`n$certs"
    }
    Write-Host 'Подпись совпадает с прошлыми релизами.'
} else {
    Write-Warning 'apksigner не найден — подпись не проверена.'
}

$distDir = Join-Path $BuildDir 'dist'
New-Item -ItemType Directory -Force $distDir | Out-Null
$named = Join-Path $distDir "stoox-employee-$VersionName.apk"
Copy-Item $apk $named -Force
Write-Host "APK: $named ($([math]::Round((Get-Item $named).Length / 1MB, 1)) МБ)"

if (-not $Publish) { return }

if (-not $env:GH_TOKEN) {
    $cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
    $token = ($cred | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''
    if (-not $token) { throw 'Нет GH_TOKEN и токена GitHub в git credential' }
    $env:GH_TOKEN = $token
}

$body = $Notes.Trim()
if ($Force) { $body = ($body + "`n`n[force]").Trim() }
if (-not $body) { $body = "Версия $VersionName" }

$tag = "v$Version"
Write-Host "Публикую $tag в $Repo ..."
gh release create $tag $named --repo $Repo --title "$VersionName" --notes $body
if ($LASTEXITCODE -ne 0) { throw 'gh release create упал' }
Write-Host "Готово: https://github.com/$Repo/releases/tag/$tag"
