"""tools/gdstyle_reflow.py, which `tools/gdstyle.sh fmt` runs gdstyle through: gdstyle wraps an over-long comment line
by moving its tail onto a new line of its own, and the re-flow then fills each comment paragraph gdstyle changed back
to 100 columns (a tab counts 4), with the same indent and marker (`#` / `##`), never splitting a backtick span.

A paragraph is the full-line comments of one indent and marker between a blank comment line, a line of another
indent or marker, a list item (`- `, `* `, `1. `: it starts one, and its hang-indented lines, or the tail gdstyle split
off it, continue it), a preformatted line (more than one space after the marker), or code. A trailing comment on a
code line is never part of one. A paragraph gdstyle left alone is left alone, however it is wrapped.

`reflow(before, after)` is checked on the text alone; then the wrapper end to end, with a fake gdstyle planted in a
temp cache that splits the way the real one does; `fmt --check` and `check` pass through untouched; and, when the
pinned gdstyle is in the default cache, the real one.
"""
import os
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

from tools.coverage.tests.support import clean_env
from tools.gdstyle_reflow import reflow
from tools.tests.test_gdstyle import VERSION, asset

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "gdstyle.sh"

# Splits like gdstyle v0.4.0: a full-line comment over 100 columns (tab = 4) is cut at the last space that fits, the
# tail going onto a new line with the same indent and marker. Logs its arguments to $FAKE_GDSTYLE_LOG.
FAKE_GDSTYLE = '''#!/usr/bin/env python3
import os, re, sys
from pathlib import Path
with open(os.environ["FAKE_GDSTYLE_LOG"], "a") as log:
    log.write(" ".join(sys.argv[1:]) + "\\n")
if sys.argv[1:2] != ["fmt"] or "--check" in sys.argv:
    sys.exit(0)
targets = [a for a in sys.argv[2:] if not a.startswith("-")] or ["."]
files = []
for t in targets:
    p = Path(t)
    files += sorted(p.rglob("*.gd")) if p.is_dir() else [p]
for f in files:
    out = []
    for line in f.read_text().split("\\n"):
        while len(line.expandtabs(4)) > 100 and re.match(r"^\\s*#+ ", line):
            prefix = re.match(r"^(\\s*#+ )", line).group(1)
            cut = max(i for i, c in enumerate(line) if c == " " and len(line[:i].expandtabs(4)) <= 100)
            out.append(line[:cut])
            line = prefix + line[cut + 1:]
        out.append(line)
    f.write_text("\\n".join(out))
'''


def split_like_gdstyle(text: str) -> str:
    """`text` with each full-line comment over 100 columns (tab = 4) cut at the last space that fits, the tail on a
    new line with the same indent and marker: what gdstyle v0.4.0 does (and FAKE_GDSTYLE)."""
    out = []
    for line in text.split("\n"):
        while len(line.expandtabs(4)) > 100 and re.match(r"^\s*#+ ", line):
            prefix = re.match(r"^(\s*#+ )", line).group(1)
            cut = max(i for i, c in enumerate(line) if c == " " and len(line[:i].expandtabs(4)) <= 100)
            out.append(line[:cut])
            line = prefix + line[cut + 1:]
        out.append(line)
    return "\n".join(out)


def lines(text: str) -> str:
    return textwrap.dedent(text).lstrip("\n")


def widths(text: str) -> list[int]:
    return [len(line.expandtabs(4)) for line in text.split("\n")]


LONG = "## The first doc line of a paragraph that runs well past the hundred column limit by a few words here."
BROKEN = "## The first doc line of a paragraph that runs well past the hundred column limit by a few words\n## here."


