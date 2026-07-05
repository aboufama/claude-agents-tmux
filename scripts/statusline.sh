#!/bin/sh
# Claude Code statusLine hook.
# 1) Renders the status line inside Claude Code itself (outside tmux).
# 2) Drops a per-tmux-pane state file that the tmux pane-border HUD
#    (pane-status.sh) reads, so every split shows its agent's model,
#    effort level, and cumulative session tokens.
input="$(cat)"

pick() { printf '%s' "$input" | sed -n "s/.*$1.*/\\1/p" | head -1; }

MODEL="$(pick '"display_name" *: *"\([^"]*\)"')"
MODEL_ID="$(pick '"model" *: *{ *"id" *: *"\([^"]*\)"')"
# Effort: current payloads carry it nested ("effort":{"level":"high"}),
# older ones used flat keys. Prefer the payload so /model and /effort
# changes mid-session show up live; settings.json is a last resort only.
EFFORT="$(pick '"effort" *: *{ *"level" *: *"\([^"]*\)"')"
[ -z "$EFFORT" ] && EFFORT="$(pick '"effort_level" *: *"\([^"]*\)"')"
[ -z "$EFFORT" ] && EFFORT="$(pick '"effortLevel" *: *"\([^"]*\)"')"

# Fallbacks from settings.json when the hook payload lacks them.
S="$HOME/.claude/settings.json"
[ -z "$EFFORT" ] && [ -f "$S" ] && EFFORT="$(sed -n 's/.*"effortLevel" *: *"\([^"]*\)".*/\1/p' "$S" | head -1)"
[ -z "$MODEL" ] && [ -f "$S" ] && MODEL="$(sed -n 's/.*"model" *: *"\([^"]*\)".*/\1/p' "$S" | head -1)"

# State file for the tmux border HUD, keyed by the pane this agent lives in.
if [ -n "$TMUX_PANE" ]; then
  dir="$HOME/.claude/agents-tmux/state"
  mkdir -p "$dir"
  pf="$dir/$(printf '%s' "$TMUX_PANE" | tr -d '%').env"

  # Cumulative session tokens: the payload only describes the *current*
  # context, so sum the usage records (input + output + cache create +
  # cache read) appended to the transcript since the previous run.
  TPATH="$(pick '"transcript_path" *: *"\([^"]*\)"')"
  TOKENS=""; TOK_OFF=""; TOK_SRC=""
  if [ -f "$pf" ]; then
    TOKENS="$(sed -n "s/^TOKENS='\([0-9]*\)'\$/\1/p" "$pf")"
    TOK_OFF="$(sed -n "s/^TOK_OFF='\([0-9]*\)'\$/\1/p" "$pf")"
    TOK_SRC="$(sed -n "s/^TOK_SRC='\(.*\)'\$/\1/p" "$pf")"
  fi
  [ "$TOK_SRC" = "$TPATH" ] || { TOKENS=0; TOK_OFF=0; }
  TOKENS="${TOKENS:-0}"; TOK_OFF="${TOK_OFF:-0}"
  if [ -n "$TPATH" ] && [ -f "$TPATH" ]; then
    size="$(wc -c < "$TPATH" | tr -d ' ')"
    if [ "$size" -gt "$TOK_OFF" ] 2>/dev/null; then
      new="$(tail -c +"$((TOK_OFF + 1))" "$TPATH" \
        | grep -oE '"(input_tokens|output_tokens|cache_creation_input_tokens|cache_read_input_tokens)" *: *[0-9]+' \
        | awk -F: '{s+=$2} END{printf "%d", s}')"
      TOKENS="$((TOKENS + ${new:-0}))"
      TOK_OFF="$size"
    fi
  fi

  {
    printf "TS=%s\n" "$(date +%s)"
    printf "MODEL='%s'\n" "$MODEL"
    printf "MODEL_ID='%s'\n" "$MODEL_ID"
    printf "EFFORT='%s'\n" "$EFFORT"
    printf "TOKENS='%s'\n" "$TOKENS"
    printf "TOK_OFF='%s'\n" "$TOK_OFF"
    printf "TOK_SRC='%s'\n" "$TPATH"
  } > "$pf.tmp" && mv "$pf.tmp" "$pf"
fi

# Inside tmux the pane border already shows model · effort,
# so stay silent there; only print when there's no border HUD.
[ -n "$TMUX_PANE" ] && exit 0
out="${MODEL:-claude}"
[ -n "$EFFORT" ] && out="$out · $EFFORT"
printf '%s' "$out"
