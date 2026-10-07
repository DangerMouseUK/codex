#Requires -Version 5.1
<#
.SYNOPSIS
    Install and verify the Windows development tools used by the Codex repository.
.DESCRIPTION
    Supports Windows PowerShell 5.1 and PowerShell 7 on x64 and ARM64 Windows.
    Run as your normal Windows user; machine-wide installers may request UAC
    elevation. Rust and pnpm versions come from the repository configuration.

    Installs prerequisites and Cargo helper tools, but does not build Codex,
    run tests, or install workspace JavaScript/Python dependencies. Existing
    tools are reused when their versions satisfy the repository's requirements.
    Compiler settings are applied only to the current PowerShell process.
.PARAMETER CheckOnly
    Verify existing tools and activate the MSVC environment in this session.
    Does not install packages or write persistent environment/Git settings.
.EXAMPLE
    & .\codex-rs\scripts\setup-windows.ps1
.EXAMPLE
    & .\codex-rs\scripts\setup-windows.ps1 -CheckOnly
.NOTES
    Requires WinGet 1.6 or newer for installation. Reopen PowerShell after setup
    when invoking this script through powershell.exe -File or pwsh -File.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Check exit codes ourselves, including on PowerShell 7 with this option enabled.
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int[]]$SuccessExitCodes = @(0)
    )

    & $FilePath @ArgumentList
    $code = $LASTEXITCODE
    if ($code -eq 3010 -or $code -eq -1978334967) {
        # WinGet INSTALL_REBOOT_REQUIRED_TO_FINISH (0x8A150109), or MSI 3010.
        throw "$FilePath requires a restart to finish installation. Restart Windows and rerun setup."
    }
    if ($SuccessExitCodes -notcontains $code) {
        throw "$FilePath failed with exit code $code. Resolve the error above and rerun setup."
    }
}

function Get-ApplicationPath {
    param([string]$Name)

    $commands = @(Get-Command $Name -CommandType Application -All -ErrorAction SilentlyContinue)
    foreach ($command in $commands) {
        # Do not launch the Microsoft Store's Python app execution alias.
        if ($Name -eq 'python.exe' -and $command.Source -match '\\Microsoft\\WindowsApps\\') {
            continue
        }
        return $command.Source
    }
    return $null
}

function Update-SessionPath {
    param([string[]]$Prepend = @())

    $entries = @($Prepend) + @(
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        $env:Path
    )
    $paths = @()
    foreach ($entry in $entries) {
        foreach ($part in ($entry -split ';')) {
            $part = [Environment]::ExpandEnvironmentVariables($part.Trim().Trim('"'))
            if ($part -and $paths -notcontains $part) { $paths += $part }
        }
    }
    $env:Path = $paths -join ';'
}

function Add-UserPath {
    param([string]$Directory)

    if (-not $CheckOnly) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (@($userPath -split ';') -notcontains $Directory) {
            $newPath = (@($Directory) + @($userPath -split ';' | Where-Object { $_ })) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        }
    }
    Update-SessionPath -Prepend @($Directory)
}

function Get-ToolVersion {
    param([string]$Command, [string[]]$VersionArguments = @('--version'))

    $path = Get-ApplicationPath $Command
    if (-not $path) { return $null }
    $output = (Invoke-Native $path $VersionArguments) -join [Environment]::NewLine
    if ($output -notmatch '(?<!\d)(\d+\.\d+(?:\.\d+)?)(?!\d)') {
        throw "Could not determine $Command version from: $output"
    }
    return [version]$Matches[1]
}

