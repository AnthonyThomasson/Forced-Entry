"""Toy rule for the runner's tests: its check raises, which must fail the lint, never pass it."""

NAME = "toy_crash"
DESCRIPTION = "a toy rule whose check raises"


def check(root, paths):
    raise RuntimeError("toy rule blew up")
