@echo off
setlocal EnableExtensions
set "BATFILE=%~f0"

rem ============================================================
rem  0. Require Administrator, and make sure we run as the signed-in user
rem ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Please right-click this file and choose "Run as administrator".
    pause
    exit /b 1
)

rem  Per-user checks (Microsoft Store apps, HKCU, %APPDATA%, %LOCALAPPDATA%, Desktop) always refer
rem  to the account running this script. If an admin account was used to elevate, that is NOT
rem  the account of the person who is signed in, so warn before touching anything.
call :CheckSameUser
if errorlevel 1 (
    echo.
    echo [WARN] This script runs as a different account than the one signed in to Windows.
    echo        Store apps, HKCU, AppData and Desktop shortcuts would be checked and changed
    echo        for the WRONG account. Best fix: run it from the signed-in account
    echo        by right-clicking the file and choosing Run as administrator.
    choice /c YN /n /m "Continue anyway? [Y/N] "
    if errorlevel 2 exit /b 1
)

echo Installing some essential apps...
echo.

rem ============================================================
rem  1. Chocolatey - install only if missing, and call it by full path
rem     (the PATH of this cmd window is NOT refreshed after installing)
rem ============================================================
set "CHOCO=%ALLUSERSPROFILE%\chocolatey\bin\choco.exe"
set "CHOCO_LIB=%ALLUSERSPROFILE%\chocolatey\lib"
if not exist "%CHOCO%" (
    echo Installing Chocolatey...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
)
if not exist "%CHOCO%" (
    echo [ERROR] Chocolatey installation failed. Check your network and try again.
    pause
    exit /b 1
)
echo.

rem ============================================================
rem  2. AltSnap (hotkey = Windows key, run at startup)
rem ============================================================
call :ChocoInstall altsnap "" "%APPDATA%\AltSnap\AltSnap.exe"

set "ALTSNAP_DIR=%APPDATA%\AltSnap"
if not exist "%ALTSNAP_DIR%" mkdir "%ALTSNAP_DIR%"
if exist "%~dp0AltSnap.ini" (
    copy /y "%~dp0AltSnap.ini" "%ALTSNAP_DIR%\AltSnap.ini" >nul
) else (
    echo [WARN] AltSnap.ini not found next to this script, skipping config.
)
if exist "%ALTSNAP_DIR%\AltSnap.exe" (
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /f /v "AltSnap" /t REG_SZ /d "\"%ALTSNAP_DIR%\AltSnap.exe\"" >nul
) else (
    echo [WARN] AltSnap.exe not found in %ALTSNAP_DIR%, startup entry not added.
)
echo.

rem ============================================================
rem  3. Twinkle Tray - only when the PC has no built-in brightness control
rem     (WmiMonitorBrightness exists on laptops / internal panels)
rem ============================================================
powershell -NoProfile -Command "if (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if %errorlevel% neq 0 (
    echo No built-in brightness control detected.
    call :ChocoInstall twinkle-tray "Twinkle Tray" "%LOCALAPPDATA%\Programs\twinkle-tray\Twinkle Tray.exe" "38002AlexanderFrangos.TwinkleTray"

    set "TT_EXE="
    for %%P in ("%LOCALAPPDATA%\Programs\twinkle-tray\Twinkle Tray.exe" "%ProgramFiles%\twinkle-tray\Twinkle Tray.exe") do (
        if exist %%P set "TT_EXE=%%~P"
    )
    if defined TT_EXE (
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /f /v "electron.app.Twinkle Tray" /t REG_SZ /d "\"%TT_EXE%\"" >nul
    ) else (
        echo [INFO] Twinkle Tray.exe not found in the usual folders ^(Microsoft Store version?^), startup entry not added.
    )
) else (
    echo Built-in brightness control found. Skipping Twinkle Tray.
)
echo.

rem ============================================================
rem  4. Small tools
rem ============================================================
call :ChocoInstall openhashtab "OpenHashTab"
echo.