function Install-WinGetPackage {
    param([string]$Id, [string[]]$ExtraArguments = @(), [string]$Architecture = $script:Architecture)

    if ($CheckOnly) { throw "$Id is missing or unsuitable. Rerun setup without -CheckOnly to install it." }
    $winget = Get-ApplicationPath 'winget.exe'
    if (-not $winget) {
        throw 'WinGet is required. Install/update App Installer from Microsoft, then rerun setup.'
    }
    $wingetVersion = Get-ToolVersion 'winget.exe'
    if ($wingetVersion -lt [version]'1.6') { throw 'Update App Installer: setup requires WinGet 1.6 or newer.' }

    Write-Host "-- Installing $Id ($Architecture)" -ForegroundColor Cyan
    $arguments = @(
        'install', '--id', $Id, '--exact', '--source', 'winget',
        '--architecture', $Architecture, '--silent', '--disable-interactivity',
        '--accept-package-agreements', '--accept-source-agreements'
    ) + $ExtraArguments
    # WinGet may report an already installed package or no applicable upgrade.
    # Callers must still verify that the installed tools actually work.
    Invoke-Native $winget $arguments -SuccessExitCodes @(
        0, -1978335189, -1978335135, -1978334963
    ) | Out-Host
    Update-SessionPath
}

function Ensure-Tool {
    param(
        [string]$Id,
        [string]$Command,
        [version]$MinimumVersion = '0.0',
        [string[]]$ExtraArguments = @()
    )

    $version = $null
    try { $version = Get-ToolVersion $Command } catch { Write-Verbose $_ }
    if (-not $version -or $version -lt $MinimumVersion) {
        Install-WinGetPackage $Id -ExtraArguments $ExtraArguments
        $version = Get-ToolVersion $Command
    }
    if (-not $version -or $version -lt $MinimumVersion) {
        throw "$Id did not provide a usable $Command (minimum version $MinimumVersion). Check PATH and rerun setup."
    }
    Write-Host "-- $Command $version" -ForegroundColor DarkCyan
}

function Get-WindowsArchitecture {
    $native = $env:PROCESSOR_ARCHITEW6432
    if (-not $native) { $native = $env:PROCESSOR_ARCHITECTURE }
    switch ($native) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default { throw "Unsupported Windows architecture '$native'. Use x64 or ARM64 Windows." }
    }
}

function Get-VSInstallation {
    param([string[]]$RequiredComponents = @())

    $vswhere = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    $arguments = @('-latest', '-products', '*', '-version', '[17.0,)', '-property', 'installationPath')
    if ($RequiredComponents.Count -gt 0) { $arguments += @('-requires') + $RequiredComponents }
    $path = (Invoke-Native $vswhere $arguments) -join ''
    if ($path) { return $path.Trim() }
    return $null
}

function Ensure-VisualStudio {
    $components = @(
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        'Microsoft.VisualStudio.Component.Windows11SDK.26100'
    )
    if ($script:Architecture -eq 'arm64') {
        $components += 'Microsoft.VisualStudio.Component.VC.Tools.ARM64'
    }
    $installation = Get-VSInstallation $components
    if ($installation) { return $installation }
    if ($CheckOnly) { throw 'MSVC and Windows SDK components are missing. Rerun setup without -CheckOnly.' }

    $installation = Get-VSInstallation
    if ($installation) {
        # Modify a suitable existing VS 2022 or newer instance, including full VS.
        # setup.exe has no --wait option: Start-Process waits for its process tree.
        $installer = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio\Installer\setup.exe'
        $arguments = @('modify', '--installPath', ('"{0}"' -f $installation), '--quiet', '--norestart')
        foreach ($component in $components) { $arguments += @('--add', $component) }
        $start = @{
            FilePath = $installer
            ArgumentList = $arguments
            WorkingDirectory = $script:WorkspaceRoot
            Wait = $true
            PassThru = $true
            WindowStyle = 'Hidden'
        }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $start.Verb = 'RunAs'
        }
        Write-Host '-- Adding the required MSVC and Windows SDK components' -ForegroundColor Cyan
        $process = Start-Process @start
        if ($process.ExitCode -eq 3010) { throw 'Visual Studio requires a restart. Restart Windows and rerun setup.' }
        if ($process.ExitCode -ne 0) { throw "Visual Studio modification failed with exit code $($process.ExitCode)." }
    } else {
        $arguments = @('--quiet', '--wait', '--norestart', '--add', 'Microsoft.VisualStudio.Workload.VCTools')
        foreach ($component in $components) { $arguments += @('--add', $component) }
        # The VS bootstrapper is x64 even when it installs native ARM64 tools.
        Install-WinGetPackage 'Microsoft.VisualStudio.2022.BuildTools' -Architecture 'x64' -ExtraArguments @(
            '--override', ($arguments -join ' ')
        )
    }
    $installation = Get-VSInstallation $components
    if (-not $installation) { throw 'Visual Studio setup did not install all required MSVC/SDK components.' }
    return $installation
}

