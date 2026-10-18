"""Toy rule for the runner's tests: an ALLOW entry without a reason, which is itself an error."""
from tools.lint_rules.walk import Finding, files, lines_matching

NAME = "toy_no_reason"
DESCRIPTION = "flags BAD under scenes/, with an allow entry that gives no reason"
ALLOW = [{"path": "scenes/allowed.txt"}]


def check(root, paths):
    return [Finding(path, line, "the word BAD")
            for path in files(root, ["scenes"], paths)
            for line, _text in lines_matching(root, path, r"\bBAD\b")]
