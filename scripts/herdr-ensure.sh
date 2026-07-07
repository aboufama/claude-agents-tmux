#!/bin/sh
# Ensure the herdr agents session has a workspace for a folder with N
# running Claude agents, mirroring the tmux layout: workspace = folder,
# pane = agent. Runs on whichever machine hosts the herdr server (your
# Mac, or the cloud host over ssh); the zsh wrapper calls it before
# attaching. Agents are launched *inside* a shell (pane run), so exiting
# an agent drops the pane to a prompt instead of closing it, and idle
# shell panes are relaunched in place before any new splits are added —
# same rules as the tmux backend.
# Usage: herdr-ensure.sh <n> <folder> <claude-bin> [claude args...]
# Env:   CLAUDE_AGENTS_SESSION  herdr session name (default: agents)
#        CLAUDE_AGENTS_SELF_PANE  pane about to become an agent by the
#                                 caller itself; counted, never touched.
set -u
n="$1"; dir="$2"; bin="$3"; shift 3

command -v herdr >/dev/null 2>&1 || {
  echo "claude-agents: herdr not found — install it first (brew install herdr)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || {
  echo "claude-agents: the herdr backend needs jq (brew install jq)" >&2; exit 1; }

HERDR_SESSION="${CLAUDE_AGENTS_SESSION:-agents}"
export HERDR_SESSION
unset HERDR_SOCKET_PATH 2>/dev/null || true

# Server up? `herdr status server` exits 0 either way, so parse the
# output. Start it headless and wait for the socket to answer.
server_up() { herdr status server 2>/dev/null | grep -q '^status: running'; }
if ! server_up; then
  nohup herdr server >/dev/null 2>&1 &
  i=0
  while ! server_up; do
    i=$((i + 1)); [ "$i" -gt 100 ] && {
      echo "claude-agents: herdr server for session '$HERDR_SESSION' did not start" >&2; exit 1; }
    sleep 0.1
  done
fi

# Pre-accept Claude Code's folder-trust dialog (same key the dialog writes),
# so a burst of new panes never stalls on one prompt each.
cfg="$HOME/.claude.json"
if [ -r "$cfg" ]; then
  if ! jq -e --arg p "$dir" '.projects[$p].hasTrustDialogAccepted == true' "$cfg" >/dev/null 2>&1; then
    tmp="$cfg.agents-tmux.$$"
    if jq --arg p "$dir" \
         '.projects[$p] = (.projects[$p] // {}) + {hasTrustDialogAccepted: true}' \
         "$cfg" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      mv -f "$tmp" "$cfg"
    else
      rm -f "$tmp"
    fi
  fi
fi

# The command each agent pane runs, typed into the pane's shell so the
# pane survives the agent exiting. agent-launch.sh keeps caffeinate on
# macOS and is a plain exec of the binary elsewhere.
run="$HOME/.claude/agents-tmux/agent-launch.sh '$bin' --dangerously-skip-permissions"
for a in "$@"; do
  run="$run '$(printf '%s' "$a" | sed "s/'/'\\\\''/g")'"
done

# One workspace per folder: find it by the recorded pane cwd, else create.
ws="$(herdr pane list | jq -r --arg d "$dir" \
  '[.result.panes[] | select(.cwd == $d)][0].workspace_id // empty')"
tag="$(basename "$dir" | tr -c 'A-Za-z0-9_-' '-' | sed 's/-*$//')"
fresh=""
if [ -z "$ws" ]; then
  ws="$(herdr workspace create --cwd "$dir" --label "$tag" --focus \
    | jq -r '.result.workspace.workspace_id')"
  [ -n "$ws" ] && [ "$ws" != null ] || {
    echo "claude-agents: failed to create herdr workspace for $dir" >&2; exit 1; }
  fresh=1
else
  herdr workspace focus "$ws" >/dev/null
fi

# Count running agents; collect idle shell panes for relaunch-in-place.
# A just-created workspace's initial pane hasn't started its shell yet,
# so process-info would miss it — treat all panes of a fresh workspace
# as idle instead of scanning.
self="${CLAUDE_AGENTS_SELF_PANE:-}"
agents="$(herdr agent list | jq -r --arg w "$ws" \
  '[.result.agents[] | select(.workspace_id == $w) | .pane_id] | join(" ")')"
have=0; for p in $agents; do have=$((have + 1)); done
idle=""
for p in $(herdr pane list --workspace "$ws" | jq -r '.result.panes[].pane_id'); do
  [ "$p" = "$self" ] && { have=$((have + 1)); continue; }
  case " $agents " in *" $p "*) continue ;; esac
  if [ -n "$fresh" ]; then idle="$idle $p"; continue; fi
  fg="$(herdr pane process-info --pane "$p" \
    | jq -r '.result.process_info.foreground_processes[0].name // empty')"
  case "$fg" in zsh|bash|sh|fish|-zsh|-bash) idle="$idle $p" ;; esac
done

for p in $idle; do
  [ "$have" -ge "$n" ] && break
  herdr pane run "$p" "cd '$dir' && $run" >/dev/null
  have=$((have + 1))
done

# Split off the rest, alternating direction for a roughly tiled layout.
at="$(herdr pane list --workspace "$ws" | jq -r '.result.panes[0].pane_id')"
while [ "$have" -lt "$n" ]; do
  d=right; [ $((have % 2)) -eq 0 ] && d=down
  p="$(herdr pane split --pane "$at" --direction "$d" --cwd "$dir" --no-focus \
    | jq -r '.result.pane.pane_id // .result.root_pane.pane_id // empty')"
  [ -n "$p" ] || { echo "claude-agents: herdr pane split failed" >&2; exit 1; }
  herdr pane run "$p" "$run" >/dev/null
  at="$p"
  have=$((have + 1))
done

echo "$ws"
