"""Toy rule for the runner's tests: every line of a file under scenes/ that holds the word BAD."""
from tools.lint_rules.walk import Finding, files, lines_matching

NAME = "toy_fail"
DESCRIPTION = "a toy rule that flags the word BAD under scenes/"


def check(root, paths):
    return [Finding(path, line, "the word BAD")
            for path in files(root, ["scenes"], paths)
            for line, _text in lines_matching(root, path, r"\bBAD\b")]
