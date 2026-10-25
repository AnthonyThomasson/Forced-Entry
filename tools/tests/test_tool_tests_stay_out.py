"""The tool tests write only in a temp dir or a copy of the checkout (`copy_checkout()` in tools/test_log_gate.py),
never in the live tree: another agent's lint or `--changed` run in the same worktree would see a probe written there,
and a killed run leaves it behind.

Every tool test module, the tests' shared helpers and the test scripts (tools/tool_tests_pick.py's lists) are read
with `ast`: a path is rooted when it is built from `ROOT` or `__file__`, or from a name assigned one (`PROBE = ROOT /
...`, then `self.PROBE`), and a write on a rooted path fails: `write_text` / `write_bytes` / `mkdir` / `touch` /
`symlink_to`, `open` in a writing mode, the destination of `shutil.copy*` / `copytree` / `move`, `os.makedirs`, either
side of a path's `rename` / `replace` or of `os.rename` / `os.replace` (a file moved out of the tree is gone from it),
and a `dir=` (a temp file made in the tree). The message is `file:line` and what to do instead.
"""
import ast
import unittest
from pathlib import Path

from tools import tool_tests_pick

ROOT = Path(__file__).resolve().parents[2]
SEEDS = {"ROOT", "__file__"}
WRITE_METHODS = {"write_text", "write_bytes", "mkdir", "touch", "symlink_to"}
MOVE_METHODS = {"rename", "replace"}
COPIES = {"copy", "copy2", "copyfile", "copytree", "move"}
FIX = "write in a temp dir or copy_checkout()"


def tool_test_modules() -> list[Path]:
    found = tool_tests_pick.test_modules() + tool_tests_pick.helpers() + tool_tests_pick.test_scripts()
    return sorted(ROOT / p for p in found if ROOT / p != Path(__file__))


def names_in(node: ast.AST) -> set[str]:
    """The names an expression reads: bare names, and `self.X` / `cls.X` as `X`. A `cwd=` argument is left out: what
    a command run in the tree returns (`git ls-files`' paths, relative) is not a path built from it."""
    out = set()
    skipped = {id(k.value) for k in ast.walk(node) if isinstance(k, ast.keyword) and k.arg == "cwd"}
    stack = [node]
    while stack:
        n = stack.pop()
        if id(n) in skipped:
            continue
        stack.extend(ast.iter_child_nodes(n))
        if isinstance(n, ast.Name):
            out.add(n.id)
        elif isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id in ("self", "cls"):
            out.add(n.attr)
    return out


def targets_of(node: ast.AST) -> list[str]:
    """The names an assignment binds: `x = ...`, `X: T = ...`, `self.X = ...`, `with ... as x`, `for x in ...`."""
    if isinstance(node, ast.Assign):
        targets = node.targets
    elif isinstance(node, (ast.AnnAssign, ast.AugAssign, ast.NamedExpr)):
        targets = [node.target]
    elif isinstance(node, ast.withitem):
        targets = [node.optional_vars] if node.optional_vars is not None else []
    elif isinstance(node, ast.For):
        targets = [node.target]
    else:
        return []
    out = []
    for t in targets:
        for n in ast.walk(t):
            if isinstance(n, ast.Name):
                out.append(n.id)
            elif isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id in ("self", "cls"):
                out.append(n.attr)
    return out


def value_of(node: ast.AST):
    if isinstance(node, ast.withitem):
        return node.context_expr
    if isinstance(node, ast.For):
        return node.iter
    return getattr(node, "value", None)


def scope_nodes(scope: ast.AST):
    """The nodes of `scope` that are not inside a function nested in it."""
    stack = list(ast.iter_child_nodes(scope))
    while stack:
        n = stack.pop()
        yield n
        if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
            stack.extend(ast.iter_child_nodes(n))


def rooted_names(scope: ast.AST, inherited: set[str]) -> set[str]:
    """The names bound in `scope` (flow-insensitively, to a fixpoint) to a path built from a rooted name."""
    rooted = set(inherited)
    assigns = [n for n in scope_nodes(scope) if targets_of(n) and value_of(n) is not None]
    changed = True
    while changed:
        changed = False
        for a in assigns:
            if names_in(value_of(a)) & rooted:
                new = set(targets_of(a)) - rooted
                if new:
                    rooted |= new
                    changed = True
    return rooted


