# >>> claude-agents: one tmux session for everything; tab = folder; panes = agents >>>
# `claude`    → open (or rejoin) the "agents" session at this folder's tab
# `claude 3`  → this folder's tab has 3 agent panes (adds splits as needed)
# Inside tmux → in this folder's tab the current pane becomes an agent
#               (`claude 3` adds 2 siblings); anywhere else it routes to
#               the folder's own tab, creating it if needed
# `tmux`      → bare, outside tmux: offers to jump to the agents manager;
#               decline (or answer anything but y) for stock tmux
# One tab per folder, always: duplicate tabs for the same path get merged
# back into the first one. Tabs show a running-age badge (amber >1d, red >3d).
# Exiting an agent (Ctrl-C, /exit, crash) drops its pane to a normal shell
# instead of closing it; `claude N` counts running agents and relaunches
# idle shell panes in place before adding new splits.
# The Claude Code folder-trust prompt is pre-accepted per folder, so a
# burst of new panes never stalls on "Do you trust the files..." dialogs.
# Every agent pane's border shows a procedural sigil + model · effort,
# fed by the Claude Code statusLine hook (~/.claude/agents-tmux/).
# Agents run under caffeinate and survive closed terminals / wifi drops.

# Pre-accept Claude Code's "Do you trust the files in this folder?" dialog
# for a folder by recording the acceptance in ~/.claude.json up front — the
# same projects.<path>.hasTrustDialogAccepted key the dialog itself writes.
# (State-file edit, not a supported API.) Claude Code never saves an
# interactive acceptance for $HOME itself but honors a pre-seeded one, so
# re-seeding on every launch keeps even home-directory panes prompt-free.
_claude_agents_trust() {
  emulate -L zsh
  local cfg="$HOME/.claude.json" dir="$1" tmp
  [[ -n "${CLAUDE_TMUX_TEST:-}" ]] && cfg="${CLAUDE_TMUX_TRUST_FILE:-}"
  [[ -n "$cfg" && -r "$cfg" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -e --arg p "$dir" '.projects[$p].hasTrustDialogAccepted == true' \
    "$cfg" >/dev/null 2>&1 && return 0
  tmp="$cfg.agents-tmux.$$"
  if jq --arg p "$dir" \
       '.projects[$p] = (.projects[$p] // {}) + {hasTrustDialogAccepted: true}' \
       "$cfg" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    command mv -f "$tmp" "$cfg"
  else
    command rm -f "$tmp"
  fi
}

# Bare `tmux` outside tmux: offer to jump straight to the agents manager;
# any answer other than y falls through to stock tmux behavior.
tmux() {
  emulate -L zsh
  if [[ $# -eq 0 && -z "$TMUX" && -t 0 && -t 1 ]]; then
    local sess="${CLAUDE_TMUX_SESSION:-agents}" reply=""
    if command tmux has-session -t "=$sess" 2>/dev/null; then
      read -q "reply?tmux: open the agents manager? [y/N] "
      print
      [[ "$reply" == [yY] ]] && { command tmux attach -t "=$sess"; return }
    fi
  fi
  command tmux "$@"
}

# herdr backend: same model, different multiplexer. Workspace = folder,
# pane = agent, and herdr's sidebar rolls agent state (blocked / working /
# done / idle) up per folder, so the "which project needs me" view is
# built in. scripts/herdr-ensure.sh does the workspace/pane bookkeeping on
# whichever machine hosts the herdr server; this function decides where
# that is (local, or the configured remote host) and attaches.
_claude_agents_herdr() {
  emulate -L zsh
  local n="$1" bin="$2"; shift 2
  local hud="$HOME/.claude/agents-tmux"
  local sess="${CLAUDE_TMUX_SESSION:-agents}"

  # Same remote config as the tmux backend: ~/.claude/agents-tmux/remote
  # or CLAUDE_AGENTS_HOST; local folder NAME maps to ~/work/<name> on the
  # host; CLAUDE_AGENTS_LOCAL=1 forces a local session.
  local rconf="${CLAUDE_AGENTS_HOST:-}"
  [[ -z "$rconf" && -r "$hud/remote" ]] && rconf="$(<"$hud/remote")"
  if [[ -n "$rconf" && -z "${SSH_CONNECTION:-}" && -z "${CLAUDE_AGENTS_LOCAL:-}" ]]; then
    local rhost="${rconf%% *}" rmode="${rconf#* }" rtag="${${PWD:t}//[^A-Za-z0-9_-]/-}"
    if [[ "$rmode" == "docker" ]]; then
      # A thin client can't reach inside a container, so run the whole
      # herdr UI in the container over ssh; the wrapper there (with
      # backend=herdr set in the image) does the rest.
      local rcmd="docker exec -it claude-agents zsh -ilc 'mkdir -p ~/work/$rtag && cd ~/work/$rtag && claude $n'"
      if [[ -n "${CLAUDE_TMUX_TEST:-}" ]]; then print -r -- "ssh -t $rhost $rcmd"; return; fi
      if ssh -o BatchMode=yes -o ConnectTimeout=3 "$rhost" true 2>/dev/null; then
        ssh -t "$rhost" "$rcmd"; return
      fi
      print -u2 "claude-agents: remote $rhost unreachable — opening local session"
    else
      if [[ -n "${CLAUDE_TMUX_TEST:-}" ]]; then
        print -r -- "herdr --remote $rhost --session $sess ($rtag x$n)"; return
      fi
      if ssh -o BatchMode=yes -o ConnectTimeout=3 "$rhost" true 2>/dev/null; then
        # Set up the folder's workspace and agents server-side, then
        # attach as a thin client: local keybindings, native clipboard,
        # and herdr auto-installs its binary on the host if missing.
        ssh "$rhost" "mkdir -p ~/work/$rtag && CLAUDE_AGENTS_SESSION=$sess ~/.claude/agents-tmux/herdr-ensure.sh $n ~/work/$rtag \"\$(command -v claude || echo \$HOME/.local/bin/claude)\"" >/dev/null 2>&1 || \
          print -u2 "claude-agents: remote herdr setup failed — attaching anyway (is this repo installed on $rhost?)"
        command herdr --remote "$rhost" --session "$sess"
        return
      fi
      print -u2 "claude-agents: remote $rhost unreachable — opening local session"
    fi
  fi

  if [[ -n "${CLAUDE_TMUX_TEST:-}" ]]; then print -r -- "herdr-local $sess $n $PWD"; return; fi
  CLAUDE_AGENTS_SESSION="$sess" "$hud/herdr-ensure.sh" "$n" "$PWD" "$bin" "$@" >/dev/null || return
  command herdr --session "$sess"
}

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

  local hud="$HOME/.claude/agents-tmux"

  # Backend: tmux (default) or herdr. Pick herdr once with
  #   echo herdr > ~/.claude/agents-tmux/backend
  # or per-call with CLAUDE_AGENTS_BACKEND=herdr.
  local backend="${CLAUDE_AGENTS_BACKEND:-}"
  [[ -z "$backend" && -r "$hud/backend" ]] && backend="$(<"$hud/backend")"

  # Inside a herdr pane, whatever the configured backend: the current
  # pane becomes an agent and `claude 3` adds 2 siblings — the mirror of
  # the inside-tmux behavior below. Checked before anything else so a
  # herdr pane that inherited a stale $TMUX never routes into tmux.
  if [[ -n "${HERDR_PANE_ID:-}" ]]; then
    local -a hextra
    [[ " $* " != *" --dangerously-skip-permissions "* ]] && hextra=(--dangerously-skip-permissions)
    [[ -n "${CLAUDE_TMUX_TEST:-}" ]] && { print -r -- "herdr-inside $n"; return }
    if (( n > 1 )); then
      CLAUDE_AGENTS_SELF_PANE="$HERDR_PANE_ID" \
        "$hud/herdr-ensure.sh" "$n" "$PWD" "$bin" "$@" >/dev/null
    else
      _claude_agents_trust "$PWD"
    fi
    "$hud/agent-launch.sh" "$bin" "$@" "${hextra[@]}"
    return
  fi

  if [[ "$backend" == "herdr" ]]; then
    if command -v herdr >/dev/null 2>&1; then
      _claude_agents_herdr "$n" "$bin" "$@"
      return
    fi
    print -u2 "claude-agents: backend is herdr but herdr isn't installed (brew install herdr) — using tmux"
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

  local sess="${CLAUDE_TMUX_SESSION:-agents}"
  local tag="${${PWD:t}//[^A-Za-z0-9_-]/-}"

  # Pre-accept the folder-trust dialog so a burst of new panes doesn't
  # stall on one "Do you trust the files in this folder?" prompt each.
  _claude_agents_trust "$PWD"

  local -a extra
  [[ " $* " != *" --dangerously-skip-permissions "* ]] && extra=(--dangerously-skip-permissions)
  local -a qargs; qargs=("${(q)@}" "${(q)extra[@]}")
  # agent-launch.sh matches the Claude Code spinner color to the pane's
  # sigil and runs the agent under caffeinate.
  local run="$hud/agent-launch.sh $bin $qargs"
  # When an agent exits (Ctrl-C, /exit, crash) its pane drops to a normal
  # shell instead of closing, so tabs are never locked to Claude. Agent
  # panes carry pane-level remain-on-exit (set by agent-launch.sh); this
  # hook turns the dead pane into a shell and clears the flag, so a plain
  # `exit` in that shell still closes the pane.
  local died='respawn-pane zsh ; set -p remain-on-exit off'

  # Inside tmux: when this window is (or can become) this folder's tab,
  # the current pane becomes an agent and a count adds sibling panes.
  # From any other window or session, fall through and route to the
  # folder's own tab — one tab per folder, wherever you typed `claude`.
  if [[ -n "$TMUX" && -n "${TMUX_PANE:-}" ]]; then
    # Target this pane explicitly everywhere: without -t, tmux resolves
    # window commands against the session's *active* window, which is
    # only coincidentally the one this shell lives in.
    local me="$TMUX_PANE" here="" cur_path="" owner="" tline
    if [[ "$(command tmux display -t "$TMUX_PANE" -p '#{session_name}')" == "$sess" ]]; then
      cur_path="$(tmux show -w -t "$me" -v @agent_path 2>/dev/null)"
      if [[ "$cur_path" == "$PWD" ]]; then here=1
      elif [[ -z "$cur_path" ]]; then
        # Unclaimed window: claim it, unless another tab already owns $PWD.
        while IFS= read -r tline; do
          [[ "${tline#*$'\t'}" == "$PWD" ]] && { owner="${tline%%$'\t'*}"; break }
        done < <(tmux list-windows -t "$sess" -F $'#{window_id}\t#{@agent_path}')
        [[ -z "$owner" ]] && here=1
      fi
    fi
    if [[ -n "$here" ]]; then
      tmux set-hook -t "$sess" pane-died "$died"
      tmux set -w -t "$me" pane-border-status top
      tmux set -w -t "$me" pane-border-format \
        ' #(exec '"$hud"'/pane-status.sh "#{pane_id}" "#{pane_current_command}") '
      # Claim this window for the folder so a later `claude` from outside
      # rejoins this tab instead of opening a duplicate.
      [[ -z "$cur_path" ]] && tmux set -w -t "$me" @agent_path "$PWD"
      [[ -z "$(tmux show -w -t "$me" -v @created 2>/dev/null)" ]] && \
        tmux set -w -t "$me" @created "$(date +%s)"
      # `claude N` here = this pane plus N-1 siblings. Sibling panes
      # sitting at a plain shell (exited agents) are relaunched in place
      # before any new splits are added.
      local i pid pcmd
      local -a idle
      while IFS=$'\t' read -r pid pcmd; do
        [[ "$pid" == "$me" ]] && continue
        case "$pcmd" in zsh|bash|sh|fish|-zsh|-bash) idle+=("$pid") ;; esac
      done < <(tmux list-panes -t "$me" -F $'#{pane_id}\t#{pane_current_command}')
      for (( i = 2; i <= n; i++ )); do
        if (( ${#idle} )); then
          tmux respawn-pane -k -c "$PWD" -t "${idle[1]}" "$run"
          idle=("${(@)idle[2,-1]}")
        else
          tmux split-window -d -t "$me" -c "$PWD" "$run"
          tmux select-layout -t "$me" tiled
        fi
      done
      [[ -n "${CLAUDE_TMUX_TEST:-}" ]] && return
      "$hud/agent-launch.sh" "$bin" "$@" "${extra[@]}"
      # Back at the shell that launched the agent: this pane is a normal
      # terminal again, so exiting it should close the pane, not respawn.
      tmux set -p -t "$me" remain-on-exit off 2>/dev/null
      return
    fi
  fi

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
  tmux set-hook -t "$sess" pane-died "$died"

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

  # Top up to N agents. Only actual agents count — panes sitting at a
  # plain shell (exited agents) don't — so `claude 4` means four running
  # Claudes. Idle shell panes are relaunched in place before splitting.
  local have=0 pid pcmd
  local -a idle
  while IFS=$'\t' read -r pid pcmd; do
    case "$pcmd" in
      zsh|bash|sh|fish|-zsh|-bash) idle+=("$pid") ;;
      *) (( have++ )) ;;
    esac
  done < <(tmux list-panes -t "$win" -F $'#{pane_id}\t#{pane_current_command}')
  for pid in "${idle[@]}"; do
    (( have >= n )) && break
    tmux respawn-pane -k -c "$PWD" -t "$pid" "$run"
    (( have++ ))
  done
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
