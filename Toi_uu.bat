@echo off
setlocal

rem Check if run by Admin [https://stackoverflow.com/a/16285248].
net session >nul 2>&1 || (echo This script requires Admin.& pause& goto :eof)

echo.
rem Enable System restore first
powershell.exe -NoProfile -Command "Enable-ComputerRestore -Drive 'C:\'"
echo Create snapshot and backup registry
rem Set disk space max usage to 5GB first
vssadmin resize shadowstorage /for=C: /on=C: /maxsize=5GB
rem Unlimited restore point before in 24 hours
set "srkey=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
reg add "%srkey%" /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f >nul
rem Create System Restore Point to make snapshot
powershell.exe -NoProfile -Command "Checkpoint-Computer -Description 'BeforeOptimize' -RestorePointType 'MODIFY_SETTINGS'"
rem Clear value key return default
reg delete "%srkey%" /v SystemRestorePointCreationFrequency /f >nul 2>&1

echo.
echo Adjust some STRING or WORD of registry
call :adjustRegistry

echo.
call :lapOrDesk

echo.
echo Add registry values to stop telemetry
reg delete "HKCU\Software\Policies\Microsoft\Windows\DataCollection" /f /va >nul 2>&1
set "key=HKLM\Software\Policies\Microsoft\Windows\DataCollection"
reg add "%key%" /f /t REG_DWORD /d 0 /v AllowDesktopAnalyticsProcessing
reg add "%key%" /f /t REG_DWORD /d 1 /v LimitEnhancedDiagnosticDataWindowsAnalytics
reg add "%key%" /f /t REG_DWORD /d 0 /v AllowTelemetry
reg add "%key%" /f /t REG_DWORD /d 0 /v AllowDeviceNameInTelemetry
reg add "%key%" /f /t REG_DWORD /d 1 /v DisableTelemetryOptInChangeNotification
reg add "%key%" /f /t REG_DWORD /d 0 /v AllowWUfBCloudProcessing
reg add "%key%" /f /t REG_DWORD /d 0 /v AllowUpdateComplianceProcessing
reg add "%key%" /f /t REG_DWORD /d 1 /v DisableTelemetryOptInSettingsUx

echo.
echo Set timezone to SE Asia Standard Time (GMT+7) and sync time
tzutil /s "SE Asia Standard Time"
net start w32time >nul 2>&1
w32tm /resync

echo.
echo Disable Telemetry Service and set manual for Windows Search
sc stop diagtrack
sc config diagtrack start=disabled
sc config WSearch start=demand

echo.
echo Schedule Windows Update cache cleanup every 7 days
schtasks /create /tn "Clear WU Cache" /tr "cmd /c net stop wuauserv & net stop bits & rd /s /q %windir%\SoftwareDistribution\Download & md %windir%\SoftwareDistribution\Download & net start bits & net start wuauserv" /sc daily /mo 7 /st 12:00 /ru SYSTEM /rl HIGHEST /f

echo.
echo Optimize (TRIM) SSD disk (C, D drive)
defrag C: /O
defrag D: /O

echo.
echo Turn off BitLocker for C and D and E (if exist)
manage-bde -off c:
manage-bde -off d:
manage-bde -off e:

echo.
echo Reduce CPU usage by WD
powershell.exe -NoProfile -Command "Set-MpPreference -ScanAvgCPULoadFactor 30"

echo.
echo Disable BingSearch Taskbar
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f

echo.
echo Remove some apps
set "apps='Microsoft.Copilot','Microsoft.OutlookForWindows','Microsoft.BingNews','Microsoft.MicrosoftOfficeHub','Microsoft.BingWeather','Microsoft.WindowsFeedbackHub','Microsoft.WindowsMaps','Microsoft.XboxSpeechToTextOverlay','Microsoft.SkypeApp','Microsoft.Microsoft3DViewer','Microsoft.MixedReality.Portal','Microsoft.People','Microsoft.Getstarted','Microsoft.BingSearch','Microsoft.GetHelp','MicrosoftCorporationII.MicrosoftFamily','Clipchamp.Clipchamp'"
powershell.exe -NoProfile -Command "%apps% | ForEach-Object { Get-AppxPackage -AllUsers $_ | Remove-AppxPackage -ErrorAction SilentlyContinue }"

echo.
echo HPET optimization
bcdedit /set useplatformtick yes
bcdedit /set disabledynamictick yes
bcdedit /deletevalue useplatformclock

echo.
echo Enabling DirectPlay
dism.exe /online /enable-feature /featurename:DirectPlay /all
echo Enabling .NET Framework 3.5 per OS....
set "sxs=%~dp0\sxs\sxs10"
if %build% GEQ 22000 set "sxs=%~dp0\sxs\sxs11"
dism.exe /online /enable-feature /featurename:NetFx3 /all /limitaccess /source:"%sxs%"

echo Done!
exit /b


:lapOrDesk
echo Checking platform..
set "isLaptop=0"
for /f %%A in ('powershell -NoProfile -Command "$t=@((Get-CimInstance Win32_SystemEnclosure).ChassisTypes); $b=[bool](Get-CimInstance Win32_Battery); $core=[bool]($t | Where-Object {$_ -in 8,9,10,14,30,31,32}); $amb=[bool]($t | Where-Object {$_ -in 1,2,11,12,18,21}); [int]($core -or ($b -and $amb))"') do set "isLaptop=%%A"

if "%isLaptop%"=="1" (
  echo Laptop: set Balanced power plan
  powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e
  powercfg -change -monitor-timeout-ac 60
  powercfg -change -monitor-timeout-dc 15
  powercfg -change -standby-timeout-ac 0
) else (
  echo Desktop: set High Performance power plan
  powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
  powercfg -change -monitor-timeout-ac 60
)
goto :eof

:adjustRegistry
echo Checking OS version first
set /a build=0
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber') do set /a build=%%A

rem Windows 11 = build 22000 or higher, Windows 10 = build 10240 - 21999
if %build% GEQ 22000 (
  echo Applying w11.reg...
  reg import "%~dp0w11.reg"
) else if %build% GEQ 10240 (
  echo Applying w10.reg...
  reg import "%~dp0w10.reg"
  powershell.exe -NoProfile -Command "(New-Object -Com Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items() | %%{ $_.Verbs() } | ? {$_.Name -match 'Un.*pin from Start'} | %%{$_.DoIt()}"
) else (
  echo OS not recognized as Windows 10 or Windows 11.
)
goto :eof
