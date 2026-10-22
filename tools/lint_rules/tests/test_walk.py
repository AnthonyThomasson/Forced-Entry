"""Tests for the GDScript helpers the lint rules share (tools/lint_rules/walk.py).

`gdscript_lines(root, path)` splits each line of a script into its `code` and its `comment` (from the first `#` outside
a string), marks whether it `starts` a statement (not inside brackets, a triple-quoted string or a backslash
continuation an earlier line opened) and gives its `bare` code (the code with what is inside each string blanked to
spaces, the quotes kept). Strings are "", '', triple-quoted and their `&` (StringName) and `^` (NodePath) forms.
`godot_scripts(root, dirs, paths)` lists the `.gd` files under `dirs` that Godot loads: none under a folder holding a
`.gdignore`, at any depth.
"""
import unittest

from tools.lint_rules import walk
from tools.lint_rules.tests.support import TempTree, write


def lines_of(text: str) -> list:
    with TempTree() as root:
        write(root, "a.gd", text)
        return walk.gdscript_lines(root, "a.gd")


class CommentTests(unittest.TestCase):
    def test_a_hash_inside_a_string_is_code(self):
        for literal in ('"a#b"', "'a#b'", '&"a#b"', '^"a#b"'):
            with self.subTest(literal=literal):
                line = lines_of(f"var s := {literal}  # the s\n")[0]
                self.assertEqual(line.code, f"var s := {literal}  ")
                self.assertEqual(line.comment, "# the s")

    def test_an_escaped_quote_does_not_end_the_string(self):
        line = lines_of('var s := "a\\"#b"  ## the s\n')[0]
        self.assertEqual(line.comment, "## the s")

    def test_a_line_with_no_comment_has_an_empty_one(self):
        line = lines_of("var x := 1\n")[0]
        self.assertEqual((line.code, line.comment), ("var x := 1", ""))


class StartTests(unittest.TestCase):
    def test_a_triple_quoted_string_spans_lines(self):
        lines = lines_of('var s := """one\n# not a comment\n"""  # after\nvar t := 1\n')
        self.assertEqual([line.starts for line in lines[:4]], [True, False, False, True])
        self.assertEqual(lines[1].comment, "")
        self.assertEqual(lines[2].comment, "# after")

    def test_brackets_span_lines(self):
        lines = lines_of("var a := [\n\t1,  # one\n]\nvar b := 2\n")
        self.assertEqual([line.starts for line in lines[:4]], [True, False, False, True])
        self.assertEqual(lines[1].comment, "# one")

    def test_a_bracket_inside_a_string_is_not_counted(self):
        lines = lines_of('var a := "("\nvar b := 2\n')
        self.assertEqual([line.starts for line in lines[:2]], [True, True])

    def test_a_backslash_continues_the_statement(self):
        lines = lines_of("var a := 1 + \\\n\t2\nvar b := 3\n")
        self.assertEqual([line.starts for line in lines[:3]], [True, False, True])

    def test_a_one_line_string_left_open_ends_with_its_line(self):
        lines = lines_of('var a := "open\nvar b := 2\n')
        self.assertTrue(lines[1].starts)


class BareTests(unittest.TestCase):
    def test_what_is_inside_a_string_is_blanked(self):
        line = lines_of('@export_enum(")a", &"b") var x := 0  # c\n')[0]
        self.assertEqual(line.bare, '@export_enum("  ", &" ") var x := 0  ')
        self.assertEqual(len(line.bare), len(line.code))

    def test_an_escape_is_blanked_whole(self):
        line = lines_of('var s := "a\\")"\n')[0]
        self.assertEqual(line.bare, 'var s := "    "')

    def test_a_triple_quoted_string_is_blanked_across_lines(self):
        lines = lines_of('var s := """a)\nb(\n"""\n')
        self.assertEqual([line.bare for line in lines[:3]], ['var s := """  ', "  ", '"""'])


class GodotScriptsTests(unittest.TestCase):
    def test_a_folder_godot_ignores_is_left_out_at_any_depth(self):
        with TempTree() as root:
            for rel in ("scenes/a.gd", "scenes/deep/.gdignore", "scenes/deep/b.gd", "scenes/deep/er/c.gd",
                        "scenes/ok/d.gd", "scenes/ok/e.txt"):
                write(root, rel)
            self.assertEqual(walk.godot_scripts(root, ["scenes"]), ["scenes/a.gd", "scenes/ok/d.gd"])

    def test_paths_limit_it(self):
        with TempTree() as root:
            write(root, "scenes/a/x.gd")
            write(root, "scenes/b/y.gd")
            self.assertEqual(walk.godot_scripts(root, ["scenes"], ["scenes/b"]), ["scenes/b/y.gd"])


if __name__ == "__main__":
    unittest.main()