function Enter-VisualStudioEnvironment {
    param([string]$Installation)

    $devCommand = Join-Path $Installation 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $devCommand)) { throw "Visual Studio developer shell is missing: $devCommand" }
    $command = '"{0}" -no_logo -arch={1} -host_arch={1} >nul && set' -f $devCommand, $script:Architecture
    # /d disables cmd AutoRun hooks; && prevents importing a failed environment.
    $lines = Invoke-Native $env:ComSpec @('/d', '/c', $command)
    $variables = @(
        'PATH', 'INCLUDE', 'LIB', 'LIBPATH', 'VCINSTALLDIR', 'VCToolsInstallDir',
        'WindowsSdkDir', 'WindowsSDKVersion', 'WindowsSDKLibVersion',
        'WindowsSdkBinPath', 'WindowsLibPath', 'UniversalCRTSdkDir', 'UCRTVersion'
    )
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$' -and $variables -contains $Matches[1]) {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
    if (-not $env:VCToolsInstallDir -or -not $env:WindowsSdkDir -or -not $env:WindowsSDKVersion) {
        throw 'Visual Studio did not expose the MSVC/Windows SDK environment.'
    }
    foreach ($tool in @('cl.exe', 'link.exe', 'rc.exe')) {
        $path = Get-ApplicationPath $tool
        if (-not $path) { throw "Visual Studio did not provide $tool for $script:Architecture." }
        $root = if ($tool -eq 'rc.exe') { $env:WindowsSdkDir } else { $env:VCToolsInstallDir }
        if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            throw "$tool resolves outside the selected Visual Studio/SDK installation: $path"
        }
    }
    $sdkVersion = $env:WindowsSDKVersion.TrimEnd('\')
    $header = Join-Path $env:WindowsSdkDir "Include\$sdkVersion\um\Windows.h"
    $library = Join-Path $env:WindowsSdkDir "Lib\$sdkVersion\um\$script:Architecture\kernel32.lib"
    if (-not (Test-Path -LiteralPath $header) -or -not (Test-Path -LiteralPath $library)) {
        throw "Windows SDK headers/libraries are missing for $script:Architecture. Repair the selected SDK."
    }
    Write-Host "-- MSVC and Windows SDK ready ($script:Architecture)" -ForegroundColor DarkCyan
}

function Test-LibclangArchitecture {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Position = 0x3C
        $stream.Position = $reader.ReadInt32()
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
        $machine = $reader.ReadUInt16()
        $expected = if ($script:Architecture -eq 'arm64') { 0xAA64 } else { 0x8664 }
        return $machine -eq $expected
    } catch [IO.EndOfStreamException] {
        return $false
    } finally {
        $reader.Dispose()
    }
}

