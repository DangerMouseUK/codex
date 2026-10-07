# Workflow Strategy

## Forks

`fork-ci.yml` is the entrypoint for fork pull requests and pushes to `main`.
It uses standard GitHub-hosted Ubuntu, Windows 2025 and macOS 15 runners with
read-only repository permissions. It needs no OpenAI secrets, runner groups,
BuildBuddy account, protected environments or paid larger runners.

- Every run checks repository policies, formatting, unused dependencies,
  spelling and dependency advisories, and runs the Windows setup tests under
  Windows PowerShell 5.1 and PowerShell 7 with mocked installers.
- Native Cargo clippy and nextest always cover `codex-shell-command`,
  `codex-utils-pty` and `codex-utils-path` on all three operating systems. This
  includes native MSVC Windows builds and PowerShell-related shell handling.
- Rust sources, Cargo manifests/lockfiles, toolchain or Cargo/nextest configuration
  changes expand native checks to the full Rust workspace and enable SDK tests.
  SDK sources, JavaScript dependency files and `sdk.yml` changes enable SDK tests
  against a Cargo-built CLI on hosted Ubuntu.
- The **Run workflow** button defaults to full native Rust and SDK coverage.
  Clear **full** to repeat the faster smoke checks. Cargo caches are isolated by
  operating system, architecture, toolchain, dependency lock and coverage scope.
- Require **Fork CI required** in the fork's branch rules. It fails on failed,
  cancelled or unexpectedly skipped dependencies. SDK checks may be skipped only
  when the change detector says they are unnecessary.

The native fork suite does not replace OpenAI's Bazel, source-built V8,
cross-compilation, release/signing or custom argument-comment-lint coverage.
Those workflows are gated to `openai/codex`; they remain available there with
their original infrastructure. Fork CI does not publish releases or deploy.
Cargo shear reports informational warnings about unlinked source files without
failing; unused dependencies remain failures.

## OpenAI Upstream

The workflows in this directory are split so that pull requests get fast, review-friendly signal while `main` still gets the full cross-platform verification pass.

## Pull Requests

- Required checks run against GitHub's synthetic merge commit, not the pull
  request head alone. This includes changes already on `main` and catches
  conflicts before they reach the branch.
- `bazel.yml` is the main pre-merge verification path for Rust code.
  It runs Bazel `test` and Bazel `clippy` on the supported Bazel targets,
  including the generated Rust test binaries needed to lint inline `#[cfg(test)]`
  code.
- `rust-ci.yml` keeps the Cargo-native PR checks intentionally small:
  - `cargo fmt --check`
  - `cargo shear`
  - `argument-comment-lint` on Linux, macOS, and Windows
  - `tools/argument-comment-lint` package tests when the lint or its workflow wiring changes

## Post-Merge On `main`

- `bazel.yml` also runs on pushes to `main`.
  This re-verifies the merged Bazel path and helps keep the BuildBuddy caches warm.
- `rust-ci-full.yml` is the full Cargo-native verification workflow.
  It keeps the heavier checks off the PR path while still validating them after merge:
  - the full Cargo `clippy` matrix
  - the full Cargo `nextest` matrix via per-platform archive-backed shards
  - Windows ARM64 nextest archives cross-compiled on Windows x64, then replayed on native Windows ARM64 shards
  - release-profile Cargo builds
  - cross-platform `argument-comment-lint`
  - Linux remote-env tests

## Rule Of Thumb

- If a build/test/clippy check can be expressed in Bazel, prefer putting the PR-time version in `bazel.yml`.
- Keep `rust-ci.yml` fast enough that it usually does not dominate PR latency.
- Reserve `rust-ci-full.yml` for heavyweight Cargo-native coverage that Bazel does not replace yet.
