#!/usr/bin/env python3
"""Pick the tool test modules a set of changed paths can break (tools/tool_tests.sh --staged runs it on the index).

  python3 tools/tool_tests_pick.py PATH...

Prints one test module a line (dotted, as `python3 -m unittest` takes it), nothing when no tool test can break, or the
single line `all` followed by `# <why>` lines when the whole discovery must run. A path is one of the changed files,
repo-relative.

The test modules are what `python3 -m unittest discover -s tools -t .` loads: every test*.py in a package (a folder
with an __init__.py) under the folders tools/__init__.py's `load_tests` keeps the discovery to (its TEST_PACKAGES), or
from tools/ down when it keeps none. The other test*.py files under tools/ are test scripts, run on their own
(`python3 tools/test_log_gate.py`): the discovery never loads them, so nothing here picks them, and no tool is named
through them. Fixtures and caches are no code. The rules:
  - a changed test module runs itself;
  - a changed file runs every test module whose code names it. Code names a file by its repo-relative path
    (`tools/lint.sh`), by its file name as a word of a path or a string of its own (`ROOT / ".githooks" /
    "pre-commit"`, `$(dirname "$0")/lint.sh`), or, for a Python module, by importing it (`from tools.lint_rules
    import walk`). A file name several files share (runner.py) counts only with its folder's name beside it. Code
    also names every file of a folder below the top level that is no Python package (its files are read by listing
    it, as the lint runner loads each rule, not imported one by one) when it names the folder whole: a path ending at
    the folder, by its path or its parent's name and its own (`scenes/testing/*.gd`, `ROOT / "scenes" / "testing"`,
    `LINT_RULES / "rules"` with `LINT_RULES = ROOT / "tools" / "lint_rules"`), or, in a Python module beside it, a
    path ending in its name alone (tools/lint_rules/runner.py's `HERE / "rules"`). A path going on into the folder
    names that file, not the folder, and a top-level folder (`ROOT / "scenes"`, copied whole) names no file: it would
    tie a test to every file of the tree. Comments and docstrings are not code: a file named in prose is no
    dependency. For a tool file, naming carries through the tools and the tests' shared helpers: a test of
    tools/lint_staged.sh is picked for a change to tools/lint.sh, which lint_staged.sh runs, and a test importing a
    helper's symbol for a change that symbol's code names. A file outside tools/ and .githooks/ counts only where a
    test reads it, named by the test's own code or a helper symbol it imports, not through a tool that runs it
    (tools/run_tests.sh names scenes/testing/test_batch.gd: the game tests the hook runs for that file cover it);
  - a changed shared test helper (a .py in a package named tests that is not a test module: support.py,
    __init__.py), or a changed tool file (under tools/ or .githooks/, not a test script) no test module or test
    script names, runs the whole discovery;
  - a changed file anywhere else (scenes/, docs/, gdstyle.toml ...), a test script, or a tool file only test scripts
    name (tools/play_tests.sh, tested by tools/test_play_tests.py), that no test module names runs none.
"""
import ast
import functools
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))  # `import tools` below, when this runs as a script

import tools  # noqa: E402

# What a tool can name another file from: its code. Prose files (READMEs) and data are not followed.
SOURCE_SUFFIXES = {".py", ".sh", ".gd", ".tscn", ""}
TOOL_TREES = ("tools/", ".githooks/")


def packages(top: Path):
    """The package folders unittest discovery enters from `top`: those with an __init__.py, reached through such."""
    if not (top / "__init__.py").is_file():
        return
    yield top
    for child in sorted(p for p in top.iterdir() if p.is_dir() and p.name != "__pycache__"):
        yield from packages(child)


def test_packages() -> list[Path]:
    """The packages the discovery loads tests from: those under TEST_PACKAGES, or every one from tools/ down."""
    tops = [ROOT / "tools" / p for p in getattr(tools, "TEST_PACKAGES", ())] or [ROOT / "tools"]
    return [pkg for top in tops for pkg in packages(top)]


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def test_modules() -> list[str]:
    return [rel(f) for pkg in test_packages() for f in sorted(pkg.glob("test*.py"))]


def helpers() -> list[str]:
    """The tests' shared helpers: every .py in a package named tests that is not a test module."""
    tests = set(test_modules())
    return [rel(f) for pkg in test_packages() if pkg.name == "tests"
            for f in sorted(pkg.glob("*.py")) if rel(f) not in tests]


def test_scripts() -> list[str]:
    """The test*.py files under tools/ the discovery does not load: scripts that run on their own."""
    tests = set(test_modules())
    return [rel(f) for f in sorted((ROOT / "tools").rglob("test*.py"))
            if "fixtures" not in f.parts and "__pycache__" not in f.parts and rel(f) not in tests]


def tool_sources() -> list[str]:
    """The code under tools/ (fixtures, caches and test scripts left out) and the git hooks: what can name another
    tool file."""
    scripts = set(test_scripts())
    found = []
    for f in sorted((ROOT / "tools").rglob("*")) + sorted((ROOT / ".githooks").glob("*")):
        parts = f.relative_to(ROOT).parts
        if (f.is_file() and f.suffix in SOURCE_SUFFIXES and "fixtures" not in parts and "__pycache__" not in parts
                and rel(f) not in scripts):
            found.append(rel(f))
    return found


