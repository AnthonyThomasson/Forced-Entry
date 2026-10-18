"""Toy rule for the runner's tests: flags BAD under scenes/, with one file allowed (and the reason shown)."""
from tools.lint_rules.walk import Finding, files, lines_matching

NAME = "toy_allowed"
DESCRIPTION = "flags BAD under scenes/, scenes/allowed.txt excepted"
ALLOW = [{"path": "scenes/allowed.txt", "reason": "a fixture exception, kept visible"}]


def check(root, paths):
    return [Finding(path, line, "the word BAD")
            for path in files(root, ["scenes"], paths)
            for line, _text in lines_matching(root, path, r"\bBAD\b")]
