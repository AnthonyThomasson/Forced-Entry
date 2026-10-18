"""Toy rule for the runner's tests: an ALLOW entry whose reason is blank, which is itself an error."""

NAME = "toy_blank_reason"
DESCRIPTION = "finds nothing, but allows a path with a blank reason"
ALLOW = [{"path": "scenes/allowed.txt", "reason": "   "}]


def check(root, paths):
    return []
