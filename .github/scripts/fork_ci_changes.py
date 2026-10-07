#!/usr/bin/env python3
"""Select hosted fork CI coverage without requiring Rust or repository secrets."""

import argparse
import subprocess
from pathlib import PurePosixPath


def coverage(paths: list[str], *, full: bool = False) -> dict[str, bool]:
    rust = full or any(
        path.startswith("codex-rs/")
        and (
            PurePosixPath(path).suffix == ".rs"
            or PurePosixPath(path).name
            in {"Cargo.toml", "Cargo.lock", "rust-toolchain.toml"}
            or path.startswith("codex-rs/.cargo/")
            or path.startswith("codex-rs/.config/")
        )
        for path in paths
    )
    sdk = rust or any(
        path.startswith("sdk/")
        or path in {"package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"}
        or path == ".github/workflows/sdk.yml"
        for path in paths
    )
    return {"rust_full": rust, "sdk": sdk}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()
    if args.full:
        paths = []
    elif not args.base or set(args.base) == {"0"}:
        # Initial pushes and manual runs have no usable comparison range.
        args.full = True
        paths = []
    else:
        paths = (
            subprocess.check_output(
                [
                    "git",
                    "diff",
                    "--name-only",
                    "--no-renames",
                    "-z",
                    args.base,
                    args.head,
                ]
            )
            .decode("utf-8")
            .split("\0")
        )
    for key, value in coverage(paths, full=args.full).items():
        print(f"{key}={str(value).lower()}")


if __name__ == "__main__":
    main()
