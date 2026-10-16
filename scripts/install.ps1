<#
.SYNOPSIS
    DynBox Windows Installation Script
    Installs standalone DynBox CLI into %LOCALAPPDATA%\DynBox\bin and updates User PATH idempotently.
#>

$ErrorActionPreference = "Stop"

$DefaultInstallDir = if ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA "DynBox\bin"
} else {
    Join-Path $env:USERPROFILE "AppData\Local\DynBox\bin"
}

$InstallDir = if ($env:DYNBOX_INSTALL_DIR) { $env:DYNBOX_INSTALL_DIR } else { $DefaultInstallDir }
$Version = if ($env:DYNBOX_VERSION) { $env:DYNBOX_VERSION } else { "latest" }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "           DynBox CLI Windows Installer                   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Architecture Detection
$Arch = [System.Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")
if ($Arch -ne "AMD64" -and $Arch -ne "ARM64") {
    Write-Error "Unsupported Windows architecture: $Arch. Only x64 and arm64 are supported."
    exit 1
}

$PlatformId = if ($Arch -eq "AMD64") { "windows-x64" } else { "windows-arm64" }
Write-Host "Detected Platform: $PlatformId"
Write-Host "Installation Directory: $InstallDir"
Write-Host ""

# 2. Temporary Staging Directory
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dynbox_install_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    # 3. Resolve Release URL
    $BaseUrl = if ($env:DYNBOX_RELEASE_URL) {
        $env:DYNBOX_RELEASE_URL
    } elseif ($Version -eq "latest") {
        "https://github.com/juwelzan/dynbox/releases/latest/download"
    } else {
        "https://github.com/juwelzan/dynbox/releases/download/v$Version"
    }

    $ManifestUrl = "$BaseUrl/release_manifest.json"
    $ManifestFile = Join-Path $TempDir "release_manifest.json"

    Write-Host "Fetching release metadata from $ManifestUrl..."
    Invoke-WebRequest -Uri $ManifestUrl -OutFile $ManifestFile -UseBasicParsing

    $Manifest = Get-Content -Raw -Path $ManifestFile | ConvertFrom-Json
    $ResolvedVersion = $Manifest.version
    Write-Host "Resolved DynBox Version: v$ResolvedVersion"

    $Artifact = $Manifest.artifacts.$PlatformId
    if (-not $Artifact) {
        Write-Error "No release artifact available for $PlatformId in version v$ResolvedVersion."
        exit 1
    }

    $ArtifactName = $Artifact.fileName
    $ExpectedSha256 = $Artifact.sha256.ToLower().Trim()
    $ArtifactUrl = "$BaseUrl/$ArtifactName"
    $ArchiveFile = Join-Path $TempDir $ArtifactName

    Write-Host "Downloading $ArtifactName..."
    Invoke-WebRequest -Uri $ArtifactUrl -OutFile $ArchiveFile -UseBasicParsing

    # 4. SHA-256 Verification
    Write-Host "Verifying SHA-256 checksum..."
    $ActualSha256 = (Get-FileHash -Path $ArchiveFile -Algorithm SHA256).Hash.ToLower().Trim()

    if ($ActualSha256 -ne $ExpectedSha256) {
        Write-Error "Cryptographic checksum mismatch! Expected: $ExpectedSha256, Actual: $ActualSha256. Aborting."
        exit 1
    }
    Write-Host "✅ Checksum verified." -ForegroundColor Green

    # 5. Extract Archive
    $ExtractedDir = Join-Path $TempDir "extracted"
    Expand-Archive -Path $ArchiveFile -DestinationPath $ExtractedDir -Force

    $SourceExe = Join-Path $ExtractedDir "dynbox.exe"
    if (-not (Test-Path $SourceExe)) {
        Write-Error "Extracted archive did not contain 'dynbox.exe'."
        exit 1
    }

    # 6. Install to User Directory
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $TargetExe = Join-Path $InstallDir "dynbox.exe"
    Copy-Item -Path $SourceExe -Destination $TargetExe -Force
    Write-Host "✅ Installed binary to: $TargetExe" -ForegroundColor Green
    Write-Host ""

    # 7. Update User PATH Environment Variable Idempotently
    $UserPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
    if ($UserPath -notlike "*$InstallDir*") {
        $NewPath = if ([string]::IsNullOrWhiteSpace($UserPath)) { $InstallDir } else { "$UserPath;$InstallDir" }
        [System.Environment]::SetEnvironmentVariable("Path", $NewPath, [System.EnvironmentVariableTarget]::User)
        Write-Host "Updated User PATH environment variable."
    }

    # Also update current session Path
    if ($env:Path -notlike "*$InstallDir*") {
        $env:Path = "$env:Path;$InstallDir"
    }

    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "🎉 DynBox was successfully installed!" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verify in your current session:"
    Write-Host "  dynbox --version"
    Write-Host ""
}
finally {
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
