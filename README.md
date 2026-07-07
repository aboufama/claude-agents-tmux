# claude-agents-tmux

Mission control for running many [Claude Code](https://claude.com/claude-code) agents at once. One `claude` command turns every folder into a workspace full of agents, backed by [herdr](https://herdr.dev) when it's installed and plain tmux when it's not.

The important things this handles:

- One persistent session (`agents`) holds all your agentic work. Running `claude` either creates the current folder's workspace or drops you back into it, agents intact.
- `claude 3` opens three permission-bypassed Claude agents side by side in a single root folder.
- Every agent shows its model, effort level, fresh session tokens, and API-price cost.
- With herdr installed (the installer sets it up), you also get a sidebar of every folder with each agent's live state (working / blocked / done / idle), locally or attached to a cloud host.
- Agents survive closed terminal windows, dropped SSH, and wifi blips. Reattach by typing `claude` again.

```
┌ ⣷◆ Fable 5 · high ────────────────┬ ⡪✦ Fable 5 · high ─────────────────┐
│                                   │                                    │
│  agent 1                          │  agent 2                           │
│                                   │                                    │
└───────────────────────────────────┴────────────────────────────────────┘
  1 game-engine 2d4h   2 website 3h   3 api 41m
```

## How it works

The same mental model on both backends:

- **Workspace = folder, always exactly one.** Typing `claude` in any project opens (or rejoins) that folder's workspace in the `agents` session, no matter where you type it. New folder → new workspace. Same folder → same workspace, same running agents. On tmux, duplicate tabs for one folder (e.g. two `claude`s racing) are automatically merged back into one.
- **Pane = agent.** `claude 4` gives the current folder four *running* agents in a tiled layout. Inside the folder's own workspace, `claude 3` turns the current pane into an agent plus two siblings. Idle shell panes are relaunched in place before any new splits are added.
- **Exiting an agent never kills the pane.** Ctrl-C / `/exit` / a crash drops the pane to a normal shell in the same folder: type `claude` to relaunch, or `exit` to actually close the pane.
- **Every pane is labeled.** A procedural sigil (a glyph pair hashed from the pane id, stable and unique per split) plus the agent's model, effort level, fresh session tokens (input + output + cache writes, so cache reads don't inflate the number), and the session's API-price cost (`· 843k tok · $2.80`). On herdr this lives on the pane box title and, since a lone pane draws no box, on Claude Code's own status line inside the pane; the sidebar keeps herdr's plain agent rows. On tmux it lives on the pane border, colored, with Claude Code's spinner themed to match.
- **No trust popups.** The wrapper pre-accepts Claude Code's "Do you trust the files in this folder?" dialog before spawning panes, so a burst of new agents doesn't stall on one prompt per pane. This covers the home directory too: Claude Code never saves an interactive acceptance for `~`, but it does honor a pre-seeded one, and the wrapper re-seeds on every launch.
- **On herdr**, the sidebar lists every folder with its agents' live states rolled up per folder, so "which project needs me" is one glance instead of tab-cycling. **On tmux**, each folder tab shows its running age in the status bar (dim under a day, amber at 1–3 days, red past 3 days), so long-forgotten agents stand out.

Agents run under `caffeinate`, so your Mac won't idle-sleep while they work.

## Install

One command:

```sh
git clone https://github.com/aboufama/claude-agents-tmux ~/.claude-agents-tmux && ~/.claude-agents-tmux/install.sh
```

(Or clone anywhere you like and run `./install.sh` from the checkout.)

The installer copies the scripts to `~/.claude/agents-tmux/`, appends a `source` line for `claude-agents.zsh` to your `~/.zshrc`, and wires the `statusLine` hook into `~/.claude/settings.json` (your previous settings file is backed up as `settings.json.bak`). It also installs the backends if they're missing: herdr via the official installer (needs ≥ 0.7.2; Homebrew's is older and draws a focus marker on pane titles) plus `jq`, and tmux via Homebrew as the fallback.

Then open a new terminal (or `source ~/.zshrc`) and run `claude`.

The wrapper picks herdr automatically whenever `herdr` and `jq` are on your PATH, and tmux otherwise. To pin a backend explicitly, `echo tmux > ~/.claude/agents-tmux/backend` (or `echo herdr`), or set `CLAUDE_AGENTS_BACKEND` per call.

