import json
import os
from pathlib import Path
import subprocess
import sys
import unittest


class CiResultsTests(unittest.TestCase):
    def check(self, needs, *args):
        return subprocess.run(
            [
                sys.executable,
                str(Path(__file__).with_name("check_ci_results.py")),
                *args,
            ],
            env={**os.environ, "NEEDS": json.dumps(needs)},
            capture_output=True,
            text=True,
        ).returncode

    def test_success(self):
        self.assertEqual(self.check({"tests": {"result": "success"}}), 0)

    def test_required_checks_must_succeed(self):
        for result in ("failure", "cancelled", "skipped"):
            with self.subTest(result=result):
                self.assertNotEqual(self.check({"tests": {"result": result}}), 0)

    def test_only_explicit_optional_skips_are_allowed(self):
        self.assertEqual(
            self.check({"sdk": {"result": "skipped"}}, "--allow-skipped", "sdk"),
            0,
        )
        self.assertNotEqual(
            self.check({"tests": {"result": "skipped"}}, "--allow-skipped", "sdk"),
            0,
        )

    def test_optional_failures_and_cancellations_still_fail(self):
        for result in ("failure", "cancelled"):
            with self.subTest(result=result):
                self.assertNotEqual(
                    self.check({"sdk": {"result": result}}, "--allow-skipped", "sdk"),
                    0,
                )


if __name__ == "__main__":
    unittest.main()