call :ChocoInstall bulk-crap-uninstaller "Bulk Crap Uninstaller"
echo.

rem ============================================================
rem  5. Java JRE 8 (add Python etc. here if you want)
rem ============================================================
call :ChocoInstall jre8 "Java 8"

rem Disable Java auto-update notifications, in both 64-bit and 32-bit registry views
for %%V in (64 32) do (
    reg add "HKLM\SOFTWARE\JavaSoft\Java Update\Policy" /v EnableJavaUpdate /t REG_DWORD /d 0 /f /reg:%%V >nul 2>&1
    reg add "HKLM\SOFTWARE\JavaSoft\Java Update\Policy" /v EnableAutoUpdateCheck /t REG_DWORD /d 0 /f /reg:%%V >nul 2>&1
    reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v SunJavaUpdateSched /f /reg:%%V >nul 2>&1
)
echo.

rem ============================================================
rem  6. VLC, and remove the pre-installed Movies & TV app
rem     (Windows 11's "Media Player" is Microsoft.ZuneMusic - add it below if wanted)
rem ============================================================
call :ChocoInstall vlc "VLC media player" "%ProgramFiles%\VideoLAN\VLC\vlc.exe"

powershell -NoProfile -Command "Get-AppxPackage -AllUsers *Microsoft.ZuneVideo* | Remove-AppxPackage -AllUsers"
powershell -NoProfile -Command "Get-AppxPackage -AllUsers *Microsoft.ZuneMusic* | Remove-AppxPackage -AllUsers"
echo.

rem ============================================================
rem  7. Visual C++ Redistributables (TechPowerUp All-in-One pack)
rem     Pack folder sits next to the MyOptimize folder (one level up).
rem     Skipped when :CheckVCRedist reports nothing is missing.
rem ============================================================
call :CheckVCRedist
if %errorlevel% equ 0 echo All C++ runtimes are already installed. Skipping.& goto :vc_done
echo Installing missing C++ runtimes...
pushd "%~dp0..\CppRuntime_2026"
cmd /c "install_all.bat"
popd
:vc_done
echo.

rem ============================================================
rem  8. Clean up shortcuts - run AFTER all installs are finished.
rem     Covers the shared Desktop AND the current user's real Desktop
rem     (works even when Desktop is redirected to OneDrive).
rem ============================================================
set "USERDESKTOP="
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "USERDESKTOP=%%D"

for %%F in ("BCUninstaller.lnk" "VLC media player.lnk") do (
    del /f /q "%PUBLIC%\Desktop\%%~F" >nul 2>&1
    if defined USERDESKTOP del /f /q "%USERDESKTOP%\%%~F" >nul 2>&1
)

echo Done.
pause
endlocal
exit /b 0


rem ============================================================
rem  FUNCTIONS
rem ============================================================

:CheckSameUser
rem  Returns errorlevel 0 = this script runs as the signed-in user (or no explorer.exe is running),
rem  1 = it runs as another account.
rem  Built-in tools only (tasklist + findstr): no PowerShell and no whoami.
rem  "tasklist /v" shows each process owner as DOMAIN\user; /r makes "\\" match one backslash.
tasklist /fi "imagename eq explorer.exe" 2>nul | find /i "explorer.exe" >nul || exit /b 0
tasklist /v /fi "imagename eq explorer.exe" /fo list 2>nul | findstr /i /r /c:"\\%USERNAME%[ ]*$" >nul && exit /b 0
echo   Script account : %USERDOMAIN%\%USERNAME%
exit /b 1

:ChocoInstall
rem  %~1 = Chocolatey package id
rem  %~2 = (optional) text found in the app's "Apps and features" entry
rem  %~3 = (optional) full path of the app's main .exe (per-user installs live under %%LOCALAPPDATA%%)
rem  %~4 = (optional) Microsoft Store package name for the current user (wildcards allowed)
rem  The app counts as installed if ANY hint matches, however it was installed
rem  (Chocolatey, manual setup, per-user setup, Microsoft Store...). Nothing is ever reinstalled or forced.
rem    app found                          -> skip
rem    not found, Chocolatey knows it     -> warn only, change nothing
rem    not found, Chocolatey doesn't know -> install
rem  With no hints at all (%%~2 to %%~4 empty), only Chocolatey's lib folder is checked.
set "FOUND="
if not "%~3"=="" if exist "%~3" set "FOUND=1"
if not defined FOUND if not "%~2"=="" call :AppRegistered "%~2" && set "FOUND=1"
if not defined FOUND if not "%~4"=="" call :AppxInstalled "%~4" && set "FOUND=1"
if defined FOUND echo [SKIP]    %~1 is already installed.& exit /b 0
if exist "%CHOCO_LIB%\%~1\" if "%~2%~3%~4"=="" echo [SKIP]    %~1 is already installed (Chocolatey record).& exit /b 0
if exist "%CHOCO_LIB%\%~1\" echo [WARN]    %~1 is recorded in Chocolatey but the app was not found. Left untouched.& echo           To reinstall it yourself: choco install %~1 --force& exit /b 1
echo [INSTALL] %~1
"%CHOCO%" install %~1 -y --no-progress
exit /b %errorlevel%

:AppxInstalled
rem  %~1 = Microsoft Store (MSIX) package name, wildcards allowed.
rem  Store apps do NOT appear in the Uninstall registry keys, so ask Windows directly.
rem  Returns errorlevel 0 = installed for the current user, 1 = not installed.
powershell -NoProfile -Command "if (Get-AppxPackage -Name '%~1') { exit 0 } else { exit 1 }"
exit /b %errorlevel%

:AppRegistered
rem  %~1 = text to look for in the Uninstall registry entries (both views + current user).
rem  Returns errorlevel 0 = found, 1 = not found.
for %%K in ("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall") do reg query %%K /s /f "%~1" /d >nul 2>&1 && exit /b 0
exit /b 1

:CheckVCRedist
rem  Returns errorlevel = number of missing runtimes (0 = everything is installed).
rem  The PowerShell code is kept readable at the bottom of this file (lines starting with ::PS).
rem  The command below just collects those lines, strips the prefix and runs them.
powershell -NoProfile -Command "iex ((Get-Content -LiteralPath '%BATFILE%' | Where-Object { $_ -like '::PS*' } | ForEach-Object { $_ -replace '^::PS ?','' }) -join [char]10)"
exit /b %errorlevel%


rem ============================================================
rem  PowerShell code used by :CheckVCRedist (never executed by cmd)
rem  Keep this block LAST in the file; every line must start with "::PS".
rem ============================================================
::PS # Check which Visual C++ runtimes are installed. Exit code = number of missing ones.
::PS $uninstall = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
::PS              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
::PS $installed = (Get-ItemProperty $uninstall -ErrorAction SilentlyContinue).DisplayName
::PS $archs     = if ([Environment]::Is64BitOperatingSystem) { 'x86', 'x64' } else { 'x86' }
::PS $missing   = 0
::PS foreach ($arch in $archs) {
::PS     $isX64 = ($arch -eq 'x64')
::PS     # 2005 - 2013: look for the program name in "Apps & features"
::PS     foreach ($year in 2005, 2008, 2010, 2012, 2013) {
::PS         $found = $installed | Where-Object { $_ -match "C\+\+ $year" -and (($_ -match 'x64') -eq $isX64) }
::PS         if (-not $found) { $missing++ }
::PS     }
::PS     # 2015 and newer: one shared registry key (the 14.x family)
::PS     $keys = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$arch",
::PS             "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\$arch"
::PS     $ok = (Get-ItemProperty $keys -ErrorAction SilentlyContinue).Installed -contains 1
::PS     if (-not $ok) { $missing++ }
::PS }
::PS exit $missing