def dotted(path: str) -> str:
    return path.removesuffix(".py").replace("/", ".")


@functools.cache
def listed_folders(path: str) -> list[str]:
    """The folders holding `path` below the top level that are no Python package, whose files are read by listing
    the folder: `tools/lint_rules/rules/x.py` -> [`tools/lint_rules/rules`] (tools/lint_rules has an __init__.py)."""
    parts = path.split("/")[:-1]
    found = ["/".join(parts[:n]) for n in range(len(parts), 1, -1)]
    return [f for f in found if not (ROOT / f / "__init__.py").is_file()]


class Code:
    """What a source's code says, its comments and docstrings left out: a Python module's (or some of its top-level
    statements') string literals and imports, any other source's text outside its comments. `at` is the source's own
    path, which a folder beside it is named from."""

    def __init__(self, text: str = "", nodes: list | None = None, at: str = ""):
        self.strings: list[str] = []
        self.imports: list[tuple[str, list[str]]] = []  # (module, names): `from module import names`, [] for `import`
        # The (parent's name or None, name) of each Python path ending in a string: `X / "a" / "b"` is ("a", "b").
        self.path_ends: set[tuple[str | None, str]] = set()
        self.text = text
        self.at = at
        if nodes is not None:
            self.path_ends = path_ends(nodes)
            docstrings = {id(n.value) for node in nodes for n in ast.walk(node) if isinstance(n, ast.Expr)
                          and isinstance(n.value, ast.Constant) and isinstance(n.value.value, str)}
            for node in nodes:
                for n in ast.walk(node):
                    if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in docstrings:
                        self.strings.append(n.value)
                    elif isinstance(n, ast.ImportFrom) and n.module:
                        self.imports.append((n.module, [a.name for a in n.names]))
                    elif isinstance(n, ast.Import):
                        self.imports += [(a.name, []) for a in n.names]
            self.text = "\n".join(self.strings)

    @staticmethod
    def of(path: str) -> "Code":
        try:
            source = (ROOT / path).read_text(errors="replace")
        except OSError:
            return Code(at=path)
        if not path.endswith(".py"):
            return Code("\n".join(re.sub(r"(^|\s)#.*", "", line) for line in source.splitlines()), at=path)
        try:
            return Code(nodes=[ast.parse(source)], at=path)
        except SyntaxError:
            return Code(source, at=path)

    def uses(self, module: str, symbol: str) -> bool:
        """Whether this code imports `symbol` from `module`, or `module` itself (every symbol of it)."""
        package, _, stem = module.rpartition(".")
        return any((m == module and (not imported or symbol in imported)) or (m == package and stem in imported)
                   for m, imported in self.imports)

    def _word(self, name: str) -> bool:
        """Whether `name` is a word of a path (after a `/`) or a string of its own."""
        name = re.escape(name)
        return bool(re.search(rf"/{name}(?![\w.-])", self.text)
                    or re.search(rf"(?:^|[\s\"'(]){name}(?![\w.-])", self.text, re.M))

    def _beside(self, parent: str, name: str) -> bool:
        """Whether `parent/name` is in a path, or (Python) both are strings of their own."""
        near = re.search(rf"(?:^|/){re.escape(parent)}/{re.escape(name)}(?![\w.-])", self.text, re.M)
        return bool(near or (parent in self.strings and name in self.strings))

    def names(self, path: str, shared: bool = False) -> bool:
        """Whether this code names the file `path`, or a folder holding it (the module docstring has the rules). A
        file name `shared` by several tool files counts only beside its folder's name."""
        if path in self.text:
            return True
        folder, _, file_name = path.rpartition("/")
        # Every way below needs the file's or a listed folder's name in the code, or (a Python module) an import:
        # checking that first spares a large commit a scan of every source per way.
        listed = listed_folders(path)
        if (file_name not in self.text and not any(f.rpartition("/")[2] in self.text for f in listed)
                and not (path.endswith(".py") and self.imports)):
            return False
        if self._beside(folder.rpartition("/")[2], file_name) if shared else self._word(file_name):
            return True
        return self._imports(path) or any(self.names_folder(f) for f in listed)

    def names_folder(self, folder: str) -> bool:
        """Whether this code names `folder` whole: a path ending at it (its own, or its parent's name and its own), or,
        from a Python module in that parent, a path ending in its name alone."""
        parent, _, name = folder.rpartition("/")
        parent_name = parent.rpartition("/")[2]
        for whole in (folder, f"{parent_name}/{name}"):
            if re.search(rf"(?:^|[^\w.-]){re.escape(whole)}(?![\w.-]|/[\w.])", self.text, re.M):
                return True
        if (parent_name, name) in self.path_ends:
            return True
        return self.at.rpartition("/")[0] == parent and (None, name) in self.path_ends

    def _imports(self, path: str) -> bool:
        """Whether the code imports the Python module `path`."""
        if not path.endswith(".py"):
            return False
        # A package of the same name (tools/coverage/ beside tools/coverage.py) takes the import: the file is a script.
        if (ROOT / path.removesuffix(".py")).is_dir():
            return False
        module = dotted(path)
        package, _, stem = module.rpartition(".")
        return any(m == module or (m == package and stem in imported) for m, imported in self.imports)


