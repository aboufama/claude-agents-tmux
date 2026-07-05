#!/bin/sh
# Launches a Claude Code agent for a tmux pane so the in-app spinner line
# ("✳ Frosting…") renders in the same color as the pane's border sigil.
# Writes a tiny custom theme per color into ~/.claude/themes and selects
# it via --settings, then execs under caffeinate so the Mac stays awake.
# The color hash MUST stay in lockstep with pane-status.sh.
# Usage: agent-launch.sh <claude-bin> [claude args...]
bin="$1"; shift

# caffeinate is macOS-only; on Linux hosts run the agent directly.
awake=""
command -v caffeinate >/dev/null 2>&1 && awake="caffeinate -ims"

if [ -z "$TMUX_PANE" ]; then
  exec $awake "$bin" "$@"
fi

h=$(printf '%s' "$TMUX_PANE" | cksum | cut -d' ' -f1)
i=$(( h % 12 + 1 ))
c=$(printf '%s\n'   81     203    114    178    141    208    44     205    156    220    75     168    | sed -n "${i}p")
hex=$(printf '%s\n' 5fd7ff ff5f5f 87d787 d7af00 af87ff ff8700 00d7d7 ff5faf afff87 ffd700 5fafff d75f87 | sed -n "${i}p")
shm=$(printf '%s\n' 9fe7ff ff9f9f b7e7b7 e7cf60 cfb7ff ffb760 60e7e7 ff9fcf cfffb7 ffe760 9fcfff e79fb7 | sed -n "${i}p")

# Base the theme on the user's configured one when it's a plain named theme.
base=$(sed -n 's/.*"theme" *: *"\([a-z-]*\)".*/\1/p' "$HOME/.claude/settings.json" 2>/dev/null | head -1)
[ -z "$base" ] && base=dark

name="agents-pane-$c"
dir="$HOME/.claude/themes"
if [ ! -f "$dir/$name.json" ]; then
  mkdir -p "$dir"
  cat > "$dir/$name.json" <<EOF
{
  "name": "$name",
  "base": "$base",
  "overrides": {
    "claudeBlue_FOR_SYSTEM_SPINNER": "#$hex",
    "claudeBlueShimmer_FOR_SYSTEM_SPINNER": "#$shm"
  }
}
EOF
fi

exec $awake "$bin" --settings "{\"theme\":\"custom:$name\"}" "$@"
