"""Toy rule for the runner's tests: never finds anything."""

NAME = "toy_pass"
DESCRIPTION = "a toy rule that always passes"


def check(root, paths):
    return []
