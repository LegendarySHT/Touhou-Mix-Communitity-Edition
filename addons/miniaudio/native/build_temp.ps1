# 临时编译脚本
$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
$nativeDir = "d:\Touhou Mix Dev\THMIX Community Edition\addons\miniaudio\native"
$tempBat = Join-Path $env:TEMP "build_ma_temp.bat"
$content = @"
@echo off
call "$vcvars"
cd /d "$nativeDir"
call build_windows.bat
"@
Set-Content -Path $tempBat -Value $content -Encoding ASCII
Write-Host "Building miniaudio_bridge.dll..."
& $tempBat
$exitCode = $LASTEXITCODE
Remove-Item $tempBat -ErrorAction SilentlyContinue
exit $exitCode
