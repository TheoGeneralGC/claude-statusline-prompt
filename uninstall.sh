#!/usr/bin/env bash
# Uninstaller for claude-statusline-prompt.
# Restores your previous statusline command and removes the gist hook. Leaves the
# copied scripts and cache in place (delete them by hand if you like).
set -euo pipefail

BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$BASE/settings.json"

command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }
[ -f "$SETTINGS" ] || { echo "no settings.json at $SETTINGS; nothing to do"; exit 0; }

BASE="$BASE" SETTINGS="$SETTINGS" python3 - <<'PYEOF'
import json, os

base = os.environ["BASE"]
settings = os.environ["SETTINGS"]
hook_cmd = "bash %s/statusline-prompt-gist-hook.sh" % base
inner_file = os.path.join(base, "statusline-prompt.inner")

with open(settings, encoding="utf-8") as f:
    data = json.load(f)

# Restore the wrapped statusline (or drop it if there was none).
inner = ""
if os.path.exists(inner_file):
    with open(inner_file, encoding="utf-8") as f:
        inner = f.read().strip()
if inner:
    data["statusLine"] = {"type": "command", "command": inner}
    print("restored previous statusline")
else:
    data.pop("statusLine", None)
    print("removed statusLine (there was no prior one)")

# Remove our UserPromptSubmit hook entry.
ups = (data.get("hooks") or {}).get("UserPromptSubmit")
if isinstance(ups, list):
    kept = []
    for g in ups:
        hs = [h for h in g.get("hooks", []) if not (isinstance(h, dict) and h.get("command") == hook_cmd)]
        if hs:
            g = dict(g); g["hooks"] = hs; kept.append(g)
        elif not g.get("hooks"):
            kept.append(g)  # unrelated/empty group, keep as-is
        # else: group existed only for our hook -> drop it
    if kept:
        data["hooks"]["UserPromptSubmit"] = kept
    else:
        data["hooks"].pop("UserPromptSubmit", None)
        if not data["hooks"]:
            data.pop("hooks", None)
    print("removed gist hook")

with open(settings, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("updated %s" % settings)
PYEOF

echo "✓ uninstalled. Restart your Claude Code session to apply."
