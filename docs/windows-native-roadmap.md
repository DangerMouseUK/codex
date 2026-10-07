## Windows native compatibility roadmap

This fork aims to make native Windows and PowerShell a reliable default for Codex CLI. A Windows user should be able to install Codex, work on a repository, run tools, review changes, and develop Codex itself without needing WSL for ordinary Windows workflows. Suitable improvements may eventually be shared with OpenAI under its contribution policy.

This is a milestone plan. Only the existing foundations listed below are implemented; milestone checkboxes remain open until their completion criteria have evidence. Start with M0 and M1, then complete M2 and M3 before expanding into the remaining areas.

**Proposed support contract**

| Area                   | Target                                                                                                                                              |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Primary platform       | Supported Windows 11 releases, native x64 and ARM64 execution                                                                                       |
| Primary shell          | Stable PowerShell 7; record the minimum supported runtime version in M0. Existing development recipes require 7.5 or newer.                         |
| Compatibility shell    | Windows PowerShell 5.1 for bootstrap and a documented runtime fallback with compatible syntax; no assumption that it supports PowerShell 7 features |
| Terminals              | Windows Terminal and the VS Code integrated terminal as primary targets; console host and redirected/headless execution tested separately           |
| Permissions            | Normal user operation, with explicit administrator-approved sandbox setup where required; retain native filesystem and network boundaries           |
| Linux tooling          | WSL and Git Bash remain explicit user choices. Core Windows workflows must not silently switch into them.                                           |
| Repository development | Native MSVC builds and PowerShell recipes, with declared dependencies for optional components                                                       |
| Scope                  | CLI, executor, app-server interfaces, local tools, supported Windows extensions, SDK integration, and contributor workflows                         |

Remote Linux executors still need Linux commands. Shell information and instructions must describe the environment executing the command, rather than assuming every executor has the local Windows host's shell. The proprietary desktop application and OpenAI-hosted cloud infrastructure are outside this repository's control.

