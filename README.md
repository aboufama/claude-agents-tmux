# claude-agents-tmux

A tmux mission-control setup for running many [Claude Code](https://claude.com/claude-code) agents at once.

One persistent tmux session (`agents`) holds all your agentic work:

- **Tab = folder.** Typing `claude` in any project opens (or rejoins) that folder's tab in the `agents` session. New folder → new tab. Same folder → same tab, same running agents.
- **Pane = agent.** `claude 4` gives the current folder's tab four agent panes in a tiled layout. Inside tmux, `claude 3` splits the current window into three agents.
- **Tabs show their age.** Each tab's running time is rendered in the status bar — dim under a day, amber at 1–3 days, red past 3 days, so long-forgotten agents stand out.
- **Every pane has a live HUD.** The pane border shows a procedural sigil (a color + glyph pair hashed from the pane id, stable and unique per split), the agent's model and effort level, and a live state: an animated spinner while the agent is working, or `idle 24m · $1.10` when it's quiet.

```
┌ ⣷◆ Fable 5 · high ⠹ working ──────┬ ⡪✦ Fable 5 · high idle 24m · $1.10 ┐
│                                   │                                    │
│  agent 1                          │  agent 2                           │
│                                   │                                    │
└───────────────────────────────────┴────────────────────────────────────┘
  1 game-engine 2d4h   2 website 3h   3 api 41m
```

Agents run under `caffeinate`, so your Mac won't idle-sleep while they work, and they survive closed terminal windows, dropped SSH, and wifi blips — reattach by typing `claude` again in the same folder.

## How the HUD works

Claude Code's `statusLine` hook runs `scripts/statusline.sh` on every status update. The script renders the in-app status line *and* writes a small state file keyed by `$TMUX_PANE`. tmux's `pane-border-format` runs `scripts/pane-status.sh` once per second per visible pane, which reads that state file: model and effort come straight from the hook payload (with a fallback to `~/.claude/settings.json`), and "working" simply means the state file was touched within the last few seconds.

## Install

```sh
./install.sh
```

This copies the scripts to `~/.claude/agents-tmux/`, appends a `source` line for `claude-agents.zsh` to your `~/.zshrc`, and prints the `statusLine` snippet to add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/agents-tmux/statusline.sh"
  }
}
```

Then open a new terminal (or `source ~/.zshrc`) and run `claude`.

## Usage

| Command | Effect |
|---|---|
| `claude` | Open/rejoin the `agents` session at this folder's tab |
| `claude 4` | Ensure this folder's tab has 4 agent panes |
| `claude` (inside tmux) | Current pane becomes an agent |
| `claude 3` (inside tmux) | Current pane becomes an agent + 2 sibling splits |
| `claude -p ...`, `claude mcp`, pipes | Pass through untouched, no tmux |

Handy tmux keys: `Ctrl-b z` zoom a pane full-screen, `Ctrl-b d` detach (agents keep running), `Ctrl-b n`/`p` next/previous tab.

## Requirements & caveats

- tmux ≥ 3.2, zsh, macOS (`caffeinate` is macOS-only — on Linux, remove it from `claude-agents.zsh` or swap in `systemd-inhibit`).
- **The wrapper auto-appends `--dangerously-skip-permissions` to interactive agents.** That is the point of the setup — unattended agents that never stall on a prompt — but it means agents run without permission guardrails. Remove the `extra=(--dangerously-skip-permissions)` line in `claude-agents.zsh` if you don't want that.
- To survive a closed laptop lid you additionally need `sudo pmset -a disablesleep 1`.

## Files

- `claude-agents.zsh` — the `claude` wrapper function
- `scripts/statusline.sh` — Claude Code statusLine hook; feeds per-pane state files
- `scripts/pane-status.sh` — renders each pane's border HUD
- `scripts/tab-age.sh` — renders each tab's age badge
- `install.sh` — copies everything into place
