import unittest

from fork_ci_changes import coverage


class ForkCoverageTests(unittest.TestCase):
    def test_setup_and_docs_keep_native_smoke_coverage(self):
        self.assertEqual(
            coverage(["codex-rs/scripts/setup-windows.ps1", "docs/install.md"]),
            {"rust_full": False, "sdk": False},
        )

    def test_rust_sources_and_build_configuration_require_full_coverage(self):
        for path in (
            "codex-rs/core/src/lib.rs",
            "codex-rs/utils/pty/tests/test.rs",
            "codex-rs/Cargo.lock",
            "codex-rs/core/Cargo.toml",
            "codex-rs/rust-toolchain.toml",
            "codex-rs/.cargo/config.toml",
            "codex-rs/.config/nextest.toml",
        ):
            with self.subTest(path=path):
                self.assertEqual(coverage([path]), {"rust_full": True, "sdk": True})

    def test_sdk_and_dependency_changes_require_sdk_coverage(self):
        for path in ("sdk/python/src/example.py", "sdk/typescript/src/index.ts", "pnpm-lock.yaml"):
            with self.subTest(path=path):
                self.assertEqual(coverage([path]), {"rust_full": False, "sdk": True})

    def test_manual_full_run_cannot_skip_expensive_checks(self):
        self.assertEqual(coverage([], full=True), {"rust_full": True, "sdk": True})


if __name__ == "__main__":
    unittest.main()
