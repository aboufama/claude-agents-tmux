# claude-agents-tmux

A tmux mission-control setup for running many [Claude Code](https://claude.com/claude-code) agents at once.

One persistent tmux session (`agents`) holds all your agentic work:

- **Tab = folder, always exactly one.** Typing `claude` in any project opens (or rejoins) that folder's tab in the `agents` session. New folder → new tab. Same folder → same tab, same running agents. If duplicate tabs for one folder ever appear (e.g. two `claude`s racing), they're automatically merged back into one.
- **Pane = agent.** `claude 4` gives the current folder's tab four agent panes in a tiled layout. Inside tmux, `claude 3` splits the current window into three agents.
- **Tabs show their age.** Each tab's running time is rendered in the status bar — dim under a day, amber at 1–3 days, red past 3 days, so long-forgotten agents stand out.
- **Every pane has a color identity.** The pane border shows a procedural sigil (a color + glyph pair hashed from the pane id, stable and unique per split) plus the agent's model and effort level — nothing more, so borders stay quiet. Claude Code's own spinner line inside the pane is themed to the same color, so you always know which agent you're looking at.

```
┌───────────────────────────────────┬────────────────────────────────────┐
│                                   │                                    │
│  agent 1                          │  agent 2                           │
│                                   │                                    │
└ ⣷◆ Fable 5 · high ────────────────┴ ⡪✦ Fable 5 · high ─────────────────┘
  1 game-engine 2d4h   2 website 3h   3 api 41m
```

The HUD sits on each pane's *bottom* border, so it's always fully inside the terminal window — never clipped by the top edge or rounded corners.

Agents run under `caffeinate`, so your Mac won't idle-sleep while they work, and they survive closed terminal windows, dropped SSH, and wifi blips — reattach by typing `claude` again in the same folder.

## Install

One command:

```sh
git clone https://github.com/aboufama/claude-agents-tmux ~/.claude-agents-tmux && ~/.claude-agents-tmux/install.sh
```

(Or clone anywhere you like and run `./install.sh` from the checkout.)

The installer copies the scripts to `~/.claude/agents-tmux/`, appends a `source` line for `claude-agents.zsh` to your `~/.zshrc`, and wires the `statusLine` hook into `~/.claude/settings.json` automatically (your previous settings file is backed up as `settings.json.bak`). If `python3` isn't available it prints the snippet to add by hand instead.

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

- tmux ≥ 3.2, zsh, macOS (`caffeinate` is macOS-only — on Linux, remove it from `scripts/agent-launch.sh` or swap in `systemd-inhibit`).
- **The wrapper auto-appends `--dangerously-skip-permissions` to interactive agents.** That is the point of the setup — unattended agents that never stall on a prompt — but it means agents run without permission guardrails. Remove the `extra=(--dangerously-skip-permissions)` line in `claude-agents.zsh` if you don't want that.
- Per-pane spinner colors work by dropping tiny theme files in `~/.claude/themes/` (named `agents-pane-*`) and passing `--settings '{"theme":"custom:..."}'` to each agent; your global theme is untouched.
- To survive a closed laptop lid you additionally need `sudo pmset -a disablesleep 1`.
