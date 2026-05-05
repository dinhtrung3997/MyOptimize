@echo off
setlocal

echo Adjust some STRING or WORD of registry 
call:adjustRegistry

rem Hack to check if run by Admin [https://stackoverflow.com/a/16285248].
net session >nul 2>&1 || (echo This script requires Admin.&goto :eof)

rem Yes, this 'HKCU' key needs Admin!
set "key=HKCU\Software\Policies\Microsoft\Windows\DataCollection"
reg delete "%key%"                       /f /va
echo Add registry value to stop telemetry 
set "key=HKLM\Software\Policies\Microsoft\Windows\DataCollection"
reg add "%key%"\AllowDesktopAnalyticsProcessing             /f /v Value /t REG_DWORD /d 0
reg add "%key%"\LimitEnhancedDiagnosticDataWindowsAnalytics /f /v Value /t REG_DWORD /d 1
reg add "%key%"\AllowTelemetry                              /f /v Value /t REG_DWORD /d 0
reg add "%key%"\AllowDeviceNameInTelemetry                  /f /v Value /t REG_DWORD /d 0
reg add "%key%"\DisableTelemetryOptInChangeNotification     /f /v Value /t REG_DWORD /d 0
reg add "%key%"\AllowWUfBCloudProcessing                    /f /v Value /t REG_DWORD /d 0
reg add "%key%"\AllowUpdateComplianceProcessing             /f /v Value /t REG_DWORD /d 0
reg add "%key%"\DisableTelemetryOptInSettingsUx             /f /v Value /t REG_DWORD /d 0

echo.
rem Set timezone to SE Asia Standard Time (GMT+7)
tzutil /s "SE Asia Standard Time"
rem Sync time now
net start w32time
w32tm /resync
echo.

echo Disable Telemetry Service and set manual for Windows Search
sc stop diagtrack
sc config diagtrack start=disabled
sc config WSearch start=demand

echo Optimize SSD disk
defrag C: /O

echo Unlock bitlocker for C (if exist)
manage-bde -unlock c:
echo Off bitlocker for C
manage-bde -off c:
echo Unlock bitlocker for D (if exist)
manage-bde -unlock d:
echo Off bitlocker for D
manage-bde -off d:

echo Reduce CPU usage by WD
powershell.exe -Command "Set-MpPreference -ScanAvgCPULoadFactor 30"

echo Disable BingSearch Taskbar
powershell.exe -Command "Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type DWord"

echo Remove some apps
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.BingNews | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers MSTeams | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.BingWeather | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.WindowsFeedbackHub | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.WindowsMaps | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.XboxSpeechToTextOverlay | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.SkypeApp | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.Microsoft3DViewer | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.MixedReality.Portal | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.People | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.Getstarted | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.BingSearch | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.OutlookForWindows | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Microsoft.GetHelp | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers MicrosoftCorporationII.MicrosoftFamily | Remove-AppxPackage"
powershell.exe -Command "Get-AppxPackage -AllUsers Clipchamp.Clipchamp | Remove-AppxPackage"

echo.
echo HPET optimization
bcdedit /set useplatformtick yes
bcdedit /set disabledynamictick yes
bcdedit /deletevalue useplatformclock

echo Installing Altsnap
powershell.exe -Command "winget install --accept-package-agreements -e --id AltSnap.AltSnap"
rem Configuring... change hotkey to Windows key and run with startup
IF EXIST "%USERPROFILE%\AppData\Roaming\AltSnap" (
	robocopy "%~dp0." "%USERPROFILE%\AppData\Roaming\AltSnap" "AltSnap.ini" /E /Z /ZB /IS /R:5 /W:5
	rem Add to startup
	reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /f /v "AltSnap" /t REG_SZ /d "%USERPROFILE%\AppData\Roaming\AltSnap\AltSnap.exe"
)

echo.
echo Installing OpenHashTab
powershell.exe -Command "winget install --accept-package-agreements -e --id namazso.OpenHashTab"
echo.
echo Installing BCUninstaller
powershell.exe -Command "winget install --accept-package-agreements -h -e --id Klocman.BulkCrapUninstaller"
echo.
echo Installing 7zip
powershell.exe -Command "winget install --accept-package-agreements -e --id 7zip.7zip"
echo.
echo Installing Java JRE 8
powershell.exe -Command "winget install --accept-package-agreements -e --id Oracle.JavaRuntimeEnvironment"
echo.
echo Installing VLC
powershell.exe -Command "winget install --accept-package-agreements -e --id VideoLAN.VLC"
echo.

echo Enabling DirectPlay
dism.exe /online /enable-feature /featurename:DirectPlay /all
echo Enabling .NET Framework 3.5...
rem dism.exe /online /enable-feature /featurename:NetFX3 /All
dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /Source:%~dp0\sxs
echo Done!

endlocal

:adjustRegistry
rem Get OS Name from systeminfo
echo Checking OS Version first
for /f "tokens=1* delims=:" %%A in ('systeminfo ^| findstr /B /C:"OS Name" 2^>nul') do set "OSName=%%B"

rem Using w11.reg for windows 11, w10.reg for windows 10
echo %OSName% | findstr /I /C:"Windows 11" >nul && (
  echo Applying w11.reg...
  reg import "%~dp0\w11.reg"
  echo Applied!
) || (
  echo %OSName% | findstr /I /C:"Windows 10" >nul && (
    echo Applying w10.reg...
    reg import "%~dp0\w10.reg"
    echo Applied!
  ) || (
    echo OS not recognized as Windows 10 or Windows 11.
  )
)
goto :eof