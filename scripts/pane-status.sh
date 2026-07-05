#!/bin/sh
# Pane-border HUD for agent panes in the "agents" tmux session.
# Every pane gets a deterministic procedural sigil (glyph pair + color
# derived from its pane id), then the agent's model · effort:
#   ⡵◈ Fable 5 · high
# Claude Code already shows live working/thinking state inside the pane,
# so the border stays static and minimal.
# Usage: pane-status.sh <pane_id> <pane_current_command>
pane="$1"; cmd="$2"
f="$HOME/.claude/agents-tmux/state/$(printf '%s' "$pane" | tr -d '%').env"

# --- procedural sigil: hash the pane id into color + two glyph alphabets ---
set -- $(printf '%s' "$pane" | cksum); h=$1
set -- 81 203 114 178 141 208 44 205 156 220 75 168
i=$(( h % 12 + 1 )); eval "c=\${$i}"
set -- ⡪ ⣷ ⢝ ⡵ ⣫ ⢵ ⡿ ⣰ ⢾ ⣢ ⡮ ⣟ ⢜ ⡞ ⣳ ⢫
i=$(( (h / 12) % 16 + 1 )); eval "g1=\${$i}"
set -- ◈ ◆ ✦ ❖ ▲ ⬢ ● ◉ ■ ✚ ◍ ⬡ ◐ ✱ ◮ ⬗
i=$(( (h / 192) % 16 + 1 )); eval "g2=\${$i}"
sig="#[fg=colour$c,bold]$g1$g2#[default]"

# A pane sitting at a shell is not an agent.
case "$cmd" in
  zsh|bash|sh|fish|-zsh|-bash)
    printf '%s #[dim]shell#[default]' "$sig"; exit 0 ;;
esac

if [ ! -f "$f" ]; then
  printf '%s #[fg=colour%s]starting…#[default]' "$sig" "$c"; exit 0
fi
. "$f"

label="#[fg=colour$c]${MODEL:-claude}#[default]"
[ -n "$EFFORT" ] && label="$label #[fg=colour245]· $EFFORT#[default]"

printf '%s %s' "$sig" "$label"
