param(
    [switch]$Apply,
    [ValidateSet('neovide', 'nvim')][string]$Frontend = 'neovide'
)
$ErrorActionPreference = 'Stop'
foreach ($name in @('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME')) {
    if ([Environment]::GetEnvironmentVariable($name)) {
        throw "Custom XDG paths are not supported: $name. Unset them before installing and launching jvim."
    }
}
if (!$env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required to locate the isolated jvim installation.' }
$source = $PSScriptRoot
$config = Join-Path $env:LOCALAPPDATA 'jvim'
$bin = Join-Path $env:LOCALAPPDATA 'JensenVim/bin'
Write-Host "Configuration: $config"
Write-Host "Launcher: $bin/jvim.ps1 ($Frontend)"
Write-Host 'Windows support is experimental; iTerm/Herdr integration is macOS only.'
if (!$Apply) {
    Write-Host 'Preview only. Run ./install-windows.ps1 -Apply [-Frontend nvim] to install.'
    exit 0
}
$tools = @('nvim', 'rg', 'git')
if ($Frontend -eq 'neovide') { $tools += 'neovide' }
foreach ($tool in $tools) {
    if (!(Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "Install $tool and add it to PATH first. See README.md."
    }
}
$installId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
$backup = Join-Path $env:LOCALAPPDATA ('JensenVim/backups/' + $installId)
$stage = Join-Path ([IO.Path]::GetTempPath()) ('jvim-install-' + $installId)
# Prepare every file before moving any installed files. Stage directories are
# retained after a failure for inspection; backups are never deleted here.
New-Item -ItemType Directory -Path $stage | Out-Null
$preparedConfig = Join-Path $stage 'jvim'
Copy-Item -LiteralPath (Join-Path $source 'config') -Destination $preparedConfig -Recurse -Exclude '__pycache__', '*.pyc', '.DS_Store'
$preparedBin = Join-Path $stage 'bin'
New-Item -ItemType Directory -Path $preparedBin | Out-Null
$launcher = @'
[CmdletBinding(PositionalBinding=$false)]
param(
    [ValidateSet('neovide', 'nvim')][string]$Frontend = '__FRONTEND__',
    [Parameter(Position=0, ValueFromRemainingArguments=$true)][string[]]$Files
)
$ErrorActionPreference = 'Stop'
foreach ($name in @('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME')) {
    if ([Environment]::GetEnvironmentVariable($name)) { throw "Custom XDG paths are not supported: $name. Unset them before launching jvim." }
}
$nvimName = if ($env:JVIM_NVIM) { $env:JVIM_NVIM } else { 'nvim' }
$nvim = Get-Command $nvimName -CommandType Application -ErrorAction SilentlyContinue
if (!$nvim) { throw "Cannot find executable Neovim: $nvimName. Install nvim on PATH or set JVIM_NVIM." }
$executable = $nvim.Source
if ($Frontend -eq 'neovide') {
    $gui = Get-Command neovide -CommandType Application -ErrorAction SilentlyContinue
    if (!$gui) { throw 'Install Neovide or launch with -Frontend nvim.' }
    $executable = $gui.Source
}
$previous = $env:NVIM_APPNAME
try {
    $env:NVIM_APPNAME = 'jvim'
    if ($Frontend -eq 'neovide') { & $executable --neovim-bin $nvim.Source @Files }
    else { & $executable @Files }
    $status = $LASTEXITCODE
} finally {
    $env:NVIM_APPNAME = $previous
}
exit $status
'@
$launcher.Replace('__FRONTEND__', $Frontend) | Set-Content -LiteralPath (Join-Path $preparedBin 'jvim.ps1')
$changed = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($replacement in @(@($config, $preparedConfig), @($bin, $preparedBin))) {
        $target = $replacement[0]
        $prepared = $replacement[1]
        $saved = Join-Path $backup (Split-Path $target -Leaf)
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        $existed = Test-Path -LiteralPath $target
        if ($existed) {
            New-Item -ItemType Directory -Force -Path $backup | Out-Null
            Move-Item -LiteralPath $target -Destination $saved
        }
        $changed.Add(@($target, $saved, $existed))
        Move-Item -LiteralPath $prepared -Destination $target
    }
} catch {
    $failure = $_
    for ($index = $changed.Count - 1; $index -ge 0; $index--) {
        $target, $saved, $existed = $changed[$index]
        try {
            if (Test-Path -LiteralPath $target) {
                Move-Item -LiteralPath $target -Destination (Join-Path $stage ('failed-' + $index))
            }
            if ($existed) { Move-Item -LiteralPath $saved -Destination $target }
        } catch {
            Write-Warning "Recovery incomplete for $target. Previous files remain at $saved. Error: $_"
        }
    }
    Write-Warning "Installation failed. Preparation retained at $stage; backups at $backup."
    throw $failure
}
# Only empty staging directories remain after successful publication.
Remove-Item -LiteralPath $stage
Write-Host "Installed. Add $bin to your user PATH, then run jvim.ps1 ."
Write-Host 'First launch may download plugins/tools according to your settings. The installer does not invoke Git.'
if (Test-Path -LiteralPath $backup) { Write-Host "Backups: $backup" }
