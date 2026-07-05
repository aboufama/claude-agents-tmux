#!/bin/sh
# Age badge for a tab in the "agents" tmux session.
# Arg: the window's @created epoch. Prints e.g. 42m / 7h / 2d5h,
# dim under a day, amber 1-3 days, red+bold past 3 days.
c="$1"
case "$c" in ''|*[!0-9]*) exit 0 ;; esac
now=$(date +%s)
s=$(( now - c )); [ "$s" -lt 0 ] && s=0
d=$(( s / 86400 )); hh=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
if   [ "$d" -gt 0 ]; then txt="${d}d${hh}h"
elif [ "$hh" -gt 0 ]; then txt="${hh}h"
else txt="${m}m"; fi
if   [ "$s" -ge 259200 ]; then style='#[fg=colour196,bold]'   # > 3 days: red
elif [ "$s" -ge 86400  ]; then style='#[fg=colour178]'        # 1-3 days: amber
else style='#[fg=colour245]'; fi                              # fresh: dim
printf '%s%s#[default]' "$style" "$txt"
