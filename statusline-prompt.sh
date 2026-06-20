#!/usr/bin/env bash
# claude-statusline-prompt — pin the current prompt to your Claude Code statusline.
#
# Renders whatever statusline you already had (saved at install time as
# statusline-prompt.inner), then appends one line showing the current prompt —
# or a short LLM "gist" of it when available — so you never scroll to the top to
# remember what you asked.
#
# Config (environment overrides, all optional):
#   CCSL_COLOR   ANSI color code for the prompt text   (default 92 = bright green)
#   CCSL_MARKER  Leading marker                         (default ">")
#   CCSL_GIST    1 = prefer cached LLM gist, 0 = always raw prompt (default 1)
#
# The statusline JSON Claude Code pipes in gives us transcript_path + session_id;
# the prompt text is read from the transcript, the gist from the cache the
# UserPromptSubmit hook writes.

input=$(cat)

base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
inner_file="$base/statusline-prompt.inner"
cache_dir="$base/statusline-prompt-cache"

color="${CCSL_COLOR:-92}"
marker="${CCSL_MARKER:->}"
use_gist="${CCSL_GIST:-1}"

# Terminal width (statusline JSON doesn't carry it reliably).
cols=${COLUMNS:-}
case "$cols" in ""|*[!0-9]*) cols=$(stty size </dev/tty 2>/dev/null | awk '{print $2}');; esac
case "$cols" in ""|*[!0-9]*) cols=120;; esac

# Render the wrapped (original) statusline, if one was saved.
inner=$(cat "$inner_file" 2>/dev/null)
hud=""
if [ -n "$inner" ]; then
  hud=$(printf '%s' "$input" | bash -c "$inner" 2>/dev/null)
fi

# Resolve the prompt line text (gist if cached & fresh, else truncated raw prompt).
prompt=$(printf '%s' "$input" | CCSL_COLS="$cols" CCSL_CACHE="$cache_dir" CCSL_USE_GIST="$use_gist" python3 -c '
import sys, json, os, hashlib

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tp = data.get("transcript_path") or data.get("transcriptPath") or ""
session = data.get("session_id") or data.get("sessionId") or ""

def textify(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(b.get("text", "") for b in c
                         if isinstance(b, dict) and b.get("type") == "text")
    return None

last_prompt = None
last_user = None
if tp and os.path.exists(tp):
    try:
        with open(tp, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                t = o.get("type")
                if t == "last-prompt":
                    lp = o.get("lastPrompt")
                    if lp:
                        last_prompt = lp
                elif t == "user" and not o.get("isMeta"):
                    m = o.get("message", {}) or {}
                    c = m.get("content")
                    if isinstance(c, list) and any(
                        isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
                        continue
                    tx = textify(c)
                    if tx and tx.strip():
                        last_user = tx
    except Exception:
        pass

raw = (last_prompt or last_user or "").strip()
if not raw:
    sys.exit(0)

display = None
if os.environ.get("CCSL_USE_GIST", "1") == "1" and session:
    gp = os.path.join(os.environ.get("CCSL_CACHE", ""), session + ".gist")
    if os.path.exists(gp):
        try:
            with open(gp, encoding="utf-8") as f:
                g = json.load(f)
            digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()
            if g.get("hash") == digest and g.get("gist"):
                display = g["gist"]
        except Exception:
            pass

if not display:
    display = raw

s = " ".join(display.split())
cols = int(os.environ.get("CCSL_COLS", "120") or 120)
budget = max(20, cols - 6)
if len(s) > budget:
    s = s[:budget - 1] + "…"
print(s)
')

[ -n "$hud" ] && printf '%s' "$hud"
if [ -n "$prompt" ]; then
  pre=""
  [ -n "$hud" ] && pre=$'\n'
  printf '%s\033[1;%sm%s\033[0m \033[%sm%s\033[0m' "$pre" "$color" "$marker" "$color" "$prompt"
fi