## Usage

| Command | Effect |
|---|---|
| `claude` | Open/rejoin the `agents` session at this folder's workspace |
| `claude 4` | Ensure this folder has 4 running agents |
| `claude` (inside this folder's workspace) | Current pane becomes an agent |
| `claude 3` (inside this folder's workspace) | Current pane becomes an agent + 2 sibling splits |
| `claude -p ...`, `claude mcp`, pipes | Pass through untouched, no multiplexer |
| `tmux` (bare, outside tmux) | Asks "open the agents manager?" `y` attaches to `agents`, anything else is stock tmux |

The prefix key is `Ctrl-b` on both backends, so the muscle memory carries over: `z` zoom a pane full-screen, `n`/`p` next/previous tab, detach with `d` (tmux) or `q` (herdr). Agents keep running after detach.

## Cloud mode

Everything above runs on your machine, which means agents stall the moment the laptop sleeps or drops off wifi. Cloud mode moves the whole `agents` session to an always-on host; your laptop becomes a detachable window into it. Close the lid mid-task, reopen an hour later, type `claude`, and the agents never stopped.

Point the wrapper at your host once:

```sh
echo 'user@your-host' > ~/.claude/agents-tmux/remote
```

From then on, **remote is the default**: `claude` in any local folder opens that folder's workspace in the remote agents session (the local folder *name* maps to `~/work/<name>` on the host, so keep your repos cloned there). `claude 3` works the same way.

With the herdr backend, the attach is herdr's thin client: you keep local keybindings and native clipboard while every agent runs on the host, and the remote sidebar shows *all* your folders and agents on that box. Wifi drop or closed lid detaches the client; the server and agents never notice. On tmux, the attach is a plain SSH session, and the remote session marks itself with an amber `[remote]` tag in the status bar so you always know which side you're on.

If the host doesn't answer within 3 seconds, `claude` prints a notice and opens a local session instead; it always opens *something*. `CLAUDE_AGENTS_LOCAL=1 claude` forces a local session on purpose.

### Option A: bare VPS

Any $5 VM (Hetzner, DigitalOcean, EC2…):

```sh
ssh user@your-host
git clone https://github.com/aboufama/claude-agents-tmux && ./claude-agents-tmux/install.sh
claude setup-token        # authenticate once (needs a Claude subscription)
mkdir -p ~/work && cd ~/work && git clone <your repos>
```

### Option B: Docker

The `cloud/` directory ships a ready image (Debian + zsh + Claude Code + herdr + tmux + this setup):

```sh
ssh user@your-host          # any machine with Docker
git clone https://github.com/aboufama/claude-agents-tmux && cd claude-agents-tmux/cloud
docker compose up -d --build
docker exec -it claude-agents claude setup-token    # authenticate once
```

Then on your laptop: `echo 'user@your-host docker' > ~/.claude/agents-tmux/remote`. The wrapper attaches through `docker exec` automatically; herdr's thin client can't reach inside a container, so the full herdr UI runs there over SSH instead. Auth and workspace live in named volumes (`claude-config`, `work`), so they survive image rebuilds and host reboots (`restart: unless-stopped`).

For flaky links, [mosh](https://mosh.org) instead of ssh makes reattaching instant, and for repo-scoped tasks with zero infrastructure, [Claude Code on the web](https://claude.ai/code) runs sessions in Anthropic-managed cloud sandboxes.

## Caveats

- zsh, macOS or Linux. `caffeinate` is macOS-only; on Linux, remove it from `scripts/agent-launch.sh` or swap in `systemd-inhibit`. The tmux fallback needs tmux ≥ 3.2.
- **The wrapper auto-appends `--dangerously-skip-permissions` to interactive agents.** That is the point of the setup (unattended agents that never stall on a prompt), but it means agents run without permission guardrails. Remove the `extra=(--dangerously-skip-permissions)` line in `claude-agents.zsh` if you don't want that.
- Per-pane spinner colors (tmux backend) work by dropping tiny theme files in `~/.claude/themes/` (named `agents-pane-*`) and passing `--settings '{"theme":"custom:..."}'` to each agent; your global theme is untouched.
- To survive a closed laptop lid you additionally need `sudo pmset -a disablesleep 1`.
