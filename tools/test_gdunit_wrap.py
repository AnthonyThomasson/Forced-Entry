#!/usr/bin/env python3
"""Tests for the gdUnit4 wrapper suites: every simulation test shows up in gdUnit, once, by its id.

  python3 tools/test_gdunit_wrap.py

gdUnit's own discovery (the one its editor panel runs, through tools/gdunit_discover.gd, headless) must find:
  - one wrapper suite per domain, `tests/<domain>/<domain>_suite.gd`, and one per AI topic folder,
    `tests/ai/<topic>/<topic>_suite.gd` (27 today), each listing exactly the tests of its folder;
  - every catalog test (`tests/**/*_test.gd`, the harness's own in `tests/_harness/` aside) listed by exactly one
    wrapper suite case, named by its id: the case takes one parameter, the id (`test_<x>:<n> ('<id>')`);
  - the harness tests listed only by one self-test suite of their own, which lists nothing else;
  - any other suite (a native unit suite) listing no test id at all.
The catalog is read here from the files themselves, so a new `*_test.gd` must appear with no edit to any suite.
Skipped when no Godot binary is found.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))  # run as a script: the repo root, for tools.coverage.tests.support
from tools.coverage.tests.support import clean_env  # noqa: E402
TESTS = ROOT / "tests"
DISCOVER = "res://tools/gdunit_discover.gd"
SCAN = ROOT / "tools" / "scan_godot_log.py"
CASE_NAME = re.compile(r"^(test_\w+):(\d+) \('([^']+)'\)$")


def godot_binary():
    for name in ("godot", "godot4"):
        p = shutil.which(name)
        if p:
            return p
    for p in sorted(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot")):
        return str(p)
    return os.environ.get("GODOT")


def test_id(path: Path) -> str:
    return path.relative_to(TESTS).as_posix().removesuffix("_test.gd")


def catalog():
    """(catalog ids, harness ids) from the files: tests/**/*_test.gd, the harness's own apart."""
    ids, harness = set(), set()
    for f in TESTS.rglob("*_test.gd"):
        (harness if f.relative_to(TESTS).parts[0] == "_harness" else ids).add(test_id(f))
    return ids, harness


def expected_wrappers():
    """res:// path of each wrapper suite -> the folder whose tests it lists ("projectile/" or "ai/entry/")."""
    out = {}
    for d in sorted(p for p in TESTS.iterdir() if p.is_dir() and not p.name.startswith("_")):
        if d.name == "ai":
            for topic in sorted(p for p in d.iterdir() if p.is_dir()):
                out[f"res://tests/ai/{topic.name}/{topic.name}_suite.gd"] = f"ai/{topic.name}/"
        else:
            out[f"res://tests/{d.name}/{d.name}_suite.gd"] = f"{d.name}/"
    return out


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class WrapperSuiteDiscoveryTests(unittest.TestCase):
    """What gdUnit's discovery lists, headless, against the catalog on disk."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="gdunit_wrap_"))
        log = cls.tmp / "godot.log"
        r = subprocess.run([godot_binary(), "--headless", "--path", str(ROOT), "--log-file", str(log), "-s", DISCOVER],
                           cwd=ROOT, env=clean_env(), capture_output=True, text=True, timeout=600)
        cls.output = r.stdout + r.stderr
        cls.code = r.returncode
        cls.log_scan = subprocess.run([sys.executable, "-I", str(SCAN), str(log)], capture_output=True, text=True)
        cls.cases = [json.loads(line[len("CASE "):]) for line in r.stdout.splitlines() if line.startswith("CASE ")]
        cls.by_suite = defaultdict(list)
        for c in cls.cases:
            cls.by_suite[c["suite"]].append(c)
        cls.ids, cls.harness = catalog()
        cls.wrappers = expected_wrappers()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def listed(self, suite):
        """The ids a suite's cases are named by (None for a case not named by one id)."""
        out = []
        for c in self.by_suite.get(suite, []):
            m = CASE_NAME.match(c["name"])
            out.append(m.group(3) if m else None)
        return out

    def test_discovery_runs_clean(self):
        self.assertEqual(self.code, 0, self.output[-4000:])
        self.assertIn(f"DISCOVERED {len(self.cases)}", self.output)
        self.assertEqual(self.log_scan.returncode, 0, "an engine error or warning during discovery\n" + self.log_scan.stdout)

    def test_the_catalog_has_tests_to_wrap(self):
        # The premise: the files this test reads are the ones the brief counts (27 folders, harness tests apart).
        self.assertEqual(len(self.wrappers), 27, sorted(self.wrappers))
        self.assertTrue(self.ids and self.harness)

    def test_one_wrapper_suite_per_domain_and_per_ai_topic_folder(self):
        missing = sorted(s for s in self.wrappers if s not in self.by_suite)
        self.assertEqual(missing, [], f"{len(missing)} of {len(self.wrappers)} wrapper suites not found by gdUnit")

    def test_each_wrapper_suite_lists_exactly_the_tests_of_its_folder_by_id(self):
        for suite, folder in self.wrappers.items():
            with self.subTest(suite=suite):
                listed = self.listed(suite)
                self.assertNotIn(None, listed, f"a case not named '<func>:<n> ('<id>')': {self.by_suite.get(suite)}")
                own = {i for i in self.ids if i.startswith(folder) and "/" not in i[len(folder):]}
                self.assertTrue(own, f"no catalog test in {folder}")
                self.assertEqual(Counter(listed), Counter(own), f"{suite} must list each test of {folder} once")

    def test_every_catalog_test_is_listed_by_exactly_one_wrapper_case(self):
        listed = Counter(i for s in self.wrappers for i in self.listed(s) if i is not None)
        for what, bad in (("catalog tests no wrapper suite lists", [i for i in self.ids if listed[i] == 0]),
                          ("catalog tests listed more than once", [i for i in self.ids if listed[i] > 1]),
                          ("listed ids that name no catalog test", [i for i in listed if i not in self.ids])):
            self.assertEqual(len(bad), 0, f"{len(bad)} {what}, e.g. {sorted(bad)[:5]}")

    def test_harness_tests_appear_only_in_the_self_test_suite(self):
        holders = sorted(s for s in self.by_suite if any(i in self.harness for i in self.listed(s)))
        self.assertEqual(len(holders), 1, f"the harness tests must have one suite of their own, found {holders}")
        suite = holders[0]
        self.assertNotIn(suite, self.wrappers)
        self.assertEqual(Counter(self.listed(suite)), Counter(self.harness), "the self-test suite lists each harness test once, nothing else")

    def test_any_other_suite_lists_no_test_id(self):
        harness_suites = {s for s in self.by_suite if any(i in self.harness for i in self.listed(s))}
        for suite in sorted(set(self.by_suite) - set(self.wrappers) - harness_suites):
            with self.subTest(suite=suite):
                self.assertTrue(suite.endswith("_suite.gd"), f"a gdUnit suite is named *_suite.gd: {suite}")
                named = [i for i in self.listed(suite) if i in self.ids or i in self.harness]
                self.assertEqual(named, [], f"{suite} is not a wrapper suite but lists test ids")


if __name__ == "__main__":
    unittest.main(verbosity=2)
