@echo off
REM ============================================================================
REM  Thin wrapper that invokes build_android.ps1
REM
REM  Usage:
REM    build_android.bat                       (auto-detect NDK)
REM    build_android.bat "C:\path\to\ndk"      (explicit NDK path)
REM    set ANDROID_NDK_HOME=C:\path\to\ndk
REM    build_android.bat
REM
REM  All real logic lives in build_android.ps1 (PowerShell is far more robust
REM  than batch for path detection / directory enumeration).
REM ============================================================================

setlocal
set "PS_ARG="
if not "%~1"=="" set "PS_ARG=%~1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_android.ps1" -NdkPath "%PS_ARG%"
set "EXITCODE=%ERRORLEVEL%"

endlocal & exit /b %EXITCODE%
