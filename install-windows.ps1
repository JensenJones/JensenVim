param(
    [switch]$Apply,
    [ValidateSet('neovide', 'nvim')][string]$Frontend = 'neovide',
    # Adds the launcher folder to the user PATH (off by default so isolated test installs never touch it).
    [switch]$AddToPath
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
$wezterm = Join-Path $env:LOCALAPPDATA 'JensenVim/wezterm'
Write-Host "Configuration: $config"
Write-Host "Launcher: $bin/jvim.cmd ($Frontend)"
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
New-Item -ItemType Directory -Path (Join-Path $preparedBin 'lib') -Force | Out-Null
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
$nvim = Get-Command $nvimName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$nvim) { throw "Cannot find executable Neovim: $nvimName. Install nvim on PATH or set JVIM_NVIM." }
$executable = $nvim.Source
if ($Frontend -eq 'neovide') {
    $gui = Get-Command neovide -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
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
$launcher.Replace('__FRONTEND__', $Frontend) | Set-Content -LiteralPath (Join-Path $preparedBin 'lib/jvim.ps1')
# jvim.cmd lets `jvim` run from cmd.exe, PowerShell and Explorer without execution-policy changes.
$shim = @'
@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\jvim.ps1" %*
exit /b %ERRORLEVEL%
'@
$shim | Set-Content -LiteralPath (Join-Path $preparedBin 'jvim.cmd') -Encoding ASCII
$preparedWezterm = Join-Path $stage 'wezterm'
New-Item -ItemType Directory -Path $preparedWezterm | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'integrations/wezterm/jvim.lua') -Destination (Join-Path $preparedWezterm 'wezterm.lua')
Copy-Item -LiteralPath (Join-Path $source 'integrations/wezterm/wezterm.lua') -Destination (Join-Path $preparedWezterm 'wezterm-config.lua')
$changed = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($replacement in @(@($config, $preparedConfig), @($bin, $preparedBin), @($wezterm, $preparedWezterm))) {
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
$userWezterm = Join-Path $env:USERPROFILE '.wezterm.lua'
if ((Test-Path -LiteralPath $userWezterm) -or (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.config/wezterm/wezterm.lua'))) {
    Write-Host "WezTerm config left unchanged. To use jvim's terminal settings, see README.md."
} else {
    Copy-Item -LiteralPath (Join-Path $source 'integrations/wezterm/starter.lua') -Destination $userWezterm
    Write-Host "Created $userWezterm with jvim's terminal settings; add your own settings at its end."
}
$binPath = (Resolve-Path -LiteralPath $bin).Path
if ($AddToPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($userPath -split ';' | Where-Object { $_ })
    if ($entries -notcontains $binPath) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $binPath) -join ';'), 'User')
        Write-Host "Added $binPath to your user PATH."
    }
    if (($env:Path -split ';') -notcontains $binPath) { $env:Path += ";$binPath" }
    Write-Host 'Installed. Run: jvim .'
} else {
    Write-Host "Installed. Add $binPath to your user PATH (or rerun with -AddToPath), then run: jvim ."
}
Write-Host 'First launch may download plugins/tools according to your settings. The installer does not invoke Git.'
if (Test-Path -LiteralPath $backup) { Write-Host "Backups: $backup" }
