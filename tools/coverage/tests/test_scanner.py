"""Tests for tools/coverage/scanner.py: GDScript text to statements and uninstrumented spans.

  scanner.scan(text) -> {"statements": [...], "uninstrumented": [...]}
    statements:      {"line", "kind", "function", "class", ...} per statement, the fields of a statement-map entry
                     without `id` and `file` (the scanner may add its own, e.g. where on the line the counter goes)
    uninstrumented:  {"line", "end_line", "reason"} per span it was not sure about and left untouched

Kinds as tools/coverage/README.md defines them: `function` (a function's first body statement), `branch` (the first
statement of an if / elif / else body, a match arm or a loop body), `statement` (any other statement in a function
body, a lambda's included). Only function bodies hold statements. The scanner works from indentation and brackets;
strings, comments and multi-line strings are never statements.

Each case is a small GDScript snippet (written with 4-space indents here, turned into tabs as the project writes
them) with its statements listed by hand: (line, kind, function, class).
"""
import textwrap
import unittest

from tools.coverage import scanner


def gd(text: str) -> str:
    """Dedent `text` and turn each leading group of 4 spaces into a tab."""
    out = []
    for line in textwrap.dedent(text).lstrip("\n").split("\n"):
        stripped = line.lstrip(" ")
        out.append("\t" * ((len(line) - len(stripped)) // 4) + stripped)
    return "\n".join(out)


def statements(text: str) -> list[tuple]:
    return sorted((s["line"], s["kind"], s["function"], s["class"]) for s in scanner.scan(gd(text))["statements"])


def uninstrumented(text: str) -> list[tuple]:
    return sorted((u["line"], u["end_line"]) for u in scanner.scan(gd(text))["uninstrumented"])


class SimpleTests(unittest.TestCase):
    def test_simple_statements_and_the_function_entry(self):
        self.assertEqual(statements("""
            extends Node

            func run() -> void:
                var a := 1
                a += 2
                print(a)
            """), [(4, "function", "run", ""), (5, "statement", "run", ""), (6, "statement", "run", "")])

    def test_pass_is_a_statement_and_a_one_line_function_has_its_entry_on_the_func_line(self):
        self.assertEqual(statements("""
            func idle() -> void:
                pass

            func one() -> int: return 1
            """), [(2, "function", "idle", ""), (4, "function", "one", "")])

    def test_two_statements_on_one_line_are_two_statements(self):
        self.assertEqual(statements("""
            func run() -> void:
                var a := 1; var b := 2
            """), [(2, "function", "run", ""), (2, "statement", "run", "")])

    def test_class_level_declarations_are_not_statements(self):
        self.assertEqual(statements("""
            extends Node
            ## A doc comment.

            signal done(value: int)
            enum Mode { A, B }
            const LIMIT := 3
            @export var speed: float = 1.0
            var _count := 0
            @onready var _label = get_node("Label")

            func run() -> void:
                _count += 1
            """), [(12, "function", "run", "")])


class BranchTests(unittest.TestCase):
    def test_if_elif_else_blocks(self):
        self.assertEqual(statements("""
            func run(v: int) -> int:
                var t := 0
                if v > 2:
                    t += 1
                    t += 1
                elif v > 0:
                    t += 2
                else:
                    t += 3
                return t
            """), [(2, "function", "run", ""), (3, "statement", "run", ""), (4, "branch", "run", ""),
                   (5, "statement", "run", ""), (7, "branch", "run", ""), (9, "branch", "run", ""),
                   (10, "statement", "run", "")])

    def test_one_line_if_elif_else(self):
        self.assertEqual(statements("""
            func run(v: int) -> int:
                var t := 0
                if v > 5: t += 10
                elif v > 2: t += 20
                else: t += 30
                return t
            """), sorted([(2, "function", "run", ""), (3, "statement", "run", ""), (3, "branch", "run", ""),
                   (4, "branch", "run", ""), (5, "branch", "run", ""), (6, "statement", "run", "")]))

    def test_match_arms_block_and_one_line(self):
        self.assertEqual(statements("""
            func run(v: int) -> int:
                var t := 0
                match v:
                    1:
                        t += 1
                    2, 3:
                        t += 2
                    _:
                        t += 3
                match v:
                    1: t += 1
                    _: t += 2
                return t
            """), [(2, "function", "run", ""), (3, "statement", "run", ""), (5, "branch", "run", ""),
                   (7, "branch", "run", ""), (9, "branch", "run", ""), (10, "statement", "run", ""),
                   (11, "branch", "run", ""), (12, "branch", "run", ""), (13, "statement", "run", "")])

    def test_for_and_while_bodies_block_and_one_line(self):
        self.assertEqual(statements("""
            func run() -> int:
                var t := 0
                for i in 3:
                    t += i
                for i in 2: t += i
                while t < 10:
                    t += 1
                while t < 20: t += 1
                return t
            """), sorted([(2, "function", "run", ""), (3, "statement", "run", ""), (4, "branch", "run", ""),
                   (5, "statement", "run", ""), (5, "branch", "run", ""), (6, "statement", "run", ""),
                   (7, "branch", "run", ""), (8, "statement", "run", ""), (8, "branch", "run", ""),
                   (9, "statement", "run", "")]))

    def test_a_compound_statement_that_opens_a_body_is_that_body_s_branch(self):
        self.assertEqual(statements("""
            func run(v: int) -> void:
                if v > 0:
                    if v > 1:
                        print(v)
                else:
                    for i in v:
                        print(i)
            """), [(2, "function", "run", ""), (3, "branch", "run", ""), (4, "branch", "run", ""),
                   (6, "branch", "run", ""), (7, "branch", "run", "")])


class LambdaTests(unittest.TestCase):
    def test_a_multi_line_lambda_in_a_variable_belongs_to_its_function(self):
        self.assertEqual(statements("""
            func run() -> int:
                var f := func(x: int) -> int:
                    var y := x * 2
                    return y
                return f.call(1)
            """), [(2, "function", "run", ""), (3, "statement", "run", ""), (4, "statement", "run", ""),
                   (5, "statement", "run", "")])

    def test_an_inline_lambda_in_call_arguments(self):
        self.assertEqual(statements("""
            func run(arr: Array) -> Array:
                var doubled := arr.map(func(x): return x * 2)
                return doubled
            """), [(2, "function", "run", ""), (2, "statement", "run", ""), (3, "statement", "run", "")])

    def test_a_multi_line_lambda_in_call_arguments(self):
        self.assertEqual(statements("""
            func run(arr: Array) -> Array:
                var tripled := arr.map(func(x):
                    var y = x * 3
                    return y
                )
                return tripled
            """), [(2, "function", "run", ""), (3, "statement", "run", ""), (4, "statement", "run", ""),
                   (6, "statement", "run", "")])


class LayoutTests(unittest.TestCase):
    def test_a_statement_wrapped_over_several_lines_and_the_one_after_it(self):
        self.assertEqual(statements("""
            func run() -> int:
                var t := _sum(1,
                        2,
                        3)
                var d := {
                    "a": 1,
                    "b": [2,
                        3],
                }
                return t + d.size()
            """), [(2, "function", "run", ""), (5, "statement", "run", ""), (10, "statement", "run", "")])

    def test_a_multi_line_signature(self):
        self.assertEqual(statements("""
            func signature(a: int,
                    b: int,
                    c: int) -> int:
                return a + b + c
            """), [(4, "function", "signature", "")])

    def test_static_func(self):
        self.assertEqual(statements("""
            static func helper(a: int) -> int:
                return a + 1
            """), [(2, "function", "helper", "")])

    def test_inner_and_nested_classes(self):
        self.assertEqual(statements("""
            extends RefCounted

            class Counter:
                var n := 0

                func bump() -> int:
                    n += 1
                    return n

                class Nested:
                    static func twice(x: int) -> int:
                        return x * 2

            func run() -> int:
                return Counter.new().bump()
            """), [(7, "function", "bump", "Counter"), (8, "statement", "bump", "Counter"),
                   (12, "function", "twice", "Counter.Nested"), (15, "function", "run", "")])

    def test_a_tool_script(self):
        self.assertEqual(statements("""
            @tool
            extends Node

            func touched() -> int:
                return 7
            """), [(5, "function", "touched", "")])


class StringAndCommentTests(unittest.TestCase):
    def test_a_hash_inside_a_string_is_not_a_comment(self):
        self.assertEqual(statements("""
            func run() -> int:
                var text := "a # b"; var n := text.count("#")
                var q := 'single "quoted" # still text'; n += 1
                var e := "escaped \\" quote # still text"; n += 1
                return n
            """), [(2, "function", "run", ""), (2, "statement", "run", ""), (3, "statement", "run", ""),
                   (3, "statement", "run", ""), (4, "statement", "run", ""), (4, "statement", "run", ""),
                   (5, "statement", "run", "")])

    def test_comments_are_not_statements(self):
        self.assertEqual(statements("""
            func run() -> int:
                # print("commented out")
                var n := 1 # a trailing comment; n += 5
                    # an indented comment
                ## a doc comment inside a body
                return n
            """), [(3, "function", "run", ""), (6, "statement", "run", "")])

    def test_multi_line_strings_are_not_statements(self):
        self.assertEqual(statements("""
            func run() -> int:
                var s := \"\"\"first
            if inside: print("string, not code")
            # still the string
                return 99
            last\"\"\"
                return s.length()
            """), [(2, "function", "run", ""), (7, "statement", "run", "")])

    def test_a_statement_on_the_closing_line_of_a_multi_line_string_is_uninstrumented(self):
        text = """
            func run() -> int:
                var s := \"\"\"first
            last\"\"\"; s += "!"
                return s.length()
            """
        self.assertEqual(statements(text), [(2, "function", "run", ""), (4, "statement", "run", "")])
        self.assertEqual(uninstrumented(text), [(3, 3)])
        self.assertTrue(all(u["reason"].strip() for u in scanner.scan(gd(text))["uninstrumented"]),
                        "every uninstrumented span says why")

    def test_a_plain_file_has_nothing_uninstrumented(self):
        self.assertEqual(uninstrumented("""
            func run(v: int) -> int:
                if v > 0: return 1
                return 0
            """), [])


if __name__ == "__main__":
    unittest.main()
