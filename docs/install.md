## Installing & building

### System requirements

| Requirement                 | Details                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| Operating systems           | macOS 12+, Ubuntu 20.04+/Debian 10+, or Windows 11 (native PowerShell or WSL2) |
| Git (optional, recommended) | 2.23+ for built-in PR helpers                                                  |
| RAM                         | 4-GB minimum (8-GB recommended)                                                |

### DotSlash

The GitHub Release also contains a [DotSlash](https://dotslash-cli.com/) file for the Codex CLI named `codex`. Using a DotSlash file makes it possible to make a lightweight commit to source control to ensure all contributors use the same version of an executable, regardless of what platform they use for development.

### Build from source

#### Windows development (PowerShell)

From a checkout of this repository, run the setup script as your normal Windows
user. Windows PowerShell 5.1 can bootstrap the environment; development recipes
use PowerShell 7.5 or newer. Machine-wide installers may request UAC elevation.

```powershell
& .\codex-rs\scripts\setup-windows.ps1
```

The script supports x64 and ARM64 Windows and requires [WinGet 1.6 or newer](https://learn.microsoft.com/windows/package-manager/winget/).
It can be invoked from any directory by providing the path to the script. If
execution policy blocks it, use a separate process without changing your saved
execution policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\codex-rs\scripts\setup-windows.ps1
```

Setup installs and verifies these tools, reusing suitable existing installations:

| Tools                                   | Installation source                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------------------- |
| Git, PowerShell 7                       | `Git.Git`, `Microsoft.PowerShell` via WinGet                                          |
| MSVC and Windows SDK                    | Existing Visual Studio 2022 or newer, or `Microsoft.VisualStudio.2022.BuildTools`     |
| Rust and workspace components           | `Rustlang.Rustup`; version/components from `codex-rs/rust-toolchain.toml`             |
| Python 3.11+                            | Existing Python, or `Python.Python.3.12` via WinGet                                   |
| ripgrep, just, CMake, LLVM/libclang, uv | `BurntSushi.ripgrep.MSVC`, `Casey.Just`, `Kitware.CMake`, `LLVM.LLVM`, `astral-sh.uv` |
| Node.js and pnpm                        | `OpenJS.NodeJS.LTS`; Node minimum and exact pnpm version from `package.json`          |
| Bazel                                   | `Bazel.Bazelisk`; downloads the version in `.bazelversion`                            |
| Snapshot/test helpers and DotSlash      | `cargo install --locked cargo-insta cargo-nextest dotslash`                           |

The Visual Studio installation includes the x64 tools and Windows SDK 26100;
ARM64 machines also receive the ARM64 tools. Setup waits for installation and
checks the actual compiler, linker, SDK headers/libraries, and native libclang
architecture. If an installer requires a restart, restart Windows and rerun the
script. Failures stop setup instead of reporting success.

Setup does **not** build Codex, run tests, or install workspace JavaScript/Python
dependencies. Cargo may compile the three helper tools during their installation.
The script adds Cargo, LLVM, npm's global prefix when needed, and a user-owned
`bazel.cmd` wrapper to your user PATH. The wrapper lives in
`%LOCALAPPDATA%\Codex\dev-tools\bin` and invokes Bazelisk so `.bazelversion` is
honored. Git long-path support is enabled only for this checkout. Rust's global
default toolchain and persistent `CC`/`CXX` settings are not changed.

Use the same PowerShell session for development. If you launched setup through
`powershell.exe -File`, open PowerShell 7 afterward. In a new session, activate
and verify the installed environment without installing or changing saved
settings:

```powershell
& .\codex-rs\scripts\setup-windows.ps1 -CheckOnly
```

`-CheckOnly` does not download Rust or Bazel. It checks the Bazelisk executable
and wrapper without launching Bazel. The MSVC environment, `LIBCLANG_PATH`, and
native Rust toolchain are selected for the current process only.

Build and test explicitly when ready:

```powershell
Set-Location .\codex-rs
cargo build -p codex-cli
cargo run --bin codex -- "explain this codebase to me"
just test -p codex-tui
```

Native voice/Cygwin build inputs have their own CI setup in
`.github/scripts/setup-voice-windows.ps1`; they are not installed by the standard
CLI development setup.

#### macOS, Linux, and WSL2

```bash
# Clone the repository and navigate to the root of the Cargo workspace.
git clone https://github.com/openai/codex.git
cd codex/codex-rs

# Install the Rust toolchain, if necessary.
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup component add rustfmt
rustup component add clippy
# Install helper tools used by the workspace justfile:
cargo install --locked just
# DotSlash fetches pinned development tools such as buildifier on first use.
cargo install --locked dotslash
# Install nextest for the `just test` helper.
cargo install --locked cargo-nextest

# Build Codex.
cargo build

# Launch the TUI with a sample prompt.
cargo run --bin codex -- "explain this codebase to me"

# After making changes, use the root justfile helpers (they default to codex-rs):
just fmt
just fix -p <crate-you-touched>

# Run the relevant tests (project-specific is fastest), for example:
just test -p codex-tui
# `just test` runs the test suite via nextest:
just test
# Avoid `--all-features` for routine local runs because it increases build
# time and `target/` disk usage by compiling additional feature combinations.
```

## Tracing / verbose logging

Codex is written in Rust, so it honors the `RUST_LOG` environment variable to configure its logging behavior.

The TUI records diagnostics in bounded local stores by default. Set `log_dir` explicitly to enable a plaintext TUI log for a run:

```bash
codex -c log_dir=./.codex-log
tail -F ./.codex-log/codex-tui.log
```

The non-interactive mode (`codex exec`) defaults to `RUST_LOG=error`, but messages are printed inline, so there is no need to monitor a separate file.

See the Rust documentation on [`RUST_LOG`](https://docs.rs/env_logger/latest/env_logger/#enabling-logging) for more information on the configuration options.
