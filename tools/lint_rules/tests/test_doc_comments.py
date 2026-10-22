"""Tests for the `doc_comments` lint rule (tools/lint_rules/rules/doc_comments.py): every function and member of a
script under scenes/ has a `##` doc comment.

- A function (`func` or `static func`, at any indent: an inner class's too, an annotation before it on its line or
  not) has a `##` line directly above it; only annotation lines (`@warning_ignore(...)`, `@rpc`, one whose arguments
  run over several lines too) may stand between. A `)` or `#` inside a string in a declaration changes nothing. The
  lifecycle overrides (`_ready`, `_process`,
  `_physics_process`, `_draw`, `_init`, `_input`, `_unhandled_input`, `_enter_tree`, `_exit_tree`, `_notification`,
  `_integrate_forces`) are exempt.
- A top-level member (`var`, `static var`, `@export… var`, `@onready var`, `signal`) has a trailing `## …`, or a `##`
  line above the run of declarations it belongs to: one doc comment may cover consecutive declarations, a multi-line
  value and an annotation line (`@export_group(...)`) included. A blank line, a plain `#` comment or any other
  statement ends the run. `const`, a function's locals, a folder Godot ignores (`.gdignore`) and anything outside
  scenes/ are not checked.
"""
import unittest

from tools.lint_rules import runner
from tools.lint_rules.tests.support import RULES, ROOT, TempTree, run_runner, write


def the_rule():
    rules = [r for r in runner.load_rules(RULES) if r.NAME == "doc_comments"]
    if not rules:
        raise AssertionError("no rule named doc_comments in tools/lint_rules/rules/")
    return rules[0]


def lines_found(text: str, rel: str = "scenes/a.gd") -> list[int]:
    """The lines the rule flags in a scenes/ script holding `text`."""
    with TempTree() as root:
        write(root, rel, text)
        return [f.line for f in the_rule().check(root, None)]


class FunctionTests(unittest.TestCase):
    def test_an_undocumented_function_is_found(self):
        self.assertEqual(lines_found("extends Node\n\n\nfunc go() -> void:\n\tpass\n"), [4])

    def test_an_undocumented_static_function_is_found(self):
        self.assertEqual(lines_found("extends Node\n\n\nstatic func go() -> void:\n\tpass\n"), [4])

    def test_a_documented_function_passes(self):
        self.assertEqual(lines_found("extends Node\n\n\n## Go.\nfunc go() -> void:\n\tpass\n"), [])

    def test_annotations_may_stand_between_the_doc_and_the_function(self):
        text = 'extends Node\n\n\n## Go.\n@warning_ignore("unused_parameter")\n@rpc\nfunc go(x) -> void:\n\tpass\n'
        self.assertEqual(lines_found(text), [])

    def test_an_annotation_on_the_function_line_is_still_a_function(self):
        self.assertEqual(lines_found("extends Node\n\n\n@rpc func go() -> void:\n\tpass\n"), [4])
        self.assertEqual(lines_found("extends Node\n\n\n## Go.\n@rpc func go() -> void:\n\tpass\n"), [])

    def test_a_multi_line_annotation_may_stand_between(self):
        text = 'extends Node\n\n\n## Go.\n@rpc(\n\t"any_peer",\n\t"call_local"\n)\nfunc go() -> void:\n\tpass\n'
        self.assertEqual(lines_found(text), [])
        self.assertEqual(lines_found(text.replace("## Go.\n", "")), [8])

    def test_a_bracket_in_an_annotation_string_changes_nothing(self):
        text = 'extends Node\n\n\n## Go.\n@warning_ignore(")")\nfunc go() -> void:\n\tpass\n'
        self.assertEqual(lines_found(text), [])
        member = 'extends Node\n\n## The x.\n@export_enum(")a", "b") var x := 0\n@export_enum("c)") var y := 0\n'
        self.assertEqual(lines_found(member), [])
        self.assertEqual(lines_found(member.replace("## The x.\n", "")), [3, 4])

    def test_a_plain_comment_is_not_a_doc_comment(self):
        self.assertEqual(lines_found("extends Node\n\n\n# Go.\nfunc go() -> void:\n\tpass\n"), [5])

    def test_the_lifecycle_overrides_are_exempt(self):
        names = ("_ready", "_process", "_physics_process", "_draw", "_init", "_input", "_unhandled_input",
                 "_enter_tree", "_exit_tree", "_notification", "_integrate_forces")
        text = "extends Node\n" + "".join(f"\n\nfunc {n}() -> void:\n\tpass\n" for n in names)
        self.assertEqual(lines_found(text), [])

    def test_other_overrides_are_not_exempt(self):
        self.assertEqual(lines_found("extends Node\n\n\nfunc _gui_input(e) -> void:\n\tpass\n"), [4])

    def test_an_inner_class_function_counts(self):
        text = "extends Node\n\n\n## A box.\nclass Box:\n\tfunc open() -> void:\n\t\tpass\n"
        self.assertEqual(lines_found(text), [6])

    def test_a_lambda_is_not_a_function_declaration(self):
        text = "extends Node\n\n\n## Go.\nfunc go() -> void:\n\tvar f := func(n):\n\t\treturn n\n\tf.call(1)\n"
        self.assertEqual(lines_found(text), [])


