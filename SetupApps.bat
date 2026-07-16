@echo off
setlocal

echo Installing some essential apps...
rem install chocolatey first. Winget is good but not preinstalled on Windows 10
powershell.exe -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"

echo.
echo Installing Altsnap...
choco install altsnap -yes
rem Configuring... change hotkey to Windows key and run with startup
IF EXIST "%USERPROFILE%\AppData\Roaming\AltSnap" (
	robocopy "%~dp0." "%USERPROFILE%\AppData\Roaming\AltSnap" "AltSnap.ini" /E /Z /ZB /IS /R:5 /W:5
	rem Add to startup
	reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /f /v "AltSnap" /t REG_SZ /d "%USERPROFILE%\AppData\Roaming\AltSnap\AltSnap.exe"
)

echo.
rem check brightness control feature first
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "DisableBrightnessControlOverride" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo Brightness control is not detected. Installing TwinkleTray...
    choco install twinkle-tray -yes
    IF EXIST "%USERPROFILE%\AppData\Local\Programs\twinkle-tray" (
        rem Add to startup
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /f /v "electron.app.Twinkle Tray" /t REG_SZ /d "%USERPROFILE%\AppData\Local\Programs\twinkle-tray\Twinkle Tray.exe")
    echo.
    )    

echo.
rem tool to quick checking hash file
echo Installing OpenHashTab
choco install openhashtab -yes
echo.
rem tool opensource to support uninstall app
echo Installing BCUninstaller
choco install bulk-crap-uninstaller -yes
del "%PUBLIC%\Desktop\BCUninstaller.lnk"

echo.
rem Java Environment to run some apps in future, you can add Python if you want.
echo Installing Java JRE 8
choco install jre8 -yes
rem remove all auto update notifies of Java
REG ADD "HKLM\SOFTWARE\Wow6432Node\JavaSoft\Java Update\Policy" /v EnableJavaUpdate /t REG_DWORD /d 0 /f
REG ADD "HKLM\SOFTWARE\Wow6432Node\JavaSoft\Java Update\Policy" /v EnableAutoUpdateCheck /t REG_DWORD /d 0 /f
REG DELETE "HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run" /v SunJavaUpdateSched /f

echo.
rem Player and codec, simple is VLC. Can you use K-lite, Potplayer, KMPlayer,... for alternative
echo Installing VLC
choco install vlc -yes
del "%PUBLIC%\Desktop\VLC media player.lnk"
rem So uninstall Media Player preapp
powershell.exe -Command "Get-AppxPackage -AllUsers *Microsoft.ZuneVideo* | Remove-AppxPackage -AllUsers"
echo.
