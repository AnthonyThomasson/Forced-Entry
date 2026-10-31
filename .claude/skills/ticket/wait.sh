#!/usr/bin/env bash
# Wait for the coordinator's next inbox batch: .claude/skills/ticket/wait.sh [ack_delivery_id] [orca_inbox.py flags...]
# Acks the given delivery first, then blocks until a worker_done, escalation, question, heartbeat or status arrives.
# Prints PID=<pid> first (kill that pid to stop the wait; this script execs, so it is the reader's own pid), then the
# messages as tools/orca_inbox.py prints them, DELIVERY=<id> last.
set -euo pipefail
reader="$(cd "$(dirname "$0")/../../.." && pwd)/tools/orca_inbox.py"
ack=()
if [[ $# -gt 0 && "$1" != -* ]]; then
  [[ -n "$1" ]] && ack=(--ack "$1")
  shift
fi
exec python3 "$reader" --wait --types worker_done,escalation,question,heartbeat,status ${ack[@]+"${ack[@]}"} "$@"
