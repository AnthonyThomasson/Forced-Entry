r"""Windows only: Python writes "\r\n" for every newline on stdout and stderr, so a bash script that captures a tool's
output (`out=$("$PYTHON" tools/x.py)`, `while read`) gets a "\r" on every line. tools/setup/lib.sh's fe_use_python puts
this folder on PYTHONPATH there, and Python imports this module at start-up: it makes both streams write "\n" as on a Mac.
"""
import sys

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(newline="\n")
    except (AttributeError, ValueError):
        pass
