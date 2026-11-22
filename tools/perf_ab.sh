#!/usr/bin/env bash
# Same-fight A/B of two revisions on the match guards: tools/perf_ab.sh BASE TIP [--different-fights] [--ids=...]
# [--rounds=6] [--bar=5] [--retries=3] [--clean]; the usage, the rules and the exit codes are in tools/perf_ab.py's header (the code is Python).
source "$(dirname "$0")/setup/lib.sh"
fe_use_python || exit $?
exec "$PYTHON" "$(dirname "$0")/perf_ab.py" "$@"