function Ensure-LLVM {
    $nativeProgramFiles = $env:ProgramW6432
    if (-not $nativeProgramFiles) { $nativeProgramFiles = $env:ProgramFiles }
    $directories = @($env:LIBCLANG_PATH, (Join-Path $nativeProgramFiles 'LLVM\bin'))
    $clang = Get-ApplicationPath 'clang.exe'
    if ($clang) { $directories += Split-Path -Parent $clang }
    $directory = $null
    foreach ($candidate in $directories) {
        if ($candidate -and (Test-LibclangArchitecture (Join-Path $candidate 'libclang.dll')) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'clang.exe'))) {
            $directory = $candidate
            break
        }
    }
    if (-not $directory) {
        Install-WinGetPackage 'LLVM.LLVM'
        $clang = Get-ApplicationPath 'clang.exe'
        if ($clang) { $directories = @((Split-Path -Parent $clang)) + $directories }
        foreach ($candidate in $directories) {
            if ($candidate -and (Test-LibclangArchitecture (Join-Path $candidate 'libclang.dll')) -and
                (Test-Path -LiteralPath (Join-Path $candidate 'clang.exe'))) {
                $directory = $candidate
                break
            }
        }
    }
    if (-not $directory) { throw "LLVM did not provide a native $script:Architecture libclang.dll. Check the LLVM installation." }
    Add-UserPath $directory
    $env:LIBCLANG_PATH = $directory
    Invoke-Native (Join-Path $directory 'clang.exe') @('--version') | Out-Host
    # Do not set CC/CXX: native crates should continue to use MSVC by default.
}

function Get-RustConfiguration {
    $python = Get-ApplicationPath 'python.exe'
    $code = "import json, sys, tomllib; print(json.dumps(tomllib.load(open(sys.argv[1], 'rb'))['toolchain']))"
    $output = Invoke-Native $python @('-c', $code, (Join-Path $script:WorkspaceRoot 'rust-toolchain.toml'))
    return ($output -join [Environment]::NewLine) | ConvertFrom-Json
}

function Ensure-RustToolchain {
    param($Configuration)

    $hostTriple = if ($script:Architecture -eq 'arm64') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
    $toolchain = "$($Configuration.channel)-$hostTriple"
    $rustup = Get-ApplicationPath 'rustup.exe'
    if (-not $CheckOnly) {
        $arguments = @('toolchain', 'install', $toolchain, '--profile', 'minimal')
        foreach ($component in $Configuration.components) { $arguments += @('--component', $component) }
        if ($Configuration.PSObject.Properties['targets']) {
            foreach ($target in $Configuration.targets) { $arguments += @('--target', $target) }
        }
        Invoke-Native $rustup $arguments | Out-Host
    }
    $details = (Invoke-Native $rustup @('run', $toolchain, 'rustc', '-vV')) -join [Environment]::NewLine
    if ($details -notmatch "(?m)^host: $([regex]::Escape($hostTriple))\r?$") {
        throw "Rust must use the native MSVC host $hostTriple."
    }
    $installed = @(Invoke-Native $rustup @('component', 'list', '--toolchain', $toolchain, '--installed'))
    foreach ($component in $Configuration.components) {
        if (-not ($installed -match "^$([regex]::Escape($component))(-|$)")) {
            throw "Rust component '$component' is missing. Rerun setup without -CheckOnly."
        }
    }
    if ($Configuration.PSObject.Properties['targets']) {
        $targets = @(Invoke-Native $rustup @('target', 'list', '--toolchain', $toolchain, '--installed'))
        foreach ($target in $Configuration.targets) {
            if ($targets -notcontains $target) { throw "Rust target '$target' is missing. Rerun setup without -CheckOnly." }
        }
    }
    # Activate the native MSVC toolchain without changing rustup's global default.
    $env:RUSTUP_TOOLCHAIN = $toolchain
    Invoke-Native (Get-ApplicationPath 'cargo.exe') @("+$toolchain", '--version') | Out-Host
    return $toolchain
}

function Ensure-CargoTool {
    param([string]$Name, [string]$Toolchain, [string]$CargoHome)

    $command = "$Name.exe"
    if (-not (Get-ApplicationPath $command)) {
        if ($CheckOnly) { throw "$Name is missing. Rerun setup without -CheckOnly." }
        Write-Host "-- Installing $Name (Cargo helper)" -ForegroundColor Cyan
        Invoke-Native (Get-ApplicationPath 'cargo.exe') @(
            "+$Toolchain", 'install', '--locked', '--root', $CargoHome, $Name
        ) | Out-Host
    }
    if ($Name -like 'cargo-*') {
        $subcommand = $Name.Substring('cargo-'.Length)
        Invoke-Native (Get-ApplicationPath 'cargo.exe') @("+$Toolchain", $subcommand, '--version') | Out-Host
    } else {
        Invoke-Native (Get-ApplicationPath $command) @('--version') | Out-Host
    }
}

