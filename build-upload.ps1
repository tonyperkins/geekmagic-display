# Build and OTA upload ESPHome project using a Python 3.11 venv
# Usage:
#   ./build-upload.ps1 [path-to-yaml] [--device <host-or-ip>] [-Clean] [-SyncToHA] [-HAPath \\HA\config\esphome] [-HAFilename name.yaml]
# Examples:
#   ./build-upload.ps1                 # builds & uploads geekmagic-clock.yaml (no clean), then syncs to HA as geekmagic-clock.yaml
#   ./build-upload.ps1 geekmagic-clock.yaml -Device 192.168.50.134   # explicit device
#   ./build-upload.ps1 geekmagic-clock.yaml -HAPath \\homeassistant\config\esphome
#   ./build-upload.ps1 -SyncOnly       # Skips build/upload, only syncs the YAML to HA
#   ./build-upload.ps1 -Clean          # Performs a clean before building

param(
  [string]$Yaml = "geekmagic-clock.yaml",
  [string]$Device = "",
  [Alias('S')][string[]]$Secrets = @(),
  [switch]$SyncToHA,
  [string]$HAPath = "\\homeassistant\config\esphome",
  [string]$HAFilename = "geekmagic-clock.yaml",
  [switch]$SyncOnly,
  [switch]$Clean
)

$ErrorActionPreference = "Stop"

# Defaults requested: if SyncToHA not provided, enable it by default
if (-not $PSBoundParameters.ContainsKey('SyncToHA')) { $SyncToHA = $true }

function Activate-Venv311 {
  if (!(Test-Path ".venv311")) {
    Write-Host "Creating Python 3.11 venv at .venv311 ..." -ForegroundColor Cyan
    py -3.11 -m venv .venv311
  }

  $activate = Join-Path ".venv311" "Scripts/Activate.ps1"
  if (!(Test-Path $activate)) {
    throw "Activation script not found at $activate"
  }
  Write-Host "Activating .venv311 ..." -ForegroundColor Cyan
  . $activate

  $ver = & python --version
  Write-Host "Python: $ver" -ForegroundColor DarkGray
}

function Ensure-ESPHomeInstalled {
  try {
    $null = & esphome version 2>$null
    Write-Host "ESPHome CLI found." -ForegroundColor DarkGray
  } catch {
    Write-Host "Installing ESPHome into .venv311 ..." -ForegroundColor Cyan
    python -m pip install --upgrade pip
    python -m pip install esphome
  }
}

function Run-ESPHome {
  param([string[]]$esphomeArgs)
  try {
    & esphome @esphomeArgs
  } catch {
    # Fallback to module form if PATH shim isn’t available
    & python -m esphome @esphomeArgs
  }
}

# Optional: ease PowerShell policy for this session only
try {
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
} catch {}

if (-not $SyncOnly) {
  # 1) Activate venv
  Activate-Venv311

  # 2) Ensure ESPHome is present
  Ensure-ESPHomeInstalled

  # 3) Clean build files (optional)
  if ($Clean) {
    Write-Host "Cleaning build files for $Yaml ..." -ForegroundColor Yellow
    Run-ESPHome @('clean', $Yaml)
  } else {
    Write-Host "Skipping clean (use -Clean to force)" -ForegroundColor DarkGray
  }

  # 4) Run (compile and upload)
  $runArgs = @('run', $Yaml)
  if ($Device -and $Device.Trim().Length -gt 0) { $runArgs += @('--device', $Device) }
  # Add -s key value overrides from -S key=value
  foreach ($pair in $Secrets) {
    if ($pair -match "^") {} # noop to ensure -match exists
    $kv = $pair -split '=', 2
    if ($kv.Count -eq 2) { $runArgs += @('-s', $kv[0], $kv[1]) }
  }
  Write-Host "Running (compile and upload) on $Yaml ..." -ForegroundColor Yellow
  try {
    Run-ESPHome $runArgs
  } catch {
    Write-Warning "Run failed. If the error mentions secrets.yaml missing, either add a local secrets.yaml or pass -S wifi_ssid=... -S wifi_password=..."
    throw
  }
}

if ($SyncToHA) {
  try {
    # Determine destination filename
    $destName = if ([string]::IsNullOrWhiteSpace($HAFilename)) { [IO.Path]::GetFileName($Yaml) } else { $HAFilename }
    $dest = Join-Path $HAPath $destName
    Write-Host "Syncing to HA: $dest" -ForegroundColor Cyan
    if (!(Test-Path $HAPath)) {
      Write-Warning "HA path $HAPath not reachable. Ensure Samba share is mounted and path is correct."
    } else {
      Copy-Item -Path $Yaml -Destination $dest -Force
      Write-Host "Synced $Yaml -> $dest" -ForegroundColor DarkGray
    }
  } catch {
    Write-Warning "Samba sync failed: $($_.Exception.Message)"
  }
}

Write-Host "Done." -ForegroundColor Green