OpenAI already documents native Windows execution and sandboxing. WSL is an option for Linux tooling or workflows that need it, rather than a prerequisite for all Windows access. Our work builds on that native implementation. See the [official Windows sandbox documentation](https://learn.chatgpt.com/docs/windows/windows-sandbox).

**Existing foundations and observed gaps**

- [Shell discovery](../codex-rs/shell-command/src/shell_detect.rs) already prefers PowerShell on Windows, tries `pwsh` before Windows PowerShell, and handles sandbox-incompatible Store PowerShell paths. Its fallback behavior and the treatment of an explicitly requested shell path need coverage before changing them.
- [Environment context](../codex-rs/core/src/context/world_state/environment.rs) can expose a bounded PowerShell version, but [`powershell_shell_version`](../codex-rs/features/src/lib.rs) is under development and disabled by default. It currently applies to a single local environment.
- [Shell tool descriptions](../codex-rs/core/src/tools/handlers/shell_spec.rs) include Windows safety guidance, but describe `login` in POSIX terms. [Execution arguments](../codex-rs/core/src/shell.rs) use that option to control PowerShell profile loading.
- PowerShell parsing, UTF-8 output handling, ConPTY, process cleanup, Windows sandboxing, MCP program resolution, and terminal handling already exist. Preserve and extend these implementations rather than introducing parallel Windows execution stacks.
- PowerShell shell-state snapshots are explicitly unsupported in the [core](../codex-rs/core/src/shell_snapshot.rs), [capture helper](../codex-rs/shell-command/src/shell_snapshot_capture.rs), and [executor](../codex-rs/exec-server/src/shell_snapshot.rs). Decide what environment restoration Windows workflows actually need before adding snapshot support.
- The refined Windows setup script and hosted fork CI are in place. Installer tests are mocked; fresh-machine installation and ARM64 behavior still need direct validation.
- The first full-workspace run after the upstream sync exposed dependency setup gaps: [macOS](https://github.com/DangerMouseUK/codex/actions/runs/37668380554/job/112957787969) failed to locate GStreamer 1.28 or newer, [Linux](https://github.com/DangerMouseUK/codex/actions/runs/37668380554/job/112957788135) failed to locate GLib, and [Windows](https://github.com/DangerMouseUK/codex/actions/runs/37668380554/job/112957788005) could not run the required pkg-config probe for GLib. Those jobs failed during compilation, before tests.
- [Windows voice setup](../.github/scripts/setup-voice-windows.ps1) uses a pinned Cygwin dependency chain. Core CLI support and full repository/feature support must be tracked separately until that dependency is addressed.

**Milestone sequence**

| Milestone | Outcome                                                         | Depends on                     |
| --------- | --------------------------------------------------------------- | ------------------------------ |
| M0        | Measured Windows baseline and agreed support matrix             | None                           |
| M1        | Trustworthy native CI and regression fixtures                   | M0                             |
| M2        | Correct shell selection and model-visible Windows capabilities  | M1                             |
| M3        | Correct PowerShell commands, arguments, output, and exit status | M2                             |
| M4        | Predictable environments and local tool integrations            | M3                             |
| M5        | Reliable Windows filesystems, approvals, and sandbox access     | M3; integrate with M4          |
| M6        | Reliable terminal interaction and process lifecycle             | M3; integrate with M5          |
| M7        | Native contributor setup, builds, and maintenance recipes       | M1; validate against M3 and M4 |
| M8        | Native parity for advertised Windows features and services      | M4, M5, M6, M7                 |
| M9        | Tested Windows packages and ARM64 delivery                      | M5, M6, M7, M8                 |
| M10       | Release acceptance and sustainable upstream maintenance         | M0 through M9                  |

Dependencies describe the order of work, not permission to delegate. Each milestone should land through small changes with relevant checks, rather than a single Windows rewrite.

**M0 Establish the Windows baseline**

- [ ] Confirm the support contract above, including PowerShell runtime versions, Windows versions, and which optional features the fork will advertise.
- [ ] Reproduce reported problems using the upstream baseline and the fork on the same Windows machine or disposable VM. Distinguish model syntax errors, execution bugs, sandbox denials, missing project tools, and developer build problems.
- [ ] Create a Windows compatibility matrix recording each feature as passing, failing, unsupported, or untested. Include CLI, `codex exec`, app-server, MCP, hooks, plugins, SDKs, sandbox modes, terminal interaction, and optional voice/services.
- [ ] Define an initial suite of at least 50 representative tasks covering file inspection and edits, Git, Node/pnpm, Python/uv, Rust/MSVC, .NET, tests, background processes, and local MCP. Use tools installed in each fixture; missing project dependencies must produce an actionable result.
- [ ] Give each reproducible failure an identifier, minimal fixture, expected result, affected versions, severity, and proposed milestone. Record cold/warm startup and command latency for later comparisons.

Completion requires a checked-in matrix, reproducible examples for the priority failures, an agreed support contract, and a runnable baseline task suite. Do not treat an untested feature as a confirmed defect.

**M1 Establish reliable native CI**

- [ ] Resolve the full-workspace dependency failures using upstream build requirements, including the required GStreamer/GLib versions and platform-specific media inputs. Verify all three hosted OS results.
- [ ] Keep a fast Windows lane for shell-command, PTY, paths, and focused executor/core tests. Maintain full native workspace checks for relevant changes and release candidates, with a separately identified lane for heavier feature dependencies if needed.
- [ ] Run PowerShell 7 and Windows PowerShell 5.1 explicitly. Tests that select the first available PowerShell executable do not establish coverage of both.
- [ ] Run essential Windows fixtures with WSL and Git Bash unavailable to Codex. Retain required Windows tooling on PATH; Git may be installed without exposing its Bash as a default execution dependency.
- [ ] Record test discovery, execution, and skip reasons. Required Windows tests must fail when their prerequisites are missing instead of returning early and appearing green.
- [ ] Add deterministic executor and mock-model integration fixtures using existing test harnesses. Keep real model evaluations separate from ordinary PR checks so credentials and model variability do not obscure runtime failures.
- [ ] Make the required CI gate enforce these lanes. Configure fork branch rules through a separately authorized repository settings change.

Completion requires two consecutive full runs on the same revision without failure or unexplained skips, including one without restored build caches. Logs must distinguish dependency setup, compilation, linting, and test failures. Platform capabilities unavailable on a hosted runner need an explicit additional test environment, not an unconditional pass.

**M2 Make the selected shell and its capabilities explicit**

- [ ] Use the existing shell discovery and executor capability paths to carry shell family, executable, version/edition, platform, architecture, and profile mode for the environment executing each command.
- [ ] Validate the existing version feature before enabling or extending it. Version discovery must be bounded, cached appropriately, and must not execute arbitrary PATH-selected programs merely to collect diagnostics.
- [ ] Preserve an explicitly configured executable where safe and supported. Explain sandbox-related fallback, particularly Store, portable, and Windows PowerShell installations, and keep context synchronized with the shell actually launched.
- [ ] Give the model concise PowerShell-specific guidance for supported syntax, paths, environment variables, native executables, exit status, and cmdlet aliases. Describe profile loading accurately instead of using only `-l/-i` terminology.
- [ ] Default Windows commands to PowerShell while honoring explicit requests for another shell. Never automatically rewrite a Windows command into Bash or WSL to conceal a compatibility failure.
- [ ] Cover resumed chats, multiple environments, app-server clients, and remote Linux execution so stale or host-local shell information does not select the wrong syntax.

Completion requires deterministic tests showing that shell metadata and tool descriptions match actual execution in every supported shell/environment combination. Agent evaluation must show fewer wrong-shell commands than the recorded baseline. Reuse the existing protocol where possible and version any necessary protocol extension.

Primary code areas: `shell-command/src/shell_detect.rs`, `features/src/lib.rs`, `core/src/context/world_state/environment.rs`, `core/src/tools/handlers/shell_spec.rs`, and executor capability discovery.

**M3 Make PowerShell command execution dependable**

- [ ] Specify and test argument handling for spaces, empty arguments, Unicode, apostrophes, quotes, backticks, `$`, parentheses, trailing backslashes, and literal wildcard characters. Include executable and repository paths containing these characters.
- [ ] Keep structured executable arguments structured. Test `.exe`, `.cmd`, `.bat`, and `.ps1` launch behavior explicitly; use a command interpreter only where the target requires it.
- [ ] Cover PowerShell pipelines, multiline scripts, here-strings, redirection, call operators, native programs, cmdlets, and supported version differences. Teach the model to use explicit PowerShell forms where aliases have conflicting native meanings.
- [ ] Define observable failure semantics for native nonzero exits, missing commands, terminating errors, and non-terminating cmdlet errors. Test `$LASTEXITCODE` and `$?` interactions without globally changing users' preferences or silently rewriting arbitrary scripts.
- [ ] Validate stdin, separate stdout/stderr in pipe mode, terminal output, CRLF, Unicode, and file encodings under both shell versions. Distinguish console output encoding from file-writing encoding.
- [ ] Cover timeouts, cancellation, closed stdin, large output, and native children. Extend existing PTY and process abstractions rather than adding an unrelated launcher.
- [ ] Improve PowerShell policy parsing only for syntax whose semantics are understood. Dynamic or unsupported syntax must remain conservative; broader syntax support must not create approval bypasses or execute commands during analysis.

Completion requires exact argument round trips, expected file bytes and output, and correct process status for all deterministic fixtures on x64 and eventually ARM64. Parser and execution tests must agree on the commands being evaluated. A supported PowerShell script must not need a Bash wrapper.

Primary code areas: `shell-command/src/powershell.rs`, `shell-command/src/command_safety/`, `core/src/shell.rs`, `core/src/tools/runtimes/`, `exec-server/src/local_process.rs`, and `utils/pty/src/`.

**M4 Make environments and tool integrations predictable**

- [ ] Define profile loading and environment inheritance explicitly. Test PATH/Path casing, PATHEXT, user and machine environment values, installed tool shims, and environment filtering.
- [ ] Verify native Node/npm/pnpm, Python/uv/virtual environments, Rust/MSVC, .NET, Git/SSH, MCP stdio servers, hooks, and SDK-launched processes. Cover tools installed beneath user profiles and directories containing spaces.
- [ ] Decide whether environment capture is needed for MSVC initialization and project activation. If added, capture only the state required by the workflow under the existing permission and secret-filtering rules. Do not serialize an entire interactive session or introduce uncontrolled cross-task state.
- [ ] Cover server startup, shutdown, restart, child cleanup, loopback access, proxy settings, Windows certificate handling, and permitted credential integration without weakening existing authentication or network policies.
- [ ] Extend the existing `codex doctor` checks with redacted Windows shell, PATH, sandbox, terminal, and tool-resolution diagnostics. Preserve its read-mostly behavior and avoid automatic installs or repairs.

Completion requires the representative tool integrations to run natively, resolve the intended executable, respect configured environment boundaries, and shut down cleanly. Environments used by simultaneous tasks must stay isolated, and diagnostics must identify missing prerequisites without exposing secrets.

Primary code areas: `config/src/shell_environment_policy.rs`, `exec-server/src/environment.rs`, shell snapshot modules, `rmcp-client/src/program_resolver.rs`, hooks, SDK launchers, and `cli/src/doctor/`.

**M5 Make filesystem and sandbox behavior reliable**

- [ ] Test local drives, drive-root paths, UNC paths, extended-length paths, spaces, Unicode, case differences, junctions, symbolic links, and read-only or locked files. Use absolute literal paths where appropriate.
- [ ] Verify patches, file search, Git/worktrees, trust checks, and URI conversion on Windows, including repositories outside the default drive and user profile.
- [ ] Test read-only and workspace-write permissions against all native sandbox implementations the fork advertises. Keep experimental backends separate until their host prerequisites and guarantees are understood.
- [ ] Verify access to permitted toolchains, project dependencies, temporary directories, and loopback services. A legitimate access failure needs a clear denial/remediation path rather than an automatic switch to full access or WSL.
- [ ] Cover reparse-point escapes, protected files, environment overrides, child processes, and network allow/deny behavior. Check setup, cancellation, recovery, and uninstall in disposable Windows environments where privileged operations are required.

Completion requires both positive and negative tests: permitted workflows succeed, prohibited reads/writes/network access remain blocked, and approvals grant only the requested scope. Run cases under a normal user account; administrator execution alone does not demonstrate ordinary-user compatibility.

Primary code areas: `windows-sandbox-rs/`, `sandboxing/`, `file-system/`, `exec-server/src/no_follow/`, `exec-server/src/fs_sandbox.rs`, `utils/path/`, `utils/path-uri/`, and Windows exec-policy tests.

**M6 Make terminal interaction reliable**

- [ ] Verify ConPTY and plain-pipe execution independently, including interactive prompts, REPLs, terminal resizing, streaming output, Ctrl-C, EOF, and cancellation of process trees.
- [ ] Test Windows Terminal and VS Code manually as well as through deterministic input/output fixtures. Cover Enter/Shift-Enter, paste, dead keys, non-English input, clipboard images/text, selection, and screen-reader behavior.
- [ ] Verify screen restoration, cursor position, color, wrapping, and Unicode after normal exit, interruption, and crashes. Background tools must not unexpectedly open visible console windows.
- [ ] Check shell profiles that emit output, slow startup, and unavailable terminal capabilities. Provide a usable fallback with accurate diagnostics.

Completion requires a repeatable terminal checklist on both primary terminals, automated process-lifecycle checks, no surviving fixture child processes after shutdown, and no priority terminal/input regressions. Use physical or interactive Windows sessions for behavior that a headless runner cannot establish.

Primary code areas: `utils/pty/`, `tui/src/tui/`, `tui/src/terminal_probe/`, clipboard modules, and screen-reader support.

**M7 Make contributor workflows native Windows workflows**

- [ ] Validate the refined setup script on disposable clean x64 and ARM64 Windows installations. Exercise compatible existing tools, missing tools, failed downloads/installers, restart requirements, and reruns.
- [ ] Prove `-CheckOnly` performs no installation or persistent mutation, including Rustup and Bazel implicit-download paths. Keep setup separate from Codex builds and tests.
- [ ] Test native Cargo build, focused tests, formatting, linting, package assembly, and supported Bazel recipes using PowerShell. Audit scripts reachable from those recipes for `/bin/sh`, POSIX environment assignments, quoting assumptions, and hardcoded executable names.
- [ ] Prefer existing portable Python and Rust utilities for shared logic, with PowerShell entry points where helpful. Do not translate every shell script or duplicate implementations without a Windows requirement.
- [ ] Document core prerequisites separately from feature-specific dependencies, with exact supported versions/architectures and native troubleshooting instructions.

Completion requires a fresh checkout to complete setup and then build, test, lint, format-check, and assemble the core CLI using documented Windows commands without WSL or Git Bash. Mocked installer tests remain necessary but do not replace disposable-machine validation. System changes are confined to explicitly authorized test machines.

Primary code areas: `scripts/`, `justfile`, `codex-rs/scripts/setup-windows.ps1`, its Pester suite, and `docs/install.md`.

**M8 Complete native support for advertised Windows features**

- [ ] Use the M0 feature inventory to cover Windows services/daemon behavior, local sockets or named pipes, plugins/extensions, voice/media, and other features advertised by the fork.
- [ ] Determine exactly which voice build inputs currently come from Cygwin. Replace that dependency with suitable native tooling, or keep the affected feature explicitly experimental until a native implementation is available.
- [ ] Validate media dependency versions and architecture, runtime DLL discovery, device permissions, and optional component installation. Avoid burdening core CLI users with unrelated feature toolchains.
- [ ] Verify start/stop/restart, upgrades, uninstall, user-session boundaries, and policy restrictions for any supported background service or feature helper.

Completion requires a native build and acceptance test for every feature advertised as supported on Windows. Compilation or execution through Cygwin, WSL, or emulation is not evidence of native parity. If a feature remains deferred, list it openly and limit the release claim to the features actually validated.

**M9 Deliver and test native Windows packages**

- [ ] Assemble x64 and ARM64 packages from the validated native build outputs, including required helpers, runtime libraries, licenses, and architecture-correct dependencies.
- [ ] Test standalone and supported package-manager installation, update, rollback, and removal. Verify PATH handling, execution policy errors, locked binaries, offline/failing downloads, and coexistence with official OpenAI installations.
- [ ] Test packaged `codex`, `codex exec`, app-server, and SDK use on fresh Windows machines. End users must not need Rust, Visual Studio, WSL, or development dependencies to run the core release.
- [ ] Run the complete core acceptance suite on an actual ARM64 Windows host. Cross-compilation and x64 emulation are useful checks but cannot close the ARM64 milestone.
- [ ] Label fork releases clearly, publish checksums and provenance, and state signing status accurately. Release publication and any signing resources require separate authorization.

Completion requires install/run/update/remove results for both architectures using the exact candidate artifacts, with reproducible packaging and no undeclared runtime dependencies. Missing ARM64 hardware or signing resources remain explicit constraints rather than assumed successes.

**M10 Validate the release and maintain upstream compatibility**

- [ ] Run the whole agreed acceptance matrix without WSL or Git Bash available for core workflows, using both primary terminals, supported shells, both architectures, and required sandbox modes.
- [ ] Pass every mandatory deterministic test, with zero unresolved critical/high-priority Windows failures and zero unexplained skips. Track intentionally deferred features in the support matrix.
- [ ] Evaluate real model behavior using the M0 task suite, fixed model/configuration, equivalent tool availability, and three repetitions. Target at least 95% of generated Windows command steps executing correctly on their first attempt, no unrequested WSL/Bash fallback, and a recorded comparison with upstream. Report overall task completion separately from command syntax success.
- [ ] Keep tests for failures discovered during daily use and monitor agreed startup/command-latency budgets. Model evaluation targets are release criteria, not a guarantee that generated commands can never be wrong.
- [ ] Rebase or merge upstream changes through the same Windows gates, with focused commits and a record of the fork's behavior changes. Keep macOS/Linux checks healthy and avoid scattering duplicated Windows logic across crates.
- [ ] Prepare minimal reproductions, root-cause explanations, tests, and isolated patches for improvements worth sharing with OpenAI. Follow the [upstream contribution policy](contributing.md#upstream-contribution-policy), which currently directs external contributions toward issue reports and analysis rather than code PRs.

Completion requires release evidence linked to the exact commit and artifacts, a current support matrix, a migration/troubleshooting guide, and a maintained regression suite. Claim fully native Windows support only for the agreed and validated scope.

**How to follow the plan**

For each milestone, keep one tracking record containing status, linked reproductions, the proposed change, relevant files, validation commands/results, remaining risks, and the evidence satisfying its completion criteria. Use the states planned, in progress, blocked, and complete. A blocked test environment must state what is missing; a green smoke run does not close a full-build milestone.

Each implementation change should identify its milestone and regression fixture, preserve existing cross-platform architecture, and run focused checks before the required CI. Keep shell-selection, prompt/context, execution, sandbox, terminal, and packaging changes independently reviewable. Do not install tools on a developer's machine or publish releases merely to advance a checklist without the relevant authorization.

The first implementation batch is M0 plus M1: record the Windows failures and support contract, establish the regression fixtures, fix full-CI dependency setup, and confirm actual PowerShell 5.1/7 execution coverage. M2 and M3 then address the most visible PowerShell syntax and command execution problems.