def writing_mode(call: ast.Call, position: int) -> bool:
    mode = call.args[position] if len(call.args) > position else None
    for kw in call.keywords:
        if kw.arg == "mode":
            mode = kw.value
    return isinstance(mode, ast.Constant) and isinstance(mode.value, str) and any(c in mode.value for c in "wax+")


def written_paths(call: ast.Call) -> list:
    """The path expressions a call writes to (or moves a file out of): none for a call that writes nothing."""
    f = call.func
    found = [kw.value for kw in call.keywords if kw.arg == "dir"]
    module = f.value.id if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) else None
    if isinstance(f, ast.Attribute):
        if f.attr in WRITE_METHODS:
            found.append(f.value)
        elif f.attr == "open" and writing_mode(call, 0):
            found.append(f.value)
        elif module == "shutil" and f.attr in COPIES and len(call.args) > 1:
            found.append(call.args[1])
        elif module == "os" and f.attr == "makedirs" and call.args:
            found.append(call.args[0])
        elif module == "os" and f.attr in MOVE_METHODS:
            found += call.args[:2]
        elif f.attr in MOVE_METHODS and len(call.args) == 1 and not call.keywords:
            # A path's rename(target) / replace(target): one argument, where str.replace takes two.
            found += [f.value, call.args[0]]
    if isinstance(f, ast.Name) and f.id == "open" and call.args and writing_mode(call, 1):
        found.append(call.args[0])
    return found


def rooted_writes(source: str) -> list[tuple[int, str]]:
    """Each write on a rooted path in `source`: its line and the path expression."""
    found = []

    def visit(scope: ast.AST, inherited: set[str]) -> None:
        rooted = rooted_names(scope, inherited)
        for n in scope_nodes(scope):
            if isinstance(n, ast.Call):
                for target in written_paths(n):
                    if names_in(target) & rooted:
                        found.append((n.lineno, ast.unparse(target)))
                        break
            elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
                visit(n, rooted)

    # A class's attributes (`PROBE = ROOT / ...`) reach its methods as `self.PROBE`, so they share the module's scope.
    visit(ast.parse(source), SEEDS)
    return sorted(found)


class ToolTestsStayOutTests(unittest.TestCase):
    def test_the_check_finds_each_kind_of_write_on_a_rooted_path(self):
        source = ('PROBE = ROOT / "tests" / "_harness" / "p.gd"\n'
                  "class T:\n"
                  "    def test_x(self):\n"
                  '        self.PROBE.write_text("x")\n'
                  '        out = ROOT / "a"\n'
                  '        open(out / "b", "w")\n'
                  '        shutil.copy2(src, ROOT / "c")\n'
                  "    def test_y(self, tmp):\n"
                  '        (tmp / "d").write_text("fine")\n'
                  '        open(ROOT / "e").read()\n'
                  '        shutil.copy2(ROOT / "f", tmp / "f")\n'
                  '        listed = run(["git", "ls-files"], cwd=ROOT)\n'
                  '        (tmp / listed).write_text("fine")\n'
                  '        (tmp / "h").rename(ROOT / "h")\n'
                  '        (ROOT / "i").replace(tmp / "i")\n'
                  '        (ROOT / "j").symlink_to(tmp)\n'
                  '        os.replace(tmp / "k", ROOT / "k")\n'
                  '        os.rename(ROOT / "l", tmp / "l")\n'
                  '        tempfile.mkdtemp(dir=ROOT)\n'
                  '        tempfile.mkdtemp(dir=tmp)\n'
                  '        (tmp / "m").rename(tmp / "n")\n'
                  '        (ROOT / "o").read_text().replace("a", "b")\n')
        self.assertEqual([line for line, _ in rooted_writes(source)], [4, 6, 7, 14, 15, 16, 17, 18, 19])

    def test_no_tool_test_writes_into_the_live_tree(self):
        modules = tool_test_modules()
        for module in ("tools/test_log_gate.py", "tools/tests/test_tool_tests.py", "tools/coverage/tests/support.py"):
            self.assertIn(ROOT / module, modules, "premise: the test modules, scripts and helpers are found")
        found = [f"{m.relative_to(ROOT)}:{line}: {target}: {FIX}"
                 for m in modules for line, target in rooted_writes(m.read_text())]
        self.assertEqual(found, [], "\n" + "\n".join(found))


if __name__ == "__main__":
    unittest.main()
