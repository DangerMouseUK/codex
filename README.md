# Codex CLI - Windows and PowerShell Development Fork

An independent fork of [OpenAI's Codex CLI](https://github.com/openai/codex) focused on improving **native Windows and PowerShell compatibility**. Our goal is reliable command execution, developer tooling, and everyday Windows workflows, with suitable improvements potentially contributed upstream.

**Status: active development.** This fork builds on OpenAI's existing native Windows support. Full native compatibility is a goal with explicit validation milestones; it is not yet a completed claim.

<!-- Begin ToC -->

- [Current status](#current-status)
- [Windows development quickstart](#windows-development-quickstart)
- [What we are improving](#what-we-are-improving)
- [Roadmap](#roadmap)
- [Reporting Windows issues](#reporting-windows-issues)
- [Upstream relationship](#upstream-relationship)
- [Documentation and license](#documentation-and-license)

<!-- End ToC -->

## Current status

| Area                    | Available today                                                                                  | Validation or work still needed                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| Native execution        | Upstream Windows shell discovery, PowerShell parsing, ConPTY, and native sandbox implementations | End-to-end coverage of the fork's intended Windows workflows             |
| Developer setup         | Refined setup script with mocked installer tests under Windows PowerShell 5.1 and PowerShell 7   | Clean-machine installation, reruns, and actual ARM64 validation          |
| Fork CI                 | Standard GitHub-hosted Windows, Linux, and macOS checks, with focused native Rust coverage       | Full-workspace dependency setup and reliable full-suite results          |
| PowerShell improvements | Defined milestones and completion criteria                                                       | Shell context, syntax quality, quoting, environments, and terminal fixes |
| Fork releases           | Source checkout                                                                                  | Packaged x64/ARM64 releases and install/update validation                |

The [first full-workspace run after our upstream sync](https://github.com/DangerMouseUK/codex/actions/runs/37668380554) failed during native compilation: macOS could not locate GStreamer, Linux could not locate GLib, and Windows could not run the required pkg-config probe for GLib. Passing focused checks does not establish full-workspace compatibility. These dependency gaps are tracked in M1.

## Windows development quickstart

This fork currently has no published binary releases. The steps below set up a source checkout for development. You need Git and WinGet available; setup can start from Windows PowerShell 5.1.

Read the [Windows setup guide](./docs/install.md#windows-development-powershell) for the tools installed and environment changes before running setup. Machine-wide installers may request UAC approval.

```powershell
git clone https://github.com/DangerMouseUK/codex.git
Set-Location codex
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\codex-rs\scripts\setup-windows.ps1
```

Setup installs and verifies development tools. It does not build Codex, run its tests, or install workspace JavaScript/Python dependencies. The temporary execution-policy override applies to that PowerShell process.

Open PowerShell 7.5 or newer in the checkout, then activate and check the environment before explicitly building and running:

```powershell
& .\codex-rs\scripts\setup-windows.ps1 -CheckOnly
Set-Location .\codex-rs
cargo build --locked -p codex-cli --bin codex
cargo run --locked -p codex-cli --bin codex -- "explain this codebase to me"
```

`-CheckOnly` does not install tools or change persistent settings. Fresh-machine builds and optional feature dependencies are still being validated; see the status above and [build instructions](./docs/install.md) for the current development path.

The Windows and PowerShell workflow is our primary focus. WSL and Git Bash remain explicit choices for workflows that need them. Our target is to complete ordinary Windows tasks without silently switching shells or requiring a Linux environment.

## What we are improving

- **Shell awareness:** tell the agent which PowerShell executable and version will actually execute its commands.
- **Command correctness:** improve syntax, quoting, native arguments, pipelines, output encoding, errors, and exit codes.
- **Windows integration:** make paths, tool shims, MSVC, virtual environments, MCP servers, hooks, and SDK execution predictable.
- **Sandbox access:** support permitted Windows workflows while preserving filesystem, network, and approval boundaries.
- **Terminal behavior:** improve interactive input, clipboard handling, streaming, Ctrl-C, and process cleanup.
- **Native development:** provide repeatable setup, builds, tests, and packaging on x64 and ARM64.

These are work areas, not a list of completed fixes. Windows improvements should preserve macOS and Linux behavior and reuse the existing cross-platform architecture.

## Roadmap

The [Windows native compatibility roadmap](./docs/windows-native-roadmap.md) contains the full checklists, dependencies, code areas, and acceptance criteria.

| Milestones | Outcome                                                                       |
| ---------- | ----------------------------------------------------------------------------- |
| M0-M1      | Measured Windows baseline, reproducible failures, and reliable native CI      |
| M2-M3      | Accurate shell context and dependable PowerShell execution                    |
| M4-M6      | Predictable environments, sandbox/filesystem access, and terminal interaction |
| M7-M8      | Native contributor workflows and parity for advertised Windows features       |
| M9-M10     | Tested packages, actual ARM64 execution, and release acceptance               |

The next work is **M0 and M1**: establish the support matrix and regression fixtures, then resolve full-CI dependency setup. The milestones remain open until their completion criteria have evidence.

The proposed primary target is Windows 11 with PowerShell 7 on x64 and ARM64. Windows PowerShell 5.1 bootstrap/fallback behavior, terminal support, and optional features have separate validation requirements in the roadmap.

## Reporting Windows issues

Report fork-specific problems in [this fork's issue tracker](https://github.com/DangerMouseUK/codex/issues). Search existing issues first and include:

- Windows version and whether the machine is x64 or ARM64.
- PowerShell version and edition, plus the executable being used.
- Terminal application, Codex version, and fork commit where available.
- Minimal reproduction steps, the command that failed, and expected versus actual behavior.
- Sandbox mode, relevant tool versions, and redacted errors or logs.

Please distinguish native Windows execution from WSL or Git Bash. Remove credentials and other sensitive information from reports. For security vulnerabilities, follow the [security policy](./SECURITY.md).

See the [contributing guide](./docs/contributing.md) for the fork's focus and OpenAI's separate upstream contribution policy.

## Upstream relationship

Codex CLI is developed by OpenAI. This fork tracks [openai/codex](https://github.com/openai/codex) while developing focused Windows and PowerShell improvements. We aim to keep changes reviewable and potentially share suitable fixes, tests, and root-cause analyses with OpenAI over time, subject to its contribution policy.

OpenAI's installers, releases, and the npm package `@openai/codex` install **official upstream Codex**, not this fork. For official installation and product usage, see the [upstream README](https://github.com/openai/codex#readme) and [Codex documentation](https://developers.openai.com/codex).

## Documentation and license

- [Windows setup and build instructions](./docs/install.md#windows-development-powershell)
- [Windows native compatibility roadmap](./docs/windows-native-roadmap.md)
- [Fork CI coverage](./.github/workflows/README.md#forks)
- [Contributing and reporting problems](./docs/contributing.md)
- [Official Codex documentation](https://developers.openai.com/codex)

This fork retains the upstream [Apache-2.0 License](./LICENSE) and [notices](./NOTICE). Credit for Codex and its existing platform support belongs to OpenAI and the project's contributors.
