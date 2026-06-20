#!/usr/bin/env bash
# Installer for claude-statusline-prompt.
#
# - Copies the wrapper + gist hook + worker into your Claude config dir.
# - Saves your CURRENT statusline command so the wrapper keeps rendering it.
# - Points statusLine.command at the wrapper and registers the UserPromptSubmit
#   gist hook in settings.json.
#
# Safe to re-run (idempotent). Requires: bash, python3. Undo with ./uninstall.sh.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$BASE/settings.json"

command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }
mkdir -p "$BASE" "$BASE/statusline-prompt-cache"

for f in statusline-prompt.sh statusline-prompt-gist-hook.sh statusline-prompt-gist-worker.py; do
  cp "$SRC_DIR/$f" "$BASE/$f"
  chmod +x "$BASE/$f"
done

BASE="$BASE" SETTINGS="$SETTINGS" python3 - <<'PYEOF'
import json, os

base = os.environ["BASE"]
settings = os.environ["SETTINGS"]
wrapper = "bash %s/statusline-prompt.sh" % base
hook_cmd = "bash %s/statusline-prompt-gist-hook.sh" % base
inner_file = os.path.join(base, "statusline-prompt.inner")

data = {}
if os.path.exists(settings):
    try:
        with open(settings, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        print("warning: settings.json is not valid JSON; aborting to avoid clobbering it")
        raise SystemExit(1)

# Preserve the existing statusline as the "inner" command we wrap, unless it's
# already our wrapper (don't wrap ourselves).
sl = data.get("statusLine") or {}
cur = sl.get("command", "")
if cur and "statusline-prompt.sh" not in cur:
    with open(inner_file, "w", encoding="utf-8") as f:
        f.write(cur)
    print("saved your previous statusline -> %s" % inner_file)
elif not os.path.exists(inner_file):
    open(inner_file, "w").close()  # no prior statusline; wrapper shows just the prompt line
    print("no prior statusline found; the prompt line will render on its own")

data["statusLine"] = {"type": "command", "command": wrapper}

# Register the UserPromptSubmit gist hook (idempotent).
hooks = data.setdefault("hooks", {})
ups = hooks.setdefault("UserPromptSubmit", [])
already = any(
    isinstance(g, dict)
    and any(isinstance(h, dict) and h.get("command") == hook_cmd for h in g.get("hooks", []))
    for g in ups
)
if not already:
    ups.append({"hooks": [{"type": "command", "command": hook_cmd}]})
    print("registered UserPromptSubmit gist hook")
else:
    print("gist hook already registered")

with open(settings, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("updated %s" % settings)
PYEOF

echo
echo "✓ installed. Open a new Claude Code session (or run /statusline) to see it."
echo "  Config (set in your shell env): CCSL_COLOR, CCSL_MARKER, CCSL_GIST,"
echo "  CCSL_GIST_MODEL (default: haiku), CCSL_GIST_WORDS (default: 8)."
echo "  Undo with: $SRC_DIR/uninstall.sh"
