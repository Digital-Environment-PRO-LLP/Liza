# Build Windows installer using Inno Setup
# Run this AFTER: flutter build windows --release

$ErrorActionPreference = "Stop"

# Extract version from pubspec.yaml
$pubspec = Get-Content "$PSScriptRoot\..\pubspec.yaml" -Raw
if ($pubspec -match 'version:\s*(\S+)') {
    $fullVersion = $Matches[1] -replace '\+', '.'
    # Also keep clean version without build number
    $version = ($Matches[1] -split '\+')[0]
} else {
    Write-Error "Could not extract version from pubspec.yaml"
    exit 1
}

Write-Host "Building installer for Liza v$fullVersion"

# Verify build output exists
$buildDir = "$PSScriptRoot\..\build\windows\x64\runner\Release"
if (-not (Test-Path "$buildDir\liza.exe")) {
    Write-Error "Build not found at $buildDir. Run 'flutter build windows --release' first."
    exit 1
}

# Find Inno Setup compiler
$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe",
    "ISCC.exe"  # if in PATH
) | Where-Object { Test-Path $_ -ErrorAction SilentlyContinue } | Select-Object -First 1

if (-not $iscc) {
    # Try PATH
    $iscc = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
}

if (-not $iscc) {
    Write-Error "Inno Setup 6 not found. Install from https://jrsoftware.org/isdl.php"
    exit 1
}

Write-Host "Using Inno Setup: $iscc"

# Run Inno Setup compiler
& $iscc "/DMyAppVersion=$fullVersion" "$PSScriptRoot\..\windows\installer.iss"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup compilation failed"
    exit 1
}

$outputDir = "$PSScriptRoot\..\build\windows\installer"
Write-Host ""
Write-Host "Installer ready: $outputDir\Liza.exe ($fullVersion)"
