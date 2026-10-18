"""The example rule in tools/lint_rules/README.md works, and reports what the README says it reports.

The README's example section (the first heading with "Example" in it) holds three fenced blocks, in any order, that
this test reads:
  ```python     the example rule, a whole rules/<NAME>.py module
  ```gdscript   a sample file it flags; its first line is a comment naming where the file lies, e.g. `# scenes/x.gd`
  ```text       what the runner prints for that sample: every non-blank line of it must appear in the output
The test drops the rule into a temp rules folder, the sample into a temp tree, runs the runner with `--rule=<NAME>`,
and expects exit 1 with those lines; on the same tree without the sample the rule passes. The README must also say
how to write a rule (NAME, DESCRIPTION, check), how to make an exception (an ALLOW entry with a reason) and that
rules report lines and never fix them.
"""
import re
import unittest

from tools.lint_rules.tests.support import README, TempTree, run_runner, write

FENCE = re.compile(r"^```(\w+)[^\n]*\n(.*?)^```", re.M | re.S)


def example_blocks() -> dict[str, str]:
    """The first python, gdscript and text block after the README's first Example heading."""
    text = README.read_text()
    heading = re.search(r"^#+ .*example.*$", text, re.M | re.I)
    if heading is None:
        raise AssertionError("tools/lint_rules/README.md has no Example heading")
    blocks: dict[str, str] = {}
    for lang, body in FENCE.findall(text[heading.end():]):
        blocks.setdefault(lang, body)
    missing = {"python", "gdscript", "text"} - blocks.keys()
    if missing:
        raise AssertionError(f"the README's example lacks a ```{'/'.join(sorted(missing))} block")
    return blocks


class ReadmeTests(unittest.TestCase):
    def test_the_readme_says_how_to_write_a_rule_and_make_an_exception(self):
        text = README.read_text()
        for word in ("NAME", "DESCRIPTION", "check(", "ALLOW", "reason"):
            self.assertIn(word, text)
        self.assertRegex(text, r"(?i)never fix|not fix|don't fix|do not fix", "rules report lines and never fix them")

    def test_the_example_rule_reports_as_documented(self):
        blocks = example_blocks()
        name = re.search(r"^NAME\s*=\s*[\"'](\w+)[\"']", blocks["python"], re.M)
        self.assertIsNotNone(name, "the example rule sets NAME")
        sample_path = re.match(r"\s*#\s*(\S+)", blocks["gdscript"])
        self.assertIsNotNone(sample_path, "the sample's first line names where it lies")
        with TempTree() as root:
            rules = root / "rules"
            write(rules, f"{name.group(1)}.py", blocks["python"])
            tree = root / "tree"
            write(tree, "project.godot", "config_version=5\n")
            clean = run_runner(tree, f"--rule={name.group(1)}", rules_dir=rules)
            write(tree, sample_path.group(1), blocks["gdscript"])
            flagged = run_runner(tree, f"--rule={name.group(1)}", rules_dir=rules)
        self.assertEqual(clean.returncode, 0, "the example rule passes a tree without the sample\n" + clean.stdout + clean.stderr)
        self.assertEqual(flagged.returncode, 1, flagged.stdout + flagged.stderr)
        for line in (l.strip() for l in blocks["text"].splitlines()):
            if line:
                self.assertIn(line, flagged.stdout, f"documented output line missing:\n{flagged.stdout}")


if __name__ == "__main__":
    unittest.main()
