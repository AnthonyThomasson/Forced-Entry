"""The dev tools, a package so their tests can import them (`from tools.coverage import hits`).

The tool tests run with

    python3 -m unittest discover -s tools -t .

and `load_tests` below keeps that discovery to the tests packages. The other `tools/test_*.py` files match the
discovery pattern too, but they are scripts, not tool tests: `test_coverage.py` reports on import and
`test_log_gate.py` and `test_play_tests.py` drive the engine. They run on their own
(`python3 tools/test_log_gate.py`).
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEST_PACKAGES = ("lint_rules/tests", "coverage/tests", "tests")


def load_tests(loader, tests, pattern):
    """The tests of the tests packages only (unittest calls this when it discovers the `tools` package)."""
    for package in TEST_PACKAGES:
        tests.addTests(loader.discover(start_dir=str(HERE / package), pattern=pattern or "test*.py",
                                       top_level_dir=str(HERE.parent)))
    return tests
