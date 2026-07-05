# >>> claude-agents: one tmux session for everything; tab = folder; panes = agents >>>
# `claude`    → open (or rejoin) the "agents" session at this folder's tab
# `claude 3`  → this folder's tab has 3 agent panes (adds splits as needed)
# Inside tmux → the current pane becomes an agent; `claude 3` adds 2 siblings
# Tabs show a running-age badge (amber >1d, red >3d). Every agent pane's
# border shows a procedural sigil + model · effort + live working/idle state,
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

  local -a extra
  [[ " $* " != *" --dangerously-skip-permissions "* ]] && extra=(--dangerously-skip-permissions)
  local -a qargs; qargs=("${(q)@}" "${(q)extra[@]}")
  local run="caffeinate -ims $bin $qargs"
  local hud="$HOME/.claude/agents-tmux"

  # Inside tmux: this pane becomes an agent; a count adds sibling panes.
  if [[ -n "$TMUX" ]]; then
    local i
    for (( i = 2; i <= n; i++ )); do
      tmux split-window -d -c "$PWD" "$run"
      tmux select-layout tiled
    done
    [[ -n "${CLAUDE_TMUX_TEST:-}" ]] && return
    caffeinate -ims "$bin" "$@" "${extra[@]}"
    return
  fi

  local sess=agents
  local tag="${${PWD:t}//[^A-Za-z0-9_-]/-}"
  local win="" line

  if ! tmux has-session -t "=$sess" 2>/dev/null; then
    win="$(tmux new-session -d -P -F '#{window_id}' -x 250 -y 80 -s "$sess" -n "$tag" -c "$PWD" "$run")"
    tmux set -t "$sess" status-interval 1
    tmux set -t "$sess" window-status-format \
      ' #I #W #(exec '"$hud"'/tab-age.sh "#{@created}") '
    tmux set -t "$sess" window-status-current-format \
      '#[bold] #I #W#{?window_zoomed_flag, +Z,} #(exec '"$hud"'/tab-age.sh "#{@created}") '
  else
    # Same folder → same tab: find it by the path recorded on the window.
    while IFS= read -r line; do
      [[ "${line#*$'\t'}" == "$PWD" ]] && { win="${line%%$'\t'*}"; break }
    done < <(tmux list-windows -t "$sess" -F $'#{window_id}\t#{@agent_path}')
    [[ -z "$win" ]] && win="$(tmux new-window -t "$sess" -P -F '#{window_id}' -n "$tag" -c "$PWD" "$run")"
  fi

  # Window bookkeeping (idempotent; @created only stamped once).
  [[ -z "$(tmux show -w -t "$win" -v @created 2>/dev/null)" ]] && \
    tmux set -w -t "$win" @created "$(date +%s)"
  tmux set -w -t "$win" @agent_path "$PWD"
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