class ReflowTests(unittest.TestCase):
    def test_a_broken_paragraph_is_filled_again(self):
        before = f"extends Node\n\n{LONG}\n## A second line of the same paragraph, short.\nvar x := 1\n"
        after = f"extends Node\n\n{BROKEN}\n## A second line of the same paragraph, short.\nvar x := 1\n"
        self.assertEqual(reflow(before, after), lines("""
            extends Node

            ## The first doc line of a paragraph that runs well past the hundred column limit by a few words
            ## here. A second line of the same paragraph, short.
            var x := 1
            """))

    def test_a_code_span_at_the_edge_is_never_split(self):
        long = "## Text " + "x" * 70 + " then `a span with spaces` end, and on to the next line."
        after = "## Text " + "x" * 70 + " then `a span with\n## spaces` end, and on to the next line."
        out = reflow(f"{long}\nvar q := 2\n", f"{after}\nvar q := 2\n")
        self.assertEqual(out, "## Text " + "x" * 70 + " then\n## `a span with spaces` end, and on to the next line.\n"
                         "var q := 2\n")

    def test_every_line_fits_in_100_columns_with_a_tab_as_4(self):
        before = "func f() -> void:\n\t# " + " ".join(f"w{i}" for i in range(80)) + "\n\t# The end.\n\tpass\n"
        out = reflow(before, split_like_gdstyle(before))
        comment = [line for line in out.split("\n") if line.startswith("\t#")]
        self.assertTrue(all(line.startswith("\t# ") for line in comment), out)
        self.assertTrue(all(len(line.expandtabs(4)) <= 100 for line in comment), widths(out))
        self.assertTrue(all(len(line.expandtabs(4)) > 94 for line in comment[:-1]),
                        f"filled, not wrapped short:\n{out}")
        self.assertEqual([w for w in out.split() if w != "#"], [w for w in before.split() if w != "#"])

    def test_a_trailing_doc_comment_is_left_alone(self):
        trailing = "var some_long_name_here := 1  ## A trailing doc comment that pushes this line past the hundred."
        before = f"{trailing}\n{LONG}\nvar y := 2\n"
        after = f"{trailing}\n{BROKEN}\nvar y := 2\n"
        out = reflow(before, after)
        self.assertEqual(out.split("\n")[0], trailing, "the code line's trailing comment is not a paragraph")
        self.assertEqual(out.split("\n")[1:3], BROKEN.split("\n"), "and the paragraph below starts on its own")

    def test_a_paragraph_gdstyle_left_alone_is_left_alone(self):
        short = "## A paragraph wrapped\n## short on purpose.\nvar a := 1\n"
        before = f"{short}\n{LONG}\nvar b := 2\n"
        after = f"{short}\n{BROKEN}\nvar b := 2\n"
        self.assertTrue(reflow(before, after).startswith(short))

    def test_a_list_item_keeps_its_hang_indent(self):
        before = ("## - a list item that runs past the column limit with enough words to push the last one over "
                  "the edge ok.\n##   its hang line.\n## - the next item.\nvar z := 1\n")
        after = ("## - a list item that runs past the column limit with enough words to push the last one over the\n"
                 "## edge ok.\n##   its hang line.\n## - the next item.\nvar z := 1\n")
        self.assertEqual(reflow(before, after), lines("""
            ## - a list item that runs past the column limit with enough words to push the last one over the
            ##   edge ok. its hang line.
            ## - the next item.
            var z := 1
            """))

    def test_a_blank_comment_line_and_a_preformatted_line_end_a_paragraph(self):
        before = f"{LONG}\n##\n## After the blank.\n##   name   a preformatted row\nvar a := 1\n"
        after = f"{BROKEN}\n##\n## After the blank.\n##   name   a preformatted row\nvar a := 1\n"
        self.assertEqual(reflow(before, after), after, "the broken line has nothing after it to join")

    def test_another_marker_or_indent_ends_a_paragraph(self):
        before = f"{LONG}\n# A plain comment below.\n\t## An indented doc.\n"
        after = f"{BROKEN}\n# A plain comment below.\n\t## An indented doc.\n"
        self.assertEqual(reflow(before, after), after)

    def test_nothing_changed_returns_the_text(self):
        text = f"{BROKEN}\nvar a := 1\n"
        self.assertEqual(reflow(text, text), text)


class WrapperTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.cache = self.base / "cache"
        binary = self.cache / f"v{VERSION}" / asset().removesuffix(".tar.gz") / "gdstyle"
        binary.parent.mkdir(parents=True)
        binary.write_text(FAKE_GDSTYLE)
        binary.chmod(0o755)
        self.log = self.base / "gdstyle.log"
        self.work = self.base / "work"
        self.work.mkdir()

    def run_script(self, *args) -> subprocess.CompletedProcess:
        env = clean_env(GDSTYLE_CACHE=str(self.cache), GDSTYLE_RELEASE_URL=(self.base / "none").as_uri(),
                        FAKE_GDSTYLE_LOG=str(self.log))
        return subprocess.run(["bash", str(SCRIPT), *args], cwd=self.work, env=env, capture_output=True, text=True,
                              timeout=120)

    def write(self, rel: str, text: str) -> Path:
        path = self.work / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_fmt_re_flows_what_gdstyle_broke(self):
        a = self.write("a.gd", f"extends Node\n\n{LONG}\n## A second line.\nvar x := 1\n")
        r = self.run_script("fmt", "a.gd")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(a.read_text().split("\n")[2:4], [
            "## The first doc line of a paragraph that runs well past the hundred column limit by a few words",
            "## here. A second line.",
        ])
        self.assertEqual(self.log.read_text().split(), ["fmt", "a.gd"], "gdstyle got the arguments")

    def test_fmt_with_no_path_or_a_folder_re_flows_under_it(self):
        b = self.write("scenes/deep/b.gd", f"{LONG}\n## More.\n")
        for args in (("fmt",), ("fmt", "scenes")):
            with self.subTest(args=args):
                b.write_text(f"{LONG}\n## More.\n")
                r = self.run_script(*args)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertTrue(b.read_text().split("\n")[1].endswith("here. More."), b.read_text())

    def test_fmt_check_and_check_pass_through_untouched(self):
        a = self.write("a.gd", f"{LONG}\n")
        for args in (("fmt", "--check", "a.gd"), ("check", "a.gd")):
            with self.subTest(args=args):
                r = self.run_script(*args)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertEqual(a.read_text(), f"{LONG}\n")


class RealGdstyleTests(unittest.TestCase):
    def test_the_pinned_gdstyle_then_the_re_flow_leaves_a_formatted_file(self):
        cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "forced-entry-gdstyle"
        if not (cache / f"v{VERSION}" / asset().removesuffix(".tar.gz") / "gdstyle").exists():
            self.skipTest("the pinned gdstyle is not cached (tools/gdstyle.sh --version fetches it)")
        with tempfile.TemporaryDirectory() as d:
            work = Path(d)
            (work / "gdstyle.toml").write_text((ROOT / "gdstyle.toml").read_text())
            span = "## Text " + "x" * 70 + " then `a span with spaces` end, and the rest of the paragraph."
            a = work / "a.gd"
            a.write_text(f"extends Node\n\n{LONG}\n## A second line.\n{span}\nvar x := 1\n")
            env = clean_env()
            fmt = subprocess.run(["bash", str(SCRIPT), "fmt", "a.gd"], cwd=work, env=env, capture_output=True,
                                 text=True, timeout=300)
            self.assertEqual(fmt.returncode, 0, fmt.stdout + fmt.stderr)
            text = a.read_text()
            self.assertIn("## here. A second line. Text", text, text)
            self.assertIn("`a span with spaces`", text, text)
            check = subprocess.run(["bash", str(SCRIPT), "fmt", "--check", "a.gd"], cwd=work, env=env,
                                   capture_output=True, text=True, timeout=300)
            self.assertEqual(check.returncode, 0, "gdstyle accepts the re-flowed file\n" + check.stdout + text)


if __name__ == "__main__":
    unittest.main()
