#!/bin/sh
# Claude Code statusLine hook.
# 1) Renders the status line inside Claude Code itself (outside tmux).
# 2) Drops a per-tmux-pane state file that the tmux pane-border HUD
#    (pane-status.sh) reads, so every split shows its agent's model
#    and effort level.
input="$(cat)"

pick() { printf '%s' "$input" | sed -n "s/.*$1.*/\\1/p" | head -1; }

MODEL="$(pick '"display_name" *: *"\([^"]*\)"')"
MODEL_ID="$(pick '"model" *: *{ *"id" *: *"\([^"]*\)"')"
EFFORT="$(pick '"effort_level" *: *"\([^"]*\)"')"
[ -z "$EFFORT" ] && EFFORT="$(pick '"effortLevel" *: *"\([^"]*\)"')"
[ -z "$EFFORT" ] && EFFORT="$(pick '"effort" *: *"\([^"]*\)"')"

# Fallbacks from settings.json when the hook payload lacks them.
S="$HOME/.claude/settings.json"
[ -z "$EFFORT" ] && [ -f "$S" ] && EFFORT="$(sed -n 's/.*"effortLevel" *: *"\([^"]*\)".*/\1/p' "$S" | head -1)"
[ -z "$MODEL" ] && [ -f "$S" ] && MODEL="$(sed -n 's/.*"model" *: *"\([^"]*\)".*/\1/p' "$S" | head -1)"

# State file for the tmux border HUD, keyed by the pane this agent lives in.
if [ -n "$TMUX_PANE" ]; then
  dir="$HOME/.claude/agents-tmux/state"
  mkdir -p "$dir"
  pf="$dir/$(printf '%s' "$TMUX_PANE" | tr -d '%').env"
  {
    printf "TS=%s\n" "$(date +%s)"
    printf "MODEL='%s'\n" "$MODEL"
    printf "MODEL_ID='%s'\n" "$MODEL_ID"
    printf "EFFORT='%s'\n" "$EFFORT"
  } > "$pf.tmp" && mv "$pf.tmp" "$pf"
fi

# Inside tmux the pane border already shows model · effort,
# so stay silent there; only print when there's no border HUD.
[ -n "$TMUX_PANE" ] && exit 0
out="${MODEL:-claude}"
[ -n "$EFFORT" ] && out="$out · $EFFORT"
printf '%s' "$out"