def path_ends(nodes: list) -> set[tuple[str | None, str]]:
    """Each Python path expression (a chain of `/`) ending in a string, as (the name before it, that string): the name
    before it is the string ahead of it, or the last string of the path a name ahead of it was assigned
    (`LINT_RULES / "rules"`), None when neither (`HERE / "rules"`)."""
    def chain(e) -> list:
        return chain(e.left) + [e.right] if isinstance(e, ast.BinOp) and isinstance(e.op, ast.Div) else [e]

    def last_string(ops: list) -> str | None:
        end = ops[-1]
        return end.value if isinstance(end, ast.Constant) and isinstance(end.value, str) else None

    divs = [n for node in nodes for n in ast.walk(node) if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Div)]
    inner = {id(n.left) for n in divs}
    assigned = {}
    for node in nodes:
        for n in ast.walk(node):
            if isinstance(n, ast.Assign) and len(n.targets) == 1:
                target = n.targets[0]
                key = target.id if isinstance(target, ast.Name) else getattr(target, "attr", None)
                end = last_string(chain(n.value))
                if key and end:
                    assigned[key] = end
    ends = set()
    for n in divs:
        ops = chain(n)
        name = last_string(ops)
        if id(n) in inner or name is None:
            continue
        before = ops[-2]
        if isinstance(before, ast.Constant) and isinstance(before.value, str):
            ends.add((before.value, name))
        elif isinstance(before, (ast.Name, ast.Attribute)):
            ends.add((assigned.get(before.id if isinstance(before, ast.Name) else before.attr), name))
        else:
            ends.add((None, name))
    return ends


def helper_symbols(path: str) -> dict[str, Code]:
    """A helper's top-level names (functions, classes, constants), each with the code it runs: its own statement
    and, through the module's globals it reads, theirs. So a test importing `clean_env` from a helper depends on what
    clean_env names, not on everything the helper holds."""
    try:
        tree = ast.parse((ROOT / path).read_text(errors="replace"))
    except (OSError, SyntaxError):
        return {}
    defines: dict[str, ast.stmt] = {}
    imports = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))]
    for stmt in tree.body:
        if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            defines[stmt.name] = stmt
        elif isinstance(stmt, (ast.Assign, ast.AnnAssign)):
            for target in stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target]:
                if isinstance(target, ast.Name):
                    defines[target.id] = stmt
    symbols = {}
    for name in defines:
        seen, frontier = {name}, [name]
        while frontier:
            for n in ast.walk(defines[frontier.pop()]):
                if isinstance(n, ast.Name) and n.id in defines and n.id not in seen:
                    seen.add(n.id)
                    frontier.append(n.id)
        symbols[name] = Code(nodes=[defines[s] for s in seen] + imports, at=path)
    return symbols


def pick(changed: list[str]) -> tuple[list[str], list[str]]:
    """(the test modules to run, why the whole discovery must run instead): the modules are [] when `why` is not, and
    both are [] when no tool test can break."""
    tests = test_modules()
    helper_set = set(helpers())
    why = [f"{p} is a shared test helper" for p in changed if p in helper_set]
    if why:
        return [], why
    scripts = set(test_scripts())
    # The nodes the naming runs through: each tool and test file, and each helper's symbols as `<helper>::<name>`.
    files = set(tests) | set(tool_sources())
    code = {p: Code.of(p) for p in (files | scripts) - helper_set}
    counts = Counter(f.rpartition("/")[2] for f in files | set(changed))
    for h in helper_set:
        code.update({f"{h}::{name}": c for name, c in helper_symbols(h).items()})

    def depends(source: str, target: str) -> bool:
        if "::" in target:
            helper, symbol = target.split("::")
            return code[source].uses(dotted(helper), symbol)
        return code[source].names(target, counts[target.rpartition("/")[2]] > 1)

    picked = set()
    for path in changed:
        tool = path.startswith(TOOL_TREES)
        # Every tool or helper symbol whose code names `path`, and every one naming one of those, to a fixpoint; for
        # a file outside the tools, only the helper symbols naming it.
        reached, frontier = {path}, [path]
        while frontier:
            current = frontier.pop()
            for source in code:
                if source in reached or source in tests or source in scripts or not (tool or "::" in source):
                    continue
                if depends(source, current):
                    reached.add(source)
                    if tool:
                        frontier.append(source)
        hits = {t for t in tests if t in reached or any(depends(t, r) for r in reached)}
        if not hits and tool and path not in scripts and not any(depends(s, r) for s in scripts for r in reached):
            why.append(f"no tool test names {path}")
        picked |= hits
    if why:
        return [], why
    return sorted(dotted(t) for t in picked), []


def main(argv: list[str]) -> int:
    modules, why = pick([p for p in argv if p])
    if why:
        print("all")
        for reason in why:
            print(f"# {reason}")
    elif modules:
        print("\n".join(modules))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
