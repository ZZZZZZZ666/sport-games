# Builds (and optionally flashes) the firmware without needing an "ESP-IDF shell".
#   .\build.ps1              build
#   .\build.ps1 -Port COM5            build + flash
#   .\build.ps1 -Port COM5 -Monitor   build + flash + serial monitor
# Pins the ESP-IDF Python env explicitly: export.ps1 otherwise picks whatever python is first
# on PATH (e.g. a system 3.12) and fails looking for a venv that was never installed.
param([string]$Port = "", [switch]$Monitor)
$ErrorActionPreference = "Stop"
$idf = $env:IDF_PATH
if (-not $idf -or -not (Test-Path -LiteralPath (Join-Path $idf 'export.ps1'))) {
    throw 'Set IDF_PATH to your ESP-IDF 5.1 installation, or build in an ESP-IDF terminal with idf.py build.'
}
$tools = if ($env:IDF_TOOLS_PATH) { $env:IDF_TOOLS_PATH } else { Join-Path $env:USERPROFILE '.espressif' }
$env:IDF_PATH = $idf
$env:IDF_TOOLS_PATH = $tools
$venv = Get-ChildItem "$tools\python_env" -Directory -Filter "idf5.1_py*_env" | Select-Object -First 1
if ($venv) { $env:IDF_PYTHON_ENV_PATH = $venv.FullName }
$py = Get-ChildItem "$tools\tools\idf-python" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($py) { $env:PATH = "$($py.FullName);$env:PATH" }
. "$idf\export.ps1" | Out-Null
Set-Location $PSScriptRoot
if (-not (Test-Path build)) { idf.py set-target esp32c6 }
if ($Port -and $Monitor) { idf.py -p $Port build flash monitor }
elseif ($Port) { idf.py -p $Port build flash }
else { idf.py build }
