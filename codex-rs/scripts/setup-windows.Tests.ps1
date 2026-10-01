#Requires -Version 5.1
# Run with Pester 5: Invoke-Pester ./codex-rs/scripts/setup-windows.Tests.ps1
# Installers are mocked; the tests do not install software or change user settings.
Describe 'Windows development setup' {
    BeforeAll {
        $setupPath = Join-Path $PSScriptRoot 'setup-windows.ps1'
        $tokens = $null
        $parseErrors = $null
        $setupAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $setupPath, [ref]$tokens, [ref]$parseErrors
        )
        if ($parseErrors.Count) { throw ($parseErrors -join [Environment]::NewLine) }
        # Load the original function bodies with their source paths, without running
        # the entry point or requiring an installed development environment.
        $definitions = $setupAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $false)
        foreach ($definition in $definitions) {
            Set-Item -Path "Function:$($definition.Name)" -Value $definition.Body.GetScriptBlock()
        }
        $environmentNames = @(
            'Path', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_ARCHITEW6432', 'CARGO_HOME',
            'RUSTUP_TOOLCHAIN', 'RUSTUP_AUTO_INSTALL', 'LIBCLANG_PATH', 'CC', 'CXX',
            'VCToolsInstallDir', 'WindowsSdkDir', 'WindowsSDKVersion', 'INCLUDE', 'LIB',
            'LIBPATH', 'VCINSTALLDIR', 'WindowsSDKLibVersion', 'WindowsSdkBinPath',
            'WindowsLibPath', 'UniversalCRTSdkDir', 'UCRTVersion'
        )
    }

    BeforeEach {
        $script:CheckOnly = $false
        $script:Architecture = 'x64'
        $script:WorkspaceRoot = Split-Path -Parent $PSScriptRoot
        $script:RepositoryRoot = Split-Path -Parent $script:WorkspaceRoot
        $script:PSNativeCommandUseErrorActionPreference = $false
        $script:environmentBefore = @{}
        foreach ($name in $environmentNames) {
            $script:environmentBefore[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
    }

    AfterEach {
        foreach ($name in $environmentNames) {
            [Environment]::SetEnvironmentVariable($name, $script:environmentBefore[$name], 'Process')
        }
    }

    Describe 'Native command failure handling' {
        It 'throws on a nonzero native exit code instead of continuing' {
            { Invoke-Native $env:ComSpec @('/d', '/c', 'exit 7') } | Should -Throw '*exit code 7*'
        }

        It 'accepts only explicitly allowed already-installed exit codes' {
            { Invoke-Native $env:ComSpec @('/d', '/c', 'exit -1978335189') -SuccessExitCodes @(0, -1978335189) } |
                Should -Not -Throw
            { Invoke-Native $env:ComSpec @('/d', '/c', 'exit 8') -SuccessExitCodes @(0, -1978335189) } |
                Should -Throw '*exit code 8*'
        }

        It 'requires a restart instead of reporting a complete environment' {
            { Invoke-Native $env:ComSpec @('/d', '/c', 'exit 3010') } | Should -Throw '*Restart Windows*'
            { Invoke-Native $env:ComSpec @('/d', '/c', 'exit -1978334967') } | Should -Throw '*Restart Windows*'
        }
    }

    Describe 'Package installation and discovery' {
        It 'uses exact package IDs, the community source, and native architecture' {
            $script:Architecture = 'arm64'
            Mock Get-ApplicationPath { 'winget.exe' }
            Mock Get-ToolVersion { [version]'1.29.0' }
            Mock Invoke-Native {}
            Mock Update-SessionPath {}

            Install-WinGetPackage 'LLVM.LLVM'

            Should -Invoke Invoke-Native -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'winget.exe' -and
                $ArgumentList -contains 'LLVM.LLVM' -and
                $ArgumentList -contains '--exact' -and
                $ArgumentList -contains 'winget' -and
                $ArgumentList -contains 'arm64' -and
                $ArgumentList -contains '--silent' -and
                $ArgumentList -notcontains '--ignore-security-hash'
            }
        }

        It 'does not install in CheckOnly mode' {
            $script:CheckOnly = $true
            Mock Invoke-Native { throw 'Unexpected installer invocation' }
            { Install-WinGetPackage 'LLVM.LLVM' } | Should -Throw '*without -CheckOnly*'
            Should -Invoke Invoke-Native -Times 0 -Exactly
        }

        It 'reuses a supported installation' {
            Mock Get-ToolVersion { [version]'7.6.0' }
            Mock Install-WinGetPackage {}
            Ensure-Tool 'Microsoft.PowerShell' 'pwsh.exe' -MinimumVersion '7.4'
            Should -Invoke Install-WinGetPackage -Times 0 -Exactly
        }

        It 'upgrades an older installation and verifies the result' {
            $script:toolVersion = [version]'7.3'
            Mock Get-ToolVersion { $script:toolVersion }
            Mock Install-WinGetPackage { $script:toolVersion = [version]'7.6' }
            Ensure-Tool 'Microsoft.PowerShell' 'pwsh.exe' -MinimumVersion '7.4'
            Should -Invoke Install-WinGetPackage -Times 1 -Exactly
        }

        It 'rejects an installer success that leaves the command missing' {
            Mock Get-ToolVersion { $null }
            Mock Install-WinGetPackage {}
            { Ensure-Tool 'Casey.Just' 'just.exe' } | Should -Throw '*did not provide a usable*'
        }

        It 'ignores the Store Python alias and PowerShell wrapper scripts' {
            Mock Get-Command {
                @(
                    [pscustomobject]@{ Source = 'C:\Users\Test\AppData\Local\Microsoft\WindowsApps\python.exe' },
                    [pscustomobject]@{ Source = 'C:\Python312\python.exe' }
                )
            }
            Get-ApplicationPath 'python.exe' | Should -Be 'C:\Python312\python.exe'
            Should -Invoke Get-Command -ParameterFilter { $CommandType -eq 'Application' }
        }

        It 'refreshes PATH without writing a user setting in CheckOnly mode' {
            $script:CheckOnly = $true
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            Add-UserPath 'C:\Codex Test Tools'
            $env:Path.Split(';')[0] | Should -Be 'C:\Codex Test Tools'
            [Environment]::GetEnvironmentVariable('Path', 'User') | Should -Be $userPath
        }
    }

    Describe 'Windows architecture' {
        It 'detects native ARM64 even in an emulated x64 shell' {
            $env:PROCESSOR_ARCHITECTURE = 'AMD64'
            $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
            Get-WindowsArchitecture | Should -Be 'arm64'
        }

        It 'detects x64 Windows in a 32-bit shell' {
            $env:PROCESSOR_ARCHITECTURE = 'x86'
            $env:PROCESSOR_ARCHITEW6432 = 'AMD64'
            Get-WindowsArchitecture | Should -Be 'x64'
        }

        It 'rejects a 32-bit operating system' {
            $env:PROCESSOR_ARCHITECTURE = 'x86'
            $env:PROCESSOR_ARCHITEW6432 = ''
            { Get-WindowsArchitecture } | Should -Throw '*Unsupported Windows architecture*'
        }
    }

    Describe 'Visual Studio setup' {
        It 'reuses a complete VS 2022 or newer installation' {
            Mock Get-VSInstallation { 'C:\Existing VS' }
            Mock Install-WinGetPackage {}
            Mock Start-Process {}
            Ensure-VisualStudio | Should -Be 'C:\Existing VS'
            Should -Invoke Install-WinGetPackage -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'waits while adding components to an existing installation' {
            $script:vsReady = $false
            Mock Get-VSInstallation {
                param($RequiredComponents)
                if ($script:vsReady -or -not $RequiredComponents.Count) { 'C:\Existing VS' }
            }
            Mock Start-Process {
                $script:vsReady = $true
                [pscustomobject]@{ ExitCode = 0 }
            }
            Ensure-VisualStudio | Should -Be 'C:\Existing VS'
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $Wait -and $PassThru -and $WindowStyle -eq 'Hidden' -and
                $ArgumentList -contains '"C:\Existing VS"' -and
                $ArgumentList -contains 'Microsoft.VisualStudio.Component.Windows11SDK.26100' -and
                $ArgumentList -notcontains '--wait'
            }
        }

        It 'adds ARM64 tools only on ARM64 and waits for the x64 bootstrapper' {
            $script:Architecture = 'arm64'
            $script:vsReady = $false
            Mock Get-VSInstallation { if ($script:vsReady) { 'C:\VS' } }
            Mock Install-WinGetPackage { $script:vsReady = $true }
            Ensure-VisualStudio | Should -Be 'C:\VS'
            Should -Invoke Install-WinGetPackage -Times 1 -Exactly -ParameterFilter {
                $Architecture -eq 'x64' -and
                $ExtraArguments[1] -match '--wait' -and
                $ExtraArguments[1] -match 'VC.Tools.ARM64' -and
                $ExtraArguments[1] -notmatch 'ARM64EC|SDK.22000'
            }
        }

        It 'rejects a missing component after the installer returns success' {
            Mock Get-VSInstallation { $null }
            Mock Install-WinGetPackage {}
            { Ensure-VisualStudio } | Should -Throw '*did not install all required*'
        }

        It 'stops after a VS installer failure' {
            Mock Get-VSInstallation { param($RequiredComponents) if (-not $RequiredComponents.Count) { 'C:\VS' } }
            Mock Start-Process { [pscustomobject]@{ ExitCode = 1602 } }
            { Ensure-VisualStudio } | Should -Throw '*exit code 1602*'
        }

        It 'does not request installation in CheckOnly mode' {
            $script:CheckOnly = $true
            Mock Get-VSInstallation { $null }
            Mock Start-Process {}
            Mock Install-WinGetPackage {}
            { Ensure-VisualStudio } | Should -Throw '*components are missing*'
            Should -Invoke Start-Process -Times 0 -Exactly
            Should -Invoke Install-WinGetPackage -Times 0 -Exactly
        }
    }

    Describe 'Visual Studio environment activation' {
        BeforeEach {
            $script:testVS = Join-Path $TestDrive 'Visual Studio & Tools'
            $script:testVC = Join-Path $script:testVS 'VC\Tools\MSVC\Test'
            $script:testSDK = Join-Path $TestDrive 'Windows SDK'
            $tools = Join-Path $script:testVS 'Common7\Tools'
            $headers = Join-Path $script:testSDK 'Include\10.0.26100.0\um'
            $libraries = Join-Path $script:testSDK 'Lib\10.0.26100.0\um\x64'
            New-Item -ItemType Directory -Path $tools, $headers, $libraries -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $headers 'Windows.h'), (Join-Path $libraries 'kernel32.lib') -Force | Out-Null
            $lines = @(
                '@echo off',
                ('set "VCToolsInstallDir={0}\"' -f $script:testVC),
                ('set "WindowsSdkDir={0}\"' -f $script:testSDK),
                'set "WindowsSDKVersion=10.0.26100.0\"',
                'set "CODEX_SETUP_IGNORED=do-not-import"'
            )
            Set-Content -LiteralPath (Join-Path $tools 'VsDevCmd.bat') -Value $lines -Encoding ASCII
            Mock Get-ApplicationPath {
                param($Name)
                if ($Name -eq 'rc.exe') { Join-Path $script:testSDK "bin\10.0.26100.0\x64\$Name" }
                else { Join-Path $script:testVC "bin\Hostx64\x64\$Name" }
            }
        }

        It 'quotes batch paths with spaces and ampersands in the actual cmd.exe invocation' {
            $ignored = $env:CODEX_SETUP_IGNORED
            Enter-VisualStudioEnvironment $script:testVS
            $env:VCToolsInstallDir | Should -Be "$script:testVC\"
            $env:WindowsSdkDir | Should -Be "$script:testSDK\"
            $env:CODEX_SETUP_IGNORED | Should -Be $ignored
        }

        It 'rejects another link.exe that shadows MSVC' {
            Mock Get-ApplicationPath { 'C:\Git\usr\bin\link.exe' } -ParameterFilter { $Name -eq 'link.exe' }
            { Enter-VisualStudioEnvironment $script:testVS } | Should -Throw '*outside the selected Visual Studio*'
        }

        It 'rejects missing SDK libraries before reporting success' {
            Remove-Item -LiteralPath (Join-Path $script:testSDK 'Lib\10.0.26100.0\um\x64\kernel32.lib')
            { Enter-VisualStudioEnvironment $script:testVS } | Should -Throw '*SDK headers/libraries are missing*'
        }
    }

    Describe 'libclang architecture' {
        BeforeAll {
            function New-TestPE {
                param([string]$Path, [int]$Machine)
                $bytes = New-Object byte[] 128
                [BitConverter]::GetBytes([uint16]0x5A4D).CopyTo($bytes, 0)
                [BitConverter]::GetBytes([int]64).CopyTo($bytes, 60)
                [BitConverter]::GetBytes([uint32]0x00004550).CopyTo($bytes, 64)
                [BitConverter]::GetBytes([uint16]$Machine).CopyTo($bytes, 68)
                [IO.File]::WriteAllBytes($Path, $bytes)
            }
        }

        It 'accepts a native x64 DLL and rejects an ARM64 DLL on x64' {
            $path = Join-Path $TestDrive 'libclang.dll'
            New-TestPE $path 0x8664
            Test-LibclangArchitecture $path | Should -BeTrue
            New-TestPE $path 0xAA64
            Test-LibclangArchitecture $path | Should -BeFalse
        }

        It 'rejects an x64 DLL on ARM64' {
            $script:Architecture = 'arm64'
            $path = Join-Path $TestDrive 'libclang.dll'
            New-TestPE $path 0x8664
            Test-LibclangArchitecture $path | Should -BeFalse
            New-TestPE $path 0xAA64
            Test-LibclangArchitecture $path | Should -BeTrue
        }

        It 'rejects a missing DLL' {
            Test-LibclangArchitecture (Join-Path $TestDrive 'missing.dll') | Should -BeFalse
        }

        It 'rejects a truncated DLL' {
            $path = Join-Path $TestDrive 'broken.dll'
            [IO.File]::WriteAllBytes($path, [byte[]]@(0x4D, 0x5A))
            Test-LibclangArchitecture $path | Should -BeFalse
        }
    }

    Describe 'Pinned tools and helper installation' {
        It 'reads Rust configuration with the actual Python TOML parser' {
            $script:WorkspaceRoot = Join-Path $TestDrive 'Rust workspace'
            New-Item -ItemType Directory -Path $script:WorkspaceRoot | Out-Null
            $toml = @(
                '[toolchain]',
                '# Exercise comments and a multiline array with the real parser.',
                'channel = "1.99.3"',
                'components = [',
                '    "clippy",',
                '    "rustfmt",',
                '    "rust-src",',
                ']'
            )
            Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot 'rust-toolchain.toml') -Value $toml -Encoding ASCII
            $configuration = Get-RustConfiguration
            $configuration.channel | Should -Be '1.99.3'
            $configuration.components | Should -Contain 'clippy'
            $configuration.components | Should -Contain 'rustfmt'
            $configuration.components | Should -Contain 'rust-src'
        }

        It 'installs the configured components for the native MSVC host' {
            $script:Architecture = 'arm64'
            Mock Get-ApplicationPath { param($Name) $Name }
            Mock Invoke-Native {
                param($FilePath, $ArgumentList)
                if ($ArgumentList[0] -eq 'run') { 'host: aarch64-pc-windows-msvc' }
                elseif ($ArgumentList[0] -eq 'component') { 'clippy-aarch64-pc-windows-msvc'; 'rust-src' }
            }
            $configuration = [pscustomobject]@{ channel = '1.95.0'; components = @('clippy', 'rust-src') }
            Ensure-RustToolchain $configuration | Should -Be '1.95.0-aarch64-pc-windows-msvc'
            Should -Invoke Invoke-Native -ParameterFilter {
                $ArgumentList[0] -eq 'toolchain' -and $ArgumentList -contains '1.95.0-aarch64-pc-windows-msvc' -and
                $ArgumentList -contains 'clippy' -and $ArgumentList -contains 'rust-src'
            }
            Should -Invoke Invoke-Native -Times 0 -Exactly -ParameterFilter { $ArgumentList -contains 'default' }
        }

        It 'rejects a GNU or emulated Rust host' {
            Mock Get-ApplicationPath { param($Name) $Name }
            Mock Invoke-Native { 'host: x86_64-pc-windows-gnu' }
            $configuration = [pscustomobject]@{ channel = '1.95.0'; components = @('rustfmt') }
            { Ensure-RustToolchain $configuration } | Should -Throw '*native MSVC host*'
        }

        It 'honors CARGO_HOME and uses the pinned toolchain for Cargo helpers' {
            Mock Get-ApplicationPath { param($Name) if ($Name -eq 'cargo.exe') { $Name } }
            Mock Invoke-Native {}
            Ensure-CargoTool 'cargo-nextest' '1.95.0-x86_64-pc-windows-msvc' 'C:\Custom Cargo Home'
            Should -Invoke Invoke-Native -ParameterFilter {
                $ArgumentList -contains '+1.95.0-x86_64-pc-windows-msvc' -and
                $ArgumentList -contains 'install' -and $ArgumentList -contains '--locked' -and
                $ArgumentList -contains 'C:\Custom Cargo Home'
            }
            Should -Invoke Invoke-Native -ParameterFilter {
                $ArgumentList -contains 'nextest' -and $ArgumentList -contains '--version'
            }
        }

        It 'uses npm.cmd and pnpm.cmd without invoking blocked PowerShell shims' {
            $script:pnpmReady = $false
            Mock Get-ApplicationPath {
                param($Name)
                if ($Name -eq 'npm.cmd' -or ($Name -eq 'pnpm.cmd' -and $script:pnpmReady)) { $Name }
            }
            Mock Invoke-Native {
                param($FilePath, $ArgumentList)
                if ($ArgumentList -contains 'install') { $script:pnpmReady = $true }
                elseif ($ArgumentList -contains 'prefix') { 'C:\npm prefix' }
                else { '10.34.5' }
            }
            Mock Add-UserPath {}
            Ensure-Pnpm '10.34.5'
            Should -Invoke Invoke-Native -ParameterFilter {
                $FilePath -eq 'npm.cmd' -and $ArgumentList -contains 'pnpm@10.34.5' -and
                $ArgumentList -contains '--ignore-scripts'
            }
        }

        It 'checks an existing Bazel wrapper without launching Bazel or downloading it' {
            $script:CheckOnly = $true
            $bin = Join-Path $TestDrive 'bin'
            New-Item -ItemType Directory -Path $bin | Out-Null
            $content = @('@echo off', 'bazelisk.exe %*', 'exit /b %errorlevel%', '') -join ([char]13 + [string][char]10)
            Set-Content -LiteralPath (Join-Path $bin 'bazel.cmd') -Value $content -Encoding ASCII -NoNewline
            Mock Get-ApplicationPath { 'bazelisk.exe' }
            Mock Add-UserPath {}
            Mock Invoke-Native {}
            Ensure-Bazelisk $bin
            Should -Invoke Invoke-Native -Times 0 -Exactly
        }
    }

    Describe 'Setup orchestration' {
        BeforeEach {
            Mock Get-Content {
                '{"packageManager":"pnpm@10.40.2+sha512.test","engines":{"node":">=24.1"}}'
            } -ParameterFilter { $LiteralPath -like '*\package.json' }
            Mock Ensure-Tool {}
            Mock Ensure-VisualStudio { 'C:\VS' }
            Mock Add-UserPath {}
            Mock Update-SessionPath {}
            Mock Ensure-LLVM {}
            Mock Ensure-Pnpm {}
            Mock Ensure-Bazelisk {}
            Mock Enter-VisualStudioEnvironment {}
            Mock Ensure-RustToolchain { '1.95.0-x86_64-pc-windows-msvc' }
            Mock Ensure-CargoTool {}
            Mock Get-ApplicationPath { param($Name) $Name }
            Mock Invoke-Native {}
            Mock Get-RustConfiguration { [pscustomobject]@{ channel = '1.95.0'; components = @('clippy', 'rustfmt', 'rust-src') } }
        }

        It 'uses repository configuration, restores the directory, and never builds Codex' {
            $before = (Get-Location).Path
            Initialize-WindowsDevelopment
            (Get-Location).Path | Should -Be $before
            Should -Invoke Ensure-Pnpm -ParameterFilter { $Version -eq '10.40.2' }
            Should -Invoke Ensure-Tool -ParameterFilter {
                $Id -eq 'OpenJS.NodeJS.LTS' -and $MinimumVersion -eq [version]'24.1'
            }
            Should -Invoke Invoke-Native -Times 0 -Exactly -ParameterFilter { $ArgumentList -contains 'build' }
            Should -Invoke Invoke-Native -ParameterFilter {
                $ArgumentList -contains 'core.longpaths' -and $ArgumentList -contains '--local'
            }
        }

        It 'disables implicit Rust downloads and restores the caller setting after failure' {
            $env:RUSTUP_AUTO_INSTALL = 'custom'
            Mock Ensure-Tool {
                $env:RUSTUP_AUTO_INSTALL | Should -Be '0'
                throw 'Test failure'
            }
            $before = (Get-Location).Path
            { Initialize-WindowsDevelopment } | Should -Throw '*Test failure*'
            $env:RUSTUP_AUTO_INSTALL | Should -Be 'custom'
            (Get-Location).Path | Should -Be $before
        }

        It 'resolves a relative CARGO_HOME before changing into the workspace' {
            Push-Location -LiteralPath $TestDrive
            try {
                $env:CARGO_HOME = 'Custom Cargo Home'
                $expected = Join-Path $TestDrive 'Custom Cargo Home'
                Initialize-WindowsDevelopment
                $env:CARGO_HOME | Should -Be $expected
                Should -Invoke Ensure-CargoTool -ParameterFilter { $CargoHome -eq $expected }
            } finally {
                Pop-Location
            }
        }

        It 'does not write Git settings or allow implicit Rust downloads in CheckOnly mode' {
            $script:CheckOnly = $true
            Mock Ensure-Tool { $env:RUSTUP_AUTO_INSTALL | Should -Be '0' }
            Initialize-WindowsDevelopment
            Should -Invoke Invoke-Native -Times 0 -Exactly -ParameterFilter { $ArgumentList -contains 'config' }
        }
    }
}
