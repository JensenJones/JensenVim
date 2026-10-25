param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$source = $PSScriptRoot
$config = Join-Path $env:LOCALAPPDATA 'jvim'
$bin = Join-Path $env:LOCALAPPDATA 'JensenVim/bin'
Write-Host "Configuration: $config"
Write-Host "Launcher: $bin/jvim.ps1"
Write-Host 'Windows support is experimental. Use Neovide; iTerm/Herdr integration is macOS only.'
if (!$Apply) {
    Write-Host 'Preview only. Run ./install-windows.ps1 -Apply to install.'
    exit 0
}
foreach ($tool in @('nvim', 'neovide', 'rg', 'git')) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Install $tool and add it to PATH first. See README.md." }
}
$backup = Join-Path $env:LOCALAPPDATA ('JensenVim/backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
foreach ($path in @($config, $bin)) {
    if (Test-Path $path) {
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Move-Item -LiteralPath $path -Destination (Join-Path $backup (Split-Path $path -Leaf))
    }
}
Copy-Item -LiteralPath (Join-Path $source 'config') -Destination $config -Recurse
New-Item -ItemType Directory -Force -Path $bin | Out-Null
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Files)
$previous = $env:NVIM_APPNAME
try {
    $env:NVIM_APPNAME = 'jvim'
    & neovide @Files
} finally {
    $env:NVIM_APPNAME = $previous
}
'@ | Set-Content -LiteralPath (Join-Path $bin 'jvim.ps1')
Write-Host "Installed. Add $bin to your user PATH, then run jvim.ps1 ."
Write-Host 'First launch downloads plugins and language tools. The installer itself does not invoke Git.'
if (Test-Path $backup) { Write-Host "Backups: $backup" }
