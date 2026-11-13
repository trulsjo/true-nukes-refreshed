---
prefix: tn
---

# Review panel

The agents that review this repository's pull requests, through the `review-panel` skill: each in a
Herdr app space `tn-<agent>`, working in its own worktree beside the checkout,
`true-nukes-refreshed-panel/<agent>`, detached at `origin/main`. `panel.py up` starts what is not
running.

| Agent | Command | Clear |
|---|---|---|
| codex | `codex --no-daemon` | `/clear` |
| antigravity | `agy` | `/clear` |
| fable | `claude --model claude-fable-5-2` | `/clear` |

- **Agent**: the space's suffix and the answer file's name; `a-z`, `0-9`, `-` and `_`.
- **Command**: the bare command with its model; the app wraps it in `pwsh -NoExit -Command`.
  Codex needs `--no-daemon`, or its commands run outside hc.
- **Clear**: what `panel.py reset` sends to start a new conversation; empty means `/clear`. A clear
  keeps the program and its model: after editing a Command, run `panel.py up --restart`.

Why each agent and model: codex, antigravity and fable are the three agents that reviewed this
repository's pull requests before this file, in the spaces `tn-codex`, `tn-antigravity` and
`tn-fable`. Fable runs on `claude-fable-5-2`, the model grado-factorio-tools' panel moved its fable
lane to on 2026-11-13 at Truls's request; the earlier `tn-fable` ran `claude-fable-5-1`.
