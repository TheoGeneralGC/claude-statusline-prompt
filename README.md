# claude-statusline-prompt

Pin your **current prompt** to the Claude Code statusline so you never scroll to
the top to remember what you asked. Works alongside whatever statusline you
already use ([claude-hud](https://github.com/jarrodwatts/claude-hud),
ccstatusline, claude-powerline, a custom script, or nothing) — it **wraps** it
and adds one extra line:

```
[Opus]  OneTrip  git:(main)   Context ▓▓▓░░ 38%   ✓ Bash ×12 | ✓ Edit ×3
> Deploy OneTrip frontend and backend to onetripsearch.com/115
```

That last green line is the gist of your current prompt. For long prompts it
shows a short LLM-generated summary; until that lands (or if you disable it) it
shows the prompt itself, truncated to your terminal width.

## How it works

Claude Code can't put your prompt in the statusline directly — the statusline's
input JSON doesn't contain it. But it **does** include `transcript_path` and
`session_id`, and the transcript records your prompt (a `last-prompt` entry). So:

- **`statusline-prompt.sh`** (statusline command) renders your previous
  statusline, then reads the latest prompt from the transcript and appends it.
- **`statusline-prompt-gist-hook.sh`** (a `UserPromptSubmit` hook) fires once per
  prompt and, in the background, asks a fast model for a ~8-word "gist".
- **`statusline-prompt-gist-worker.py`** does that summary via `claude -p`
  (reusing your existing Claude Code auth — no API key needed) and writes it to a
  per-session cache, keyed by a hash of the prompt so a stale gist is never shown.

The statusline only ever *reads* the cache, so rendering stays instant. The gist
call happens once per prompt, detached, and never blocks you.

## Install

```bash
git clone https://github.com/<you>/claude-statusline-prompt
cd claude-statusline-prompt
./install.sh
```

Then start a new Claude Code session (or run `/statusline`). Requires `bash` and
`python3` (both standard on macOS/Linux). The installer is idempotent and saves
your previous statusline so it can be restored.

Undo anytime:

```bash
./uninstall.sh
```

## Configuration

Set these in your shell environment (e.g. `~/.zshrc`); all optional:

| Variable           | Default       | Meaning                                            |
| ------------------ | ------------- | -------------------------------------------------- |
| `CCSL_COLOR`       | `92`          | ANSI color of the prompt line (92 = bright green)  |
| `CCSL_MARKER`      | `>`           | Leading marker for the line                        |
| `CCSL_GIST`        | `1`           | `1` = prefer the LLM gist, `0` = always raw prompt |
| `CCSL_GIST_MODEL`  | `haiku`       | Model alias used for the summary                    |
| `CCSL_GIST_WORDS`  | `8`           | Target max words in the gist                        |
| `CCSL_GIST_TIMEOUT`| `60`          | Seconds to wait for the summary before giving up    |
| `CCSL_CLAUDE_BIN`  | auto-detected | Path to the `claude` binary, if not auto-found      |

To run **without** any LLM calls, set `CCSL_GIST=0` — you'll get the raw prompt,
truncated. (No summary calls are made at all in that mode.)

## Notes & caveats

- **Multi-line statuslines** must be supported by your Claude Code version (they
  are in current releases; the wrapped statusline appears above, the prompt below).
- The gist uses one small `claude -p` call per prompt. It runs detached and is
  guarded against recursively re-triggering its own hook.
- Everything fails safe: if the transcript can't be read or the summary fails,
  the statusline still renders (just without the prompt line, or with the raw one).
- Reads only your local transcript and writes only a small cache under your Claude
  config dir. Nothing leaves your machine except the prompt text sent to the model
  you already use for the gist.

## License

MIT — see [LICENSE](./LICENSE).
