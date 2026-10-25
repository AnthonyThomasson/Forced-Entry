#!/usr/bin/env python3
"""Pick the tool test modules a set of changed paths can break (tools/tool_tests.sh --staged runs it on the index).

  python3 tools/tool_tests_pick.py PATH...

Prints one test module a line (dotted, as `python3 -m unittest` takes it), or the single line `all` followed by
`# <why>` lines when the whole discovery must run. A path is one of the changed files, repo-relative.

The test modules are what `python3 -m unittest discover -s tools -t .` loads: every test*.py in a package under tools/
(a folder with an __init__.py, from tools/ down). The rules:
  - a changed test module runs itself;
  - a changed file runs every test module whose code names it. Code names a file by its repo-relative path
    (`tools/lint.sh`), by its file name as a word of a path or a string of its own (`ROOT / ".githooks" /
    "pre-commit"`, `$(dirname "$0")/lint.sh`), or, for a Python module, by importing it (`from tools.lint_rules
    import walk`). Comments and docstrings are not code: a file named in prose is no dependency. Naming carries
    through the tools and the tests' helpers: a test of tools/run_tests.sh is picked for a change to tools/lint.sh,
    which run_tests.sh runs, and a test importing a helper for a change the helper names;
  - a changed shared test helper (a .py in a tests package that is not a test module: support.py, __init__.py), or a
    changed file no test module names, runs the whole discovery.
"""
import ast
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# What a tool can name another file from: its code. Prose files (READMEs) and data are not followed.
SOURCE_SUFFIXES = {".py", ".sh", ".gd", ".tscn", ""}


def packages(top: Path):
    """The package folders unittest discovery enters from `top`: those with an __init__.py, reached through such."""
    if not (top / "__init__.py").is_file():
        return
    yield top
    for child in sorted(p for p in top.iterdir() if p.is_dir() and p.name != "__pycache__"):
        yield from packages(child)


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def test_modules() -> list[str]:
    return [rel(f) for pkg in packages(ROOT / "tools") for f in sorted(pkg.glob("test*.py"))]


def helpers() -> list[str]:
    """The tests' shared helpers: every .py in a tests package that is not a test module."""
    tests = set(test_modules())
    return [rel(f) for pkg in packages(ROOT / "tools") if pkg.name == "tests"
            for f in sorted(pkg.glob("*.py")) if rel(f) not in tests]


def tool_sources() -> list[str]:
    """The code under tools/ (fixtures and caches left out) and the git hooks: what can name another tool file."""
    found = []
    for f in sorted((ROOT / "tools").rglob("*")) + sorted((ROOT / ".githooks").glob("*")):
        parts = f.relative_to(ROOT).parts
        if f.is_file() and f.suffix in SOURCE_SUFFIXES and "fixtures" not in parts and "__pycache__" not in parts:
            found.append(rel(f))
    return found


def dotted(path: str) -> str:
    return path.removesuffix(".py").replace("/", ".")


class Code:
    """What a source's code says, its comments and docstrings left out: a Python module's (or some of its top-level
    statements') string literals and imports, any other source's text outside its comments."""

    def __init__(self, text: str = "", nodes: list | None = None):
        self.strings: list[str] = []
        self.imports: list[tuple[str, list[str]]] = []  # (module, names): `from module import names`, [] for `import`
        self.text = text
        if nodes is not None:
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
            return Code()
        if not path.endswith(".py"):
            return Code("\n".join(re.sub(r"(^|\s)#.*", "", line) for line in source.splitlines()))
        try:
            return Code(nodes=[ast.parse(source)])
        except SyntaxError:
            return Code(source)

    def uses(self, module: str, symbol: str) -> bool:
        """Whether this code imports `symbol` from `module`, or `module` itself (every symbol of it)."""
        package, _, stem = module.rpartition(".")
        return any((m == module and (not imported or symbol in imported)) or (m == package and stem in imported)
                   for m, imported in self.imports)

    def names(self, path: str, shared: bool = False) -> bool:
        """Whether this code names `path`: its repo-relative path, its file name as a word of a path (after a `/`) or
        a string of its own, or, for a Python module, an import of it. A file name `shared` by several tool files
        (runner.py) counts only with its folder: `coverage/runner.py`, or the folder's name as a string of its own
        beside it (`ROOT / "tools" / "coverage" / "runner.py"`)."""
        if path in self.text:
            return True
        folder, _, file_name = path.rpartition("/")
        name = re.escape(file_name)
        if shared:
            parent = folder.rpartition("/")[2]
            near = re.search(rf"(?:^|/){re.escape(parent)}/{name}(?![\w.-])", self.text, re.M)
            if not (near or (parent in self.strings and file_name in self.strings)):
                return self._imports(path, shared)
        if re.search(rf"/{name}(?![\w.-])", self.text):
            return True
        if re.search(rf"(?:^|[\s\"'(]){name}(?![\w.-])", self.text, re.M):
            return True
        return self._imports(path, shared)

    def _imports(self, path: str, shared: bool) -> bool:
        """Whether the code imports the Python module `path`, or (a file name no other shares) loads it by its stem as
        a whole string, as the lint rules are found by NAME."""
        if not path.endswith(".py"):
            return False
        module = dotted(path)
        package, _, stem = module.rpartition(".")
        if not shared and stem in self.strings:
            return True
        # A package of the same name (tools/coverage/ beside tools/coverage.py) takes the import: the file is a script.
        if (ROOT / path.removesuffix(".py")).is_dir():
            return False
        return any(m == module or (m == package and stem in imported) for m, imported in self.imports)


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
        symbols[name] = Code(nodes=[defines[s] for s in seen] + imports)
    return symbols


def pick(changed: list[str]) -> tuple[list[str], list[str]]:
    """(the test modules to run, why the whole discovery must run instead): the modules are [] when `why` is not."""
    tests = test_modules()
    helper_set = set(helpers())
    why = [f"{p} is a shared test helper" for p in changed if p in helper_set]
    if why:
        return [], why
    # The nodes the naming runs through: each tool and test file, and each helper's symbols as `<helper>::<name>`.
    files = set(tests) | set(tool_sources())
    code = {p: Code.of(p) for p in files - helper_set}
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
        # Every tool or helper symbol whose code names `path`, and every one naming one of those, to a fixpoint.
        reached, frontier = {path}, [path]
        while frontier:
            current = frontier.pop()
            for source in code:
                if source not in reached and source not in tests and depends(source, current):
                    reached.add(source)
                    frontier.append(source)
        hits = {t for t in tests if t in reached or any(depends(t, r) for r in reached)}
        if not hits:
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
    else:
        print("\n".join(modules))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
