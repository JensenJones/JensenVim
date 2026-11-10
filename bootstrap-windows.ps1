# One-line jvim setup for Windows. In PowerShell:
#
#   irm https://raw.githubusercontent.com/JensenJones/JensenVim/main/bootstrap-windows.ps1 | iex
#
# Installs any missing prerequisites with winget, clones (or fast-forwards) the
# repository into $HOME\JensenVim, installs jvim and puts `jvim` on your PATH.
# Rerun it any time to update. Optional settings, set before running:
#   $env:JVIM_FRONTEND = 'nvim'      # run inside your terminal instead of Neovide
#   $env:JVIM_DIR = 'D:\src\jvim'    # clone somewhere other than $HOME\JensenVim
& {
    $ErrorActionPreference = 'Stop'
    $repo = 'https://github.com/JensenJones/JensenVim.git'
    $frontend = if ($env:JVIM_FRONTEND) { $env:JVIM_FRONTEND } else { 'neovide' }
    if ($frontend -notin @('neovide', 'nvim')) { throw "JVIM_FRONTEND must be 'neovide' or 'nvim', not '$frontend'." }
    $checkout = if ($env:JVIM_DIR) { $env:JVIM_DIR } else { Join-Path $HOME 'JensenVim' }

    function Update-SessionPath {
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = (@($machine, $user, $env:Path) | Where-Object { $_ }) -join ';'
    }
    # Native tools write progress to stderr; judge them by exit code, not by PowerShell error records.
    function Invoke-Native([scriptblock]$command) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & $command 2>&1 | ForEach-Object { Write-Host "    $_" } } finally { $ErrorActionPreference = $previous }
        return $LASTEXITCODE
    }
    function Test-Tool([string]$name) { [bool](Get-Command $name -CommandType Application -ErrorAction SilentlyContinue) }
    function Add-UserPath([string]$directory) {
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ((@($user -split ';') -notcontains $directory)) {
            [Environment]::SetEnvironmentVariable('Path', ((@($user -split ';' | Where-Object { $_ }) + $directory) -join ';'), 'User')
        }
        if ((@($env:Path -split ';') -notcontains $directory)) { $env:Path += ";$directory" }
    }
    function Install-PortableNeovide {
        $release = Invoke-RestMethod 'https://api.github.com/repos/neovide/neovide/releases/latest' -Headers @{ 'User-Agent' = 'jvim-bootstrap' }
        $asset = $release.assets | Where-Object { $_.name -eq 'neovide-windows-x86_64.zip' } | Select-Object -First 1
        if (!$asset) { throw 'Could not find a portable Neovide download.' }
        $download = Join-Path ([IO.Path]::GetTempPath()) ('jvim-neovide-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $download | Out-Null
        $archive = Join-Path $download 'neovide.zip'
        Invoke-WebRequest $asset.browser_download_url -OutFile $archive -UseBasicParsing
        $target = Join-Path $env:LOCALAPPDATA 'Programs\Neovide'
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $target -Force
        Remove-Item -Recurse -Force -LiteralPath $download
        Add-UserPath $target
    }

    Write-Host 'jvim setup for Windows' -ForegroundColor Cyan
    if (!(Test-Tool 'winget')) {
        throw 'winget is required. Install "App Installer" from the Microsoft Store, then rerun this command.'
    }
    $packages = @(
        @{ Tool = 'git'; Id = 'Git.Git' },
        @{ Tool = 'nvim'; Id = 'Neovim.Neovim' },
        @{ Tool = 'rg'; Id = 'BurntSushi.ripgrep.MSVC' },
        @{ Tool = 'tree-sitter'; Id = 'tree-sitter.tree-sitter-cli' }
    )
    if ($frontend -eq 'neovide') { $packages += @{ Tool = 'neovide'; Id = 'Neovide.Neovide' } }
    Update-SessionPath
    foreach ($package in $packages) {
        if (Test-Tool $package.Tool) { Write-Host "  ok  $($package.Tool)"; continue }
        Write-Host "  installing $($package.Id)..."
        $null = Invoke-Native { winget install -e --id $package.Id --accept-source-agreements --accept-package-agreements --disable-interactivity }
        Update-SessionPath
        if (!(Test-Tool $package.Tool) -and $package.Tool -eq 'neovide') {
            # Neovide's winget package is a machine-wide MSI; fall back to the official portable build.
            Write-Host '  winget could not install Neovide (it needs administrator approval); using the portable build.'
            Install-PortableNeovide
        }
        if (!(Test-Tool $package.Tool)) { throw "Could not install $($package.Tool). Install $($package.Id) manually and rerun." }
    }

    # Tree-sitter compiles syntax parsers on first launch and needs a C compiler.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $msvc = (Test-Path $vswhere) -and (& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
    if (!$msvc -and !(Test-Tool 'cl') -and !(Test-Tool 'gcc') -and !(Test-Tool 'clang')) {
        Write-Warning ('No C compiler found, so syntax highlighting parsers cannot be built. Install one, then restart jvim:' +
            "`n    winget install -e --id Microsoft.VisualStudio.2022.BuildTools --override `"--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended`"")
    }
    if (!(Test-Tool 'py')) {
        Write-Host '  note: C++ compiler checks need Python 3 (winget install -e --id Python.Python.3.12).'
    }

    if (Test-Path -LiteralPath (Join-Path $checkout '.git')) {
        Write-Host "Updating $checkout"
        if (Invoke-Native { git -C $checkout pull --ff-only }) { throw "Could not fast-forward $checkout. Commit or stash local changes, then rerun." }
    } elseif (Test-Path -LiteralPath $checkout) {
        throw "$checkout exists but is not a Git checkout. Move it aside or set `$env:JVIM_DIR, then rerun."
    } else {
        Write-Host "Cloning jvim into $checkout"
        if (Invoke-Native { git clone $repo $checkout }) { throw 'git clone failed.' }
    }

    # Run the installer as a separate process so machine policies such as AllSigned do not block it.
    $installer = Join-Path $checkout 'install-windows.ps1'
    if (Invoke-Native { powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer -Apply -AddToPath -Frontend $frontend }) { throw 'The jvim installer failed; see the messages above.' }
    Update-SessionPath
    Write-Host ''
    Write-Host 'Done. Open a project with:  jvim .' -ForegroundColor Green
    Write-Host 'The first launch downloads plugins and language servers, so give it a minute.'
}
