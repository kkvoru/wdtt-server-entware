@echo off
setlocal enabledelayedexpansion

set "PROJECT_ROOT=%CD%"
set "ORIGINAL_REPO=https://github.com/amurcanov/proxy-turn-vk-android.git"
set "SOURCE_DIR=.source\proxy-turn-vk-android"
set "DIST_DIR=dist"

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
if not exist ".source" mkdir ".source"

echo === Sync original source ===
where git >nul 2>nul
if errorlevel 1 (
    echo FAILED: git is required to sync %ORIGINAL_REPO%
    exit /b 1
)

if exist "%SOURCE_DIR%\.git" (
    git -C "%SOURCE_DIR%" pull --ff-only
) else (
    git clone --depth 1 "%ORIGINAL_REPO%" "%SOURCE_DIR%"
)
if errorlevel 1 (
    echo FAILED: cannot sync original repository
    exit /b 1
)

if not exist "%SOURCE_DIR%\server.go" (
    echo FAILED: server.go not found in original repository
    exit /b 1
)

set CGO_ENABLED=0
set GOOS=linux

echo.
echo === Building WDTT server for Entware ===

pushd "%SOURCE_DIR%"

echo.
echo Preparing Go modules...
go mod tidy
if errorlevel 1 (
    echo FAILED: go mod tidy
    popd
    exit /b 1
)

call :build mipsle softfloat "" wdtt-server-entware-mipsel-softfloat
if errorlevel 1 exit /b 1

call :build mips softfloat "" wdtt-server-entware-mips-softfloat
if errorlevel 1 exit /b 1

call :build arm "" 7 wdtt-server-entware-armv7
if errorlevel 1 exit /b 1

call :build arm "" 5 wdtt-server-entware-armv5
if errorlevel 1 exit /b 1

call :build arm64 "" "" wdtt-server-entware-arm64
if errorlevel 1 exit /b 1

call :build 386 "" "" wdtt-server-entware-x86
if errorlevel 1 exit /b 1

call :build amd64 "" "" wdtt-server-entware-x64
if errorlevel 1 exit /b 1

popd

copy /Y "entware\install_wdtt_entware.sh" "%DIST_DIR%\install_wdtt_entware.sh" >nul

if exist "%DIST_DIR%\wdtt-server-entware-all.zip" del /F /Q "%DIST_DIR%\wdtt-server-entware-all.zip" >nul 2>nul
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; Get-ChildItem '%DIST_DIR%\wdtt-server-entware-*' -File | Where-Object { $_.Extension -ne '.zip' } | ForEach-Object { $h=Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName; '{0}  {1}' -f $h.Hash.ToLower(), $_.Name } | Set-Content -Encoding ASCII '%DIST_DIR%\SHA256SUMS.txt'"
if errorlevel 1 (
    echo FAILED: cannot generate SHA256SUMS.txt
    exit /b 1
)
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.IO.Compression; Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip='%DIST_DIR%\wdtt-server-entware-all.zip'; if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }; $archive=[System.IO.Compression.ZipFile]::Open($zip,[System.IO.Compression.ZipArchiveMode]::Create); try { $files=@(Get-ChildItem '%DIST_DIR%\wdtt-server-entware-*' -File | Where-Object { $_.Extension -ne '.zip' }) + @(Get-Item '%DIST_DIR%\SHA256SUMS.txt') + @(Get-Item '%DIST_DIR%\install_wdtt_entware.sh'); foreach ($file in $files) { $entry=$archive.CreateEntry($file.Name,[System.IO.Compression.CompressionLevel]::Optimal); $in=[System.IO.File]::Open($file.FullName,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite); try { $out=$entry.Open(); try { $in.CopyTo($out) } finally { $out.Dispose() } } finally { $in.Dispose() } } } finally { $archive.Dispose() }"
if errorlevel 1 (
    echo FAILED: cannot create %DIST_DIR%\wdtt-server-entware-all.zip
    exit /b 1
)

echo.
echo === Build complete ===
for %%F in ("%DIST_DIR%\wdtt-server-entware-*") do echo   %%~nxF [%%~zF bytes]
echo   %DIST_DIR%\install_wdtt_entware.sh
echo.
exit /b 0

:build
set "GOARCH=%~1"
set "GOMIPS=%~2"
set "GOARM=%~3"
set "OUT=%~4"
echo.
echo Building %OUT% ^(%GOOS%/%GOARCH%^)
go build -trimpath -ldflags="-s -w -buildid=" -o "%PROJECT_ROOT%\%DIST_DIR%\%OUT%" server.go
if errorlevel 1 (
    echo FAILED: %OUT%
    popd
    exit /b 1
)
echo OK: %DIST_DIR%\%OUT%
exit /b 0
