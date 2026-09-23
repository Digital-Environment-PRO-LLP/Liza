@echo off
setlocal enabledelayedexpansion

:: Build Windows installer using Inno Setup
:: Run this AFTER: flutter build windows --release

:: Extract version from pubspec.yaml
set "PUBSPEC=%~dp0..\pubspec.yaml"
for /f "tokens=2 delims= " %%v in ('findstr /r "^version:" "%PUBSPEC%"') do set "RAW_VERSION=%%v"
set "FULL_VERSION=%RAW_VERSION:+=.%"

if "%FULL_VERSION%"=="" (
    echo ERROR: Could not extract version from pubspec.yaml
    exit /b 1
)

echo Building installer for Liza v%FULL_VERSION%

:: Verify build output exists
set "BUILD_DIR=%~dp0..\build\windows\x64\runner\Release"
if not exist "%BUILD_DIR%\liza.exe" (
    echo ERROR: Build not found. Run 'flutter build windows --release' first.
    exit /b 1
)

:: Find Inno Setup compiler
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if "%ISCC%"=="" if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if "%ISCC%"=="" if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if "%ISCC%"=="" (
    where ISCC.exe >nul 2>&1 && set "ISCC=ISCC.exe"
)
if "%ISCC%"=="" (
    echo ERROR: Inno Setup 6 not found. Install from https://jrsoftware.org/isdl.php
    exit /b 1
)

echo Using Inno Setup: %ISCC%

:: Run Inno Setup compiler
"%ISCC%" /DMyAppVersion=%FULL_VERSION% "%~dp0..\windows\installer.iss"
if errorlevel 1 (
    echo ERROR: Inno Setup compilation failed
    exit /b 1
)

echo.
echo Installer ready: %~dp0..\build\windows\installer\Liza.exe (%FULL_VERSION%)
