"""Which functions nothing references, for the report's `dead` and `untriggered system` tags: a thin adapter over
tools/audit_scan.py's "Functions nothing references" (token matching over scenes/, tests/, tools/ and addons/; the
coverage fixtures are skipped).

  unreferenced(root) -> {(file, function)}   file repo-relative and POSIX, as in the statement map
"""
from pathlib import Path

from tools import audit_scan


def unreferenced(root) -> set[tuple[str, str]]:
    return {(Path(path).as_posix(), name) for path, _line, name in audit_scan.dead_functions(root)}