class MemberTests(unittest.TestCase):
    def test_each_kind_of_undocumented_member_is_found(self):
        for decl in ("var a := 1", "static var a := 1", "@export var a := 1", "@export_range(0, 1) var a := 0.5",
                     "@onready var a := $A", "signal moved", "signal moved(by: Vector2)"):
            with self.subTest(decl=decl):
                self.assertEqual(lines_found(f"extends Node\n\n{decl}\n"), [3])

    def test_a_trailing_doc_comment_documents_it(self):
        self.assertEqual(lines_found("extends Node\n\nvar a := 1  ## The a.\nsignal moved  ## Moved.\n"), [])

    def test_a_doc_comment_above_documents_it(self):
        self.assertEqual(lines_found("extends Node\n\n## The a,\n## over two lines.\nvar a := 1\n"), [])

    def test_one_doc_comment_covers_its_run(self):
        text = ("extends Node\n\n## The tones.\nvar a := 1\nstatic var b := 2\n@export var c := 3\n"
                "var d := {\n\t\"x\": 1,\n}\nvar e := [\n\t1,\n]\n@export_group(\"More\")\n@export var f := 4\n")
        self.assertEqual(lines_found(text), [])

    def test_a_blank_line_ends_the_run(self):
        self.assertEqual(lines_found("extends Node\n\n## The a.\nvar a := 1\n\nvar b := 2\n"), [6])

    def test_a_plain_comment_ends_the_run(self):
        self.assertEqual(lines_found("extends Node\n\n## The a.\nvar a := 1\n# --- More ---\nvar b := 2\n"), [6])

    def test_another_statement_ends_the_run(self):
        self.assertEqual(lines_found("extends Node\n\n## The A.\nconst A := 1\nvar b := 2\n"), [5])

    def test_constants_and_locals_are_not_checked(self):
        text = "extends Node\n\nconst A := 1\n\n\n## Go.\nfunc go() -> void:\n\tvar local := 1\n\tprint(local)\n"
        self.assertEqual(lines_found(text), [])

    def test_a_hash_in_a_string_is_not_a_trailing_doc_comment(self):
        self.assertEqual(lines_found('extends Node\n\nvar a := "## not a doc"\n'), [3])


class ScopeTests(unittest.TestCase):
    def test_only_scenes_is_scanned(self):
        with TempTree() as root:
            for rel in ("tests/a_test.gd", "sandboxes/a_sandbox.gd", "tools/a.gd", "addons/kit/a.gd"):
                write(root, rel, "extends Node\n\nvar a := 1\n\n\nfunc go() -> void:\n\tpass\n")
            self.assertEqual(the_rule().check(root, None), [])

    def test_a_folder_godot_ignores_is_not_scanned(self):
        with TempTree() as root:
            write(root, "scenes/deep/.gdignore")
            write(root, "scenes/deep/a.gd", "var a := 1\n")
            self.assertEqual(the_rule().check(root, None), [])

    def test_paths_limit_the_check(self):
        with TempTree() as root:
            write(root, "scenes/ai/a.gd", "var a := 1\n")
            write(root, "scenes/ui/b.gd", "var b := 1\n")
            self.assertEqual([f.path for f in the_rule().check(root, ["scenes/ui"])], ["scenes/ui/b.gd"])

    def test_the_message_names_what_lacks_a_doc_comment(self):
        with TempTree() as root:
            write(root, "scenes/a.gd", "extends Node\n\nsignal moved\n\n\nfunc go() -> void:\n\tpass\n")
            messages = [f.message for f in the_rule().check(root, None)]
        self.assertEqual(len(messages), 2, messages)
        self.assertIn("moved", messages[0])
        self.assertIn("go", messages[1])

    def test_the_real_tree_passes(self):
        self.assertEqual(the_rule().check(ROOT, None), [])


class ThroughTheLintTests(unittest.TestCase):
    def test_the_runner_fails_on_a_missing_doc_comment_and_passes_without(self):
        with TempTree() as root:
            write(root, "scenes/main.gd", "extends Node\n\n## The a.\nvar a := 1\n")
            ok = run_runner(root, "--rule=doc_comments")
            write(root, "scenes/main.gd", "extends Node\n\nvar a := 1\n")
            bad = run_runner(root, "--rule=doc_comments")
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
        self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
        self.assertIn("scenes/main.gd:3", bad.stdout)


if __name__ == "__main__":
    unittest.main()
