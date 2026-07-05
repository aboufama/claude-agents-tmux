# >>> claude-agents: one tmux session for everything; tab = folder; panes = agents >>>
# `claude`    → open (or rejoin) the "agents" session at this folder's tab
# `claude 3`  → this folder's tab has 3 agent panes (adds splits as needed)
# Inside tmux → the current pane becomes an agent; `claude 3` adds 2 siblings
# One tab per folder, always: duplicate tabs for the same path get merged
# back into the first one. Tabs show a running-age badge (amber >1d, red >3d).
# Every agent pane's border shows a procedural sigil + model · effort,
# fed by the Claude Code statusLine hook (~/.claude/agents-tmux/).
# Agents run under caffeinate and survive closed terminals / wifi drops.
claude() {
  emulate -L zsh
  local bin
  if [[ -n "${CLAUDE_TMUX_BIN:-}" ]]; then bin="$CLAUDE_TMUX_BIN"
  else bin="$(whence -p claude)" || bin="$HOME/.local/bin/claude"
  fi

  # Pass through untouched: pipes/scripts and quick one-shot commands.
  if [[ -z "${CLAUDE_TMUX_TEST:-}" && ( ! -t 0 || ! -t 1 ) ]]; then
    "$bin" "$@"; return
  fi
  case "${1:-}" in
    -p|--print|-h|--help|-v|--version|mcp|config|update|doctor|install|migrate-installer|setup-token|plugin)
      "$bin" "$@"; return ;;
  esac

  local n=1
  if [[ "${1:-}" == <-> ]]; then
    n="$1"; shift
    (( n < 1 )) && n=1
    (( n > 12 )) && n=12
  fi

  # Remote mode: run the agents session on an always-on host so agents
  # survive the laptop sleeping or dropping off wifi. Configure once with
  #   echo 'user@host'        > ~/.claude/agents-tmux/remote   (bare host)
  #   echo 'user@host docker' > ~/.claude/agents-tmux/remote   (cloud/ container)
  # or export CLAUDE_AGENTS_HOST. The local folder NAME maps to
  # ~/work/<name> on the host. CLAUDE_AGENTS_LOCAL=1 claude → force local.
  local rconf="${CLAUDE_AGENTS_HOST:-}"
  [[ -z "$rconf" && -r "$HOME/.claude/agents-tmux/remote" ]] && \
    rconf="$(<"$HOME/.claude/agents-tmux/remote")"
  if [[ -n "$rconf" && -z "$TMUX" && -z "${SSH_CONNECTION:-}" && -z "${CLAUDE_AGENTS_LOCAL:-}" ]]; then
    local rhost="${rconf%% *}" rmode="${rconf#* }" rtag="${${PWD:t}//[^A-Za-z0-9_-]/-}"
    local rcmd="mkdir -p ~/work/$rtag && cd ~/work/$rtag && exec zsh -ilc 'claude $n'"
    [[ "$rmode" == "docker" ]] && \
      rcmd="docker exec -it claude-agents zsh -ilc 'mkdir -p ~/work/$rtag && cd ~/work/$rtag && claude $n'"
    if [[ -n "${CLAUDE_TMUX_TEST:-}" ]]; then print -r -- "ssh -t $rhost $rcmd"; return; fi
    # Only go remote if the host answers quickly; otherwise fall back to
    # a local session so `claude` always opens something.
    if ssh -o BatchMode=yes -o ConnectTimeout=3 "$rhost" true 2>/dev/null; then
      ssh -t "$rhost" "$rcmd"; return
    fi
    print -u2 "claude-agents: remote $rhost unreachable — opening local session"
  fi

  local -a extra
  [[ " $* " != *" --dangerously-skip-permissions "* ]] && extra=(--dangerously-skip-permissions)
  local -a qargs; qargs=("${(q)@}" "${(q)extra[@]}")
  local hud="$HOME/.claude/agents-tmux"
  # agent-launch.sh matches the Claude Code spinner color to the pane's
  # sigil and runs the agent under caffeinate.
  local run="$hud/agent-launch.sh $bin $qargs"

  # Inside tmux: this pane becomes an agent; a count adds sibling panes.
  if [[ -n "$TMUX" ]]; then
    tmux set -w pane-border-status top
    tmux set -w pane-border-format \
      ' #(exec '"$hud"'/pane-status.sh "#{pane_id}" "#{pane_current_command}") '
    # Claim this window for the folder so a later `claude` from outside
    # rejoins this tab instead of opening a duplicate.
    [[ -z "$(tmux show -w -v @agent_path 2>/dev/null)" ]] && \
      tmux set -w @agent_path "$PWD"
    [[ -z "$(tmux show -w -v @created 2>/dev/null)" ]] && \
      tmux set -w @created "$(date +%s)"
    local i
    for (( i = 2; i <= n; i++ )); do
      tmux split-window -d -c "$PWD" "$run"
      tmux select-layout tiled
    done
    [[ -n "${CLAUDE_TMUX_TEST:-}" ]] && return
    "$hud/agent-launch.sh" "$bin" "$@" "${extra[@]}"
    return
  fi

  local sess="${CLAUDE_TMUX_SESSION:-agents}"
  local tag="${${PWD:t}//[^A-Za-z0-9_-]/-}"
  local win="" line

  if ! tmux has-session -t "=$sess" 2>/dev/null; then
    # Fresh session → no live agents; sweep HUD state left by dead panes.
    command find "$hud/state" -name '*.env' -mmin +120 -delete 2>/dev/null
    win="$(tmux new-session -d -P -F '#{window_id}' -x 250 -y 80 -s "$sess" -n "$tag" -c "$PWD" "$run")"
    tmux set -t "$sess" status-interval 1
    tmux set -t "$sess" mouse on
    # Sessions living on a remote host (ssh or the cloud/ container) tag
    # themselves next to the session name in the status bar.
    [[ -n "${SSH_CONNECTION:-}" || -f /.dockerenv ]] && \
      tmux set -t "$sess" status-left "#[bold,fg=colour114] #S #[default]#[fg=colour178][remote]#[default] "
  else
    # Same folder → same tab: find it by the path recorded on the window.
    while IFS= read -r line; do
      [[ "${line#*$'\t'}" == "$PWD" ]] && { win="${line%%$'\t'*}"; break }
    done < <(tmux list-windows -t "$sess" -F $'#{window_id}\t#{@agent_path}')
    [[ -z "$win" ]] && win="$(tmux new-window -t "$sess" -P -F '#{window_id}' -n "$tag" -c "$PWD" "$run")"
  fi

  # One tab per folder: absorb any duplicate tabs for this path into $win.
  # (Duplicates can appear if two `claude`s race to create the tab.)
  local other pane
  while IFS= read -r line; do
    other="${line%%$'\t'*}"
    [[ "$other" == "$win" || "${line#*$'\t'}" != "$PWD" ]] && continue
    for pane in $(tmux list-panes -t "$other" -F '#{pane_id}'); do
      tmux join-pane -d -s "$pane" -t "$win" 2>/dev/null
    done
    tmux select-layout -t "$win" tiled
  done < <(tmux list-windows -t "$sess" -F $'#{window_id}\t#{@agent_path}')

  # Window bookkeeping (idempotent; @created only stamped once).
  [[ -z "$(tmux show -w -t "$win" -v @created 2>/dev/null)" ]] && \
    tmux set -w -t "$win" @created "$(date +%s)"
  tmux set -w -t "$win" @agent_path "$PWD"
  # Window options only stick per-window in tmux 3.x, so set them here
  # (runs for every window) rather than once on the session.
  tmux set -w -t "$win" window-status-format \
    ' #I #W #(exec '"$hud"'/tab-age.sh "#{@created}") '
  tmux set -w -t "$win" window-status-current-format \
    '#[bold] #I #W#{?window_zoomed_flag, +Z,} #(exec '"$hud"'/tab-age.sh "#{@created}") '
  tmux set -w -t "$win" pane-border-status top
  tmux set -w -t "$win" pane-border-format \
    ' #(exec '"$hud"'/pane-status.sh "#{pane_id}" "#{pane_current_command}") '

  # Top up to N agent panes.
  local have; have="$(tmux list-panes -t "$win" | wc -l | tr -d ' ')"
  while (( have < n )); do
    tmux split-window -d -t "$win" -c "$PWD" "$run"
    tmux select-layout -t "$win" tiled
    (( have++ ))
  done

  tmux select-window -t "$win"
  [[ -n "${CLAUDE_TMUX_TEST:-}" ]] && return
  tmux attach -t "$sess"
}
# <<< claude-agents <<<