function Ensure-Pnpm {
    param([string]$Version)

    $command = Get-ApplicationPath 'pnpm.cmd'
    $current = if ($command) { (Invoke-Native $command @('--version')) -join '' } else { '' }
    if ($current.Trim() -ne $Version) {
        if ($CheckOnly) { throw "pnpm $Version is required by package.json. Rerun setup without -CheckOnly." }
        $npm = Get-ApplicationPath 'npm.cmd'
        if (-not $npm) { throw 'The Node.js installation did not provide npm.cmd.' }
        Invoke-Native $npm @('install', '--global', "pnpm@$Version", '--ignore-scripts', '--no-audit', '--no-fund') | Out-Host
        $prefix = (Invoke-Native $npm @('prefix', '--global')) -join ''
        Add-UserPath $prefix.Trim()
        $command = Get-ApplicationPath 'pnpm.cmd'
        if (-not $command) { throw 'pnpm.cmd was not found after installation. Check the npm global prefix.' }
        $current = (Invoke-Native $command @('--version')) -join ''
    }
    if ($current.Trim() -ne $Version) { throw "pnpm resolved to '$current', but package.json requires $Version." }
    Write-Host "-- pnpm $Version" -ForegroundColor DarkCyan
}

function Ensure-Bazelisk {
    param([string]$BinDirectory)

    if (-not (Get-ApplicationPath 'bazelisk.exe')) { Install-WinGetPackage 'Bazel.Bazelisk' }
    if (-not (Get-ApplicationPath 'bazelisk.exe')) { throw 'WinGet did not provide bazelisk.exe.' }
    $shim = Join-Path $BinDirectory 'bazel.cmd'
    # WinGet exposes bazelisk, whereas the repository recipes invoke bazel.
    # Keep the wrapper ASCII, including for non-ASCII Windows profile paths.
    $content = @('@echo off', 'bazelisk.exe %*', 'exit /b %errorlevel%', '') -join ([char]13 + [string][char]10)
    $existing = if (Test-Path -LiteralPath $shim) { Get-Content -LiteralPath $shim -Raw } else { '' }
    if ($existing -ne $content) {
        if ($CheckOnly) { throw 'The bazel.cmd wrapper is missing or outdated. Rerun setup without -CheckOnly.' }
        New-Item -ItemType Directory -Path $BinDirectory -Force | Out-Null
        Set-Content -LiteralPath $shim -Value $content -Encoding ASCII -NoNewline
    }
    Add-UserPath $BinDirectory
    # --version downloads the pinned Bazel if necessary, but never builds code.
    # CheckOnly checks the wrapper above to avoid downloading Bazel.
    if (-not $CheckOnly) {
        $version = (Invoke-Native $shim @('--version')) -join ''
        $expected = (Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.bazelversion') -Raw).Trim()
        if ($version.Trim() -ne "bazel $expected") { throw "Bazel version '$version' does not match .bazelversion ($expected)." }
        Write-Host "-- $version" -ForegroundColor DarkCyan
    }
}

function Initialize-WindowsDevelopment {
    if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }
    $script:Architecture = Get-WindowsArchitecture
    $script:WorkspaceRoot = Split-Path -Parent $PSScriptRoot
    $script:RepositoryRoot = Split-Path -Parent $script:WorkspaceRoot
    $package = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'package.json') -Raw | ConvertFrom-Json
    if ($package.packageManager -notmatch '^pnpm@(\d+\.\d+\.\d+)(?:\+|$)') {
        throw 'package.json must pin a pnpm version in packageManager.'
    }
    $pnpmVersion = $Matches[1]
    if ($package.engines.node -notmatch '^>=(\d+(?:\.\d+){0,2})$') { throw 'Unsupported Node.js engine requirement in package.json.' }
    $nodeVersion = $Matches[1]
    if ($nodeVersion -notmatch '\.') { $nodeVersion += '.0' }
    $nodeMinimum = [version]$nodeVersion
    $cargoHome = $env:CARGO_HOME
    if (-not $cargoHome) { $cargoHome = Join-Path $env:USERPROFILE '.cargo' }
    $cargoHome = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($cargoHome)
    $env:CARGO_HOME = $cargoHome
    $cargoBin = Join-Path $cargoHome 'bin'
    $devBin = Join-Path $env:LOCALAPPDATA 'Codex\dev-tools\bin'
    Update-SessionPath -Prepend @($cargoBin, $devBin)

    # Older rustup versions can install the active toolchain even for --version.
    # Only the explicit toolchain-install step is allowed to download Rust.
    Push-Location -LiteralPath $script:WorkspaceRoot
    $previousAutoInstall = $env:RUSTUP_AUTO_INSTALL
    try {
        $env:RUSTUP_AUTO_INSTALL = '0'
        Write-Host "==> Codex Windows development tools ($script:Architecture)" -ForegroundColor Cyan
        Ensure-Tool 'Git.Git' 'git.exe' -MinimumVersion '2.23'
        # CommandWithArgs, used by just-shell.py, became stable in PowerShell 7.5.
        Ensure-Tool 'Microsoft.PowerShell' 'pwsh.exe' -MinimumVersion '7.5' -ExtraArguments @('--installer-type', 'wix')
        # Python 3.11+ provides tomllib; reuse newer Python or install CI's 3.12.
        Ensure-Tool 'Python.Python.3.12' 'python.exe' -MinimumVersion '3.11' -ExtraArguments @('--scope', 'user')
        $rustConfiguration = Get-RustConfiguration
        $installation = Ensure-VisualStudio
        Ensure-Tool 'Rustlang.Rustup' 'rustup.exe' -MinimumVersion '1.28.1' -ExtraArguments @('--custom', '--default-toolchain none --profile minimal')
        Add-UserPath $cargoBin
        Ensure-Tool 'BurntSushi.ripgrep.MSVC' 'rg.exe'
        Ensure-Tool 'Casey.Just' 'just.exe' -MinimumVersion '1.51.0'
        Ensure-Tool 'Kitware.CMake' 'cmake.exe' -ExtraArguments @('--installer-type', 'wix')
        Ensure-Tool 'astral-sh.uv' 'uv.exe' -MinimumVersion '0.11.19'
        Ensure-Tool 'OpenJS.NodeJS.LTS' 'node.exe' -MinimumVersion $nodeMinimum -ExtraArguments @('--installer-type', 'wix')
        Ensure-LLVM
        Ensure-Pnpm $pnpmVersion
        Ensure-Bazelisk $devBin
        # Refresh PATH before entering VS, so compiler/linker paths stay first.
        Enter-VisualStudioEnvironment $installation
        $toolchain = Ensure-RustToolchain $rustConfiguration
        foreach ($tool in @('cargo-insta', 'cargo-nextest', 'dotslash')) {
            Ensure-CargoTool $tool $toolchain $cargoHome
        }
        Invoke-Native (Get-ApplicationPath 'just.exe') @('--list') | Out-Null
        if (-not $CheckOnly) {
            Invoke-Native (Get-ApplicationPath 'git.exe') @('-C', $script:RepositoryRoot, 'config', '--local', 'core.longpaths', 'true') | Out-Host
        }
        Write-Host '==> Development environment verified. Codex was not built.' -ForegroundColor Green
        Write-Host 'Use this PowerShell session, or rerun with -CheckOnly in a new session to activate MSVC.'
    } finally {
        Pop-Location
        [Environment]::SetEnvironmentVariable('RUSTUP_AUTO_INSTALL', $previousAutoInstall, 'Process')
    }
}

Initialize-WindowsDevelopment
