#!/usr/bin/env bash
# UserPromptSubmit hook for claude-statusline-prompt.
#
# Fires once when you submit a prompt. Kicks off a background worker that asks a
# fast model for a short "gist" of the prompt and caches it for the statusline.
#
# IMPORTANT: UserPromptSubmit hook stdout is injected into the conversation as
# extra context — so this prints NOTHING. It just backgrounds the work and exits.
#
# Recursion guard: the worker runs `claude -p` to summarize, which would itself
# trigger this hook. The worker sets CCSL_NO_GIST=1 for that nested call, and we
# bail immediately when we see it.

[ -n "$CCSL_NO_GIST" ] && exit 0

input=$(cat)

base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
worker="$base/statusline-prompt-gist-worker.py"
[ -f "$worker" ] || exit 0

tmp=$(mktemp "${TMPDIR:-/tmp}/ccsl-prompt.XXXXXX") || exit 0
printf '%s' "$input" > "$tmp"

# Detach fully so prompt submission is never blocked by the summary call.
nohup python3 "$worker" "$tmp" >/dev/null 2>&1 &

exit 0
