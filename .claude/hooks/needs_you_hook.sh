#!/usr/bin/env bash
# Claude Code hook: a macOS banner with the question, and a spoken "<worktree> needs you", only when a session is
# waiting on the user — an AskUserQuestion (PreToolUse: the question and its options), a permission prompt or an
# agent needing input (Notification), or a reply whose last paragraph ends by asking something (Stop). Everything
# else stays silent; the built-in notifications are off (preferredNotifChannel) so this is the one source. The
# banner is titled with the session's folder, so an Orca worktree says which worker is asking. Wired in
# .claude/settings.json.
#
# Mute the voice (keep the banner): "mute": true in .claude/hooks/needs_you.json of the main checkout, which every
# worktree reads, so one switch quiets every agent; missing means unmuted. NEEDS_YOU_DRY_RUN=1 prints instead.
set -uo pipefail

input=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$input")
session=$(jq -r '.session_id // "none"' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
# The worktree the session runs in, by its root folder (Orca names it after the task); the main checkout is "main".
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null)
common=$(git -C "${cwd:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -n "$root" ] && [ "$root" = "$(dirname "$common")" ]; then
  agent=main
else
  agent=$(basename "${root:-${cwd:-$PWD}}")
fi

# Markdown stripped so the text reads and sounds clean.
clean() {
  sed -E -e 's/`([^`]*)`/\1/g' -e 's/\*\*?([^*]*)\*\*?/\1/g' -e 's/\[([^]]*)\]\([^)]*\)/\1/g' -e 's/^[#>*-]+ *//' \
    | tr -s ' \n' ' ' | sed -E 's/^ +| +$//g'
}

case "$event" in
  PreToolUse)
    text=$(jq -r '[.tool_input.questions[]? |
             .question + ([.options[]?.label] | if length > 0 then " Options: " + join(", ") else "" end)]
             | join(" Next: ")' <<<"$input")
    ;;
  Notification)
    case "$(jq -r '.notification_type // empty' <<<"$input")" in
      permission_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog) ;;
      *) exit 0 ;;
    esac
    text=$(jq -r '.message // "Needs your attention"' <<<"$input")
    ;;
  Stop)
    # The last sentence ending in "?" of the reply's final paragraph, code fences dropped; none, no alert.
    last_para=$(jq -r '.last_assistant_message // empty' <<<"$input" |
      awk '/^```/{f=!f; next} !f' | awk 'BEGIN{RS=""} {p=$0} END{print p}')
    text=$(printf '%s' "$last_para" | clean |
      perl -ne 'for (split /(?<=[.!?])\s+/) { $q = $_ if /\?$/ } END { print $q }')
    ;;
  *) exit 0 ;;
esac

text=$(printf '%s' "$text" | clean | cut -c1-400)
[ -z "$text" ] && exit 0

# One alert per session per 5s: a question can trip two events at once.
stamp="${TMPDIR:-/tmp}/needs-you.$session"
now=$(date +%s)
[ -f "$stamp" ] && [ $((now - $(cat "$stamp"))) -lt 5 ] && exit 0
echo "$now" >"$stamp"

if [ -n "${NEEDS_YOU_DRY_RUN:-}" ]; then
  printf '%s | %s\n' "$agent" "$text"
  exit 0
fi

osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name "Glass"' \
  -e 'end run' "Claude · $agent" "$text" >/dev/null 2>&1

# Spoken in the background, one voice at a time across every session.
hooks_dir=$(cd "$(dirname "$0")" && pwd)
git_common=$(git -C "$hooks_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
settings=${git_common:+$(dirname "$git_common")/.claude/hooks/needs_you.json}
[ -f "${settings:-}" ] || settings=$hooks_dir/needs_you.json
if [ "$(jq -r '.mute // false' "$settings" 2>/dev/null)" != "true" ]; then
  nohup /usr/bin/lockf -k "${TMPDIR:-/tmp}/needs-you.say.lock" /usr/bin/say -- "${agent//[-_]/ } needs you" \
    >/dev/null 2>&1 &
fi
exit 0
