#!/usr/bin/env python3
"""Background worker for claude-statusline-prompt.

Reads the UserPromptSubmit payload (a temp JSON file), asks a fast model for a
terse "gist" of the prompt via `claude -p`, and writes it to the per-session
cache the statusline reads. Runs detached; failures are silent (the statusline
just falls back to the truncated raw prompt).

Cache file: <config>/statusline-prompt-cache/<session_id>.gist
  {"hash": "<sha1 of stripped prompt>", "gist": "<short label>"}
The hash lets the statusline show the gist only for the exact current prompt.
"""

import sys
import os
import json
import hashlib
import shutil
import subprocess
import tempfile

TIMEOUT_S = int(os.environ.get("CCSL_GIST_TIMEOUT", "60") or 60)


def find_claude():
    candidates = [
        os.environ.get("CCSL_CLAUDE_BIN"),
        os.path.expanduser("~/.local/bin/claude"),
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        shutil.which("claude"),
    ]
    for c in candidates:
        # Skip shell-function shims; we need a real executable file.
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


def main():
    if len(sys.argv) < 2:
        return
    tmp = sys.argv[1]
    try:
        with open(tmp, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass

    prompt = (data.get("prompt") or "").strip()
    session = data.get("session_id") or data.get("sessionId") or ""
    if not prompt or not session:
        return

    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    cache = os.path.join(base, "statusline-prompt-cache")
    os.makedirs(cache, exist_ok=True)

    claude = find_claude()
    if not claude:
        return

    model = os.environ.get("CCSL_GIST_MODEL", "haiku")
    words = os.environ.get("CCSL_GIST_WORDS", "8")
    instruction = (
        "Summarize this instruction as a terse imperative task label of at most "
        + str(words)
        + " words. Output ONLY the label text: no quotes, no markdown, no "
        "trailing punctuation."
    )

    env = dict(os.environ)
    env["CCSL_NO_GIST"] = "1"  # stop the nested `claude -p` from re-triggering the hook
    try:
        proc = subprocess.run(
            [claude, "-p", instruction, "--model", model],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_S,
            cwd=os.path.expanduser("~"),  # neutral cwd: don't load the project's context
            env=env,
        )
    except Exception:
        return

    # Only trust a clean exit — a non-zero code means auth failure ("Not logged
    # in"), a bad model, etc. Never cache an error string as if it were a gist.
    if proc.returncode != 0:
        return

    out = (proc.stdout or "").strip()
    gist = out.splitlines()[0].strip() if out else ""
    # Defensive cleanup: strip wrapping quotes / trailing punctuation a model might add.
    gist = gist.strip('"\'' ).rstrip(".")
    if not gist:
        return

    payload = json.dumps(
        {"hash": hashlib.sha1(prompt.encode("utf-8")).hexdigest(), "gist": gist}
    )
    try:
        fd, t2 = tempfile.mkstemp(dir=cache)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(payload)
        os.replace(t2, os.path.join(cache, session + ".gist"))
    except Exception:
        return


if __name__ == "__main__":
    main()
