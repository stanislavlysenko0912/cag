$ErrorActionPreference = "Stop"

$Repo = "stanislavlysenko0912/cag"
$InstallDir = if ($env:CAG_INSTALL_DIR) { $env:CAG_INSTALL_DIR } else { "$env:LOCALAPPDATA\cag" }
$Version = if ($args[0]) { $args[0] } else { "latest" }

function Write-Info($msg) { Write-Host "=> $msg" -ForegroundColor Blue }
function Write-Success($msg) { Write-Host "=> $msg" -ForegroundColor Green }
function Write-Error($msg) { Write-Host "Error: $msg" -ForegroundColor Red; exit 1 }

function Get-LatestVersion {
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    return $release.tag_name
}

function Main {
    Write-Info "Platform: windows_x64"

    if ($Version -eq "latest") {
        Write-Info "Fetching latest version..."
        $Version = Get-LatestVersion
    }
    Write-Info "Version: $Version"

    $Url = "https://github.com/$Repo/releases/download/$Version/cag_windows_x64.zip"
    $TmpDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }

    try {
        Write-Info "Downloading $Url..."
        Invoke-WebRequest -Uri $Url -OutFile "$TmpDir\cag.zip"

        Write-Info "Extracting..."
        Expand-Archive -Path "$TmpDir\cag.zip" -DestinationPath $TmpDir -Force

        Write-Info "Installing to $InstallDir..."
        if (-not (Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }
        Move-Item -Path "$TmpDir\cag.exe" -Destination "$InstallDir\cag.exe" -Force

        # Add to PATH if not already there
        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($UserPath -notlike "*$InstallDir*") {
            Write-Info "Adding $InstallDir to PATH..."
            [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", "User")
            $env:Path = "$env:Path;$InstallDir"
        }

        Write-Success "cag $Version installed successfully!"
        Write-Info "Restart your terminal, then run 'cag --help' to get started"
    }
    finally {
        Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Main
