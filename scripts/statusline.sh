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

# State file for the per-pane HUD, keyed by the pane this agent lives in —
# a tmux pane (border HUD) or a herdr pane (sidebar custom status).
PANE="${TMUX_PANE:-${HERDR_PANE_ID:-}}"
if [ -n "$PANE" ]; then
  dir="$HOME/.claude/agents-tmux/state"
  mkdir -p "$dir"
  pf="$dir/$(printf '%s' "$PANE" | tr -d '%' | tr ':' '-').env"

  # Cumulative session usage, per billing category. The payload only
  # describes the *current* context, so sum the usage records appended to
  # the transcript since the previous run. Categories are kept separate
  # because they bill at different rates: cache reads cost 0.1x the input
  # rate and dominate the raw total (every API call re-reads the whole
  # context from cache), so a single all-in sum reads absurdly high.
  TPATH="$(pick '"transcript_path" *: *"\([^"]*\)"')"
  TOK_IN=""; TOK_OUT=""; TOK_CC=""; TOK_CR=""; TOK_OFF=""; TOK_SRC=""
  if [ -f "$pf" ]; then
    TOK_IN="$(sed -n "s/^TOK_IN='\([0-9]*\)'\$/\1/p" "$pf")"
    TOK_OUT="$(sed -n "s/^TOK_OUT='\([0-9]*\)'\$/\1/p" "$pf")"
    TOK_CC="$(sed -n "s/^TOK_CC='\([0-9]*\)'\$/\1/p" "$pf")"
    TOK_CR="$(sed -n "s/^TOK_CR='\([0-9]*\)'\$/\1/p" "$pf")"
    TOK_OFF="$(sed -n "s/^TOK_OFF='\([0-9]*\)'\$/\1/p" "$pf")"
    TOK_SRC="$(sed -n "s/^TOK_SRC='\(.*\)'\$/\1/p" "$pf")"
  fi
  [ "$TOK_SRC" = "$TPATH" ] || { TOK_IN=0; TOK_OUT=0; TOK_CC=0; TOK_CR=0; TOK_OFF=0; }
  TOK_IN="${TOK_IN:-0}"; TOK_OUT="${TOK_OUT:-0}"
  TOK_CC="${TOK_CC:-0}"; TOK_CR="${TOK_CR:-0}"; TOK_OFF="${TOK_OFF:-0}"
  if [ -n "$TPATH" ] && [ -f "$TPATH" ]; then
    size="$(wc -c < "$TPATH" | tr -d ' ')"
    if [ "$size" -gt "$TOK_OFF" ] 2>/dev/null; then
      new="$(tail -c +"$((TOK_OFF + 1))" "$TPATH" \
        | grep -oE '"(input_tokens|output_tokens|cache_creation_input_tokens|cache_read_input_tokens)" *: *[0-9]+' \
        | awk -F'[": ]+' '{s[$2]+=$NF} END{printf "%d %d %d %d", \
            s["input_tokens"], s["output_tokens"], \
            s["cache_creation_input_tokens"], s["cache_read_input_tokens"]}')"
      set -- $new
      TOK_IN="$((TOK_IN + ${1:-0}))"; TOK_OUT="$((TOK_OUT + ${2:-0}))"
      TOK_CC="$((TOK_CC + ${3:-0}))"; TOK_CR="$((TOK_CR + ${4:-0}))"
      TOK_OFF="$size"
    fi
  fi
  # Fresh tokens = what the session actually produced/consumed anew.
  TOKENS="$((TOK_IN + TOK_OUT + TOK_CC))"

  # API-price cost in dollars: input + 5x output + 1.25x cache write +
  # 0.1x cache read, at the model's per-MTok input rate.
  RATE_IN=""; RATE_OUT=""
  case "$(printf '%s %s' "$MODEL_ID" "$MODEL" | tr 'A-Z' 'a-z')" in
    *fable*|*mythos*) RATE_IN=10; RATE_OUT=50 ;;
    *opus*)           RATE_IN=5;  RATE_OUT=25 ;;
    *sonnet*)         RATE_IN=3;  RATE_OUT=15 ;;
    *haiku*)          RATE_IN=1;  RATE_OUT=5  ;;
  esac
  COST=""
  [ -n "$RATE_IN" ] && COST="$(awk -v i="$TOK_IN" -v o="$TOK_OUT" -v cc="$TOK_CC" -v cr="$TOK_CR" \
    -v ri="$RATE_IN" -v ro="$RATE_OUT" \
    'BEGIN{printf "%.2f", (i*ri + o*ro + cc*ri*1.25 + cr*ri*0.1)/1e6}')"

  {
    printf "TS=%s\n" "$(date +%s)"
    printf "MODEL='%s'\n" "$MODEL"
    printf "MODEL_ID='%s'\n" "$MODEL_ID"
    printf "EFFORT='%s'\n" "$EFFORT"
    printf "TOKENS='%s'\n" "$TOKENS"
    printf "TOK_IN='%s'\n" "$TOK_IN"
    printf "TOK_OUT='%s'\n" "$TOK_OUT"
    printf "TOK_CC='%s'\n" "$TOK_CC"
    printf "TOK_CR='%s'\n" "$TOK_CR"
    printf "COST='%s'\n" "$COST"
    printf "TOK_OFF='%s'\n" "$TOK_OFF"
    printf "TOK_SRC='%s'\n" "$TPATH"
  } > "$pf.tmp" && mv "$pf.tmp" "$pf"
fi

# In a herdr pane, feed the same model · effort · tokens label into the
# sidebar (custom status) and onto the pane box (title) — the herdr
# equivalents of the tmux pane-border HUD. The box title gets the same
# procedural sigil as the tmux border (two glyphs hashed from the pane
# id, stable per pane); the sidebar stays plain, matching herdr's own
# agent rows.
if [ -n "${HERDR_PANE_ID:-}" ] && command -v herdr >/dev/null 2>&1; then
  hl="${MODEL:-claude}"
  [ -n "$EFFORT" ] && hl="$hl · $EFFORT"
  if [ -n "$TOKENS" ] && [ "$TOKENS" -gt 0 ] 2>/dev/null; then
    tk="$(awk -v t="$TOKENS" 'BEGIN{
      if (t >= 1e9)      printf "%.1fB", t/1e9
      else if (t >= 1e6) printf "%.1fM", t/1e6
      else if (t >= 1e3) printf "%.0fk", t/1e3
      else               printf "%d", t }')"
    hl="$hl · $tk tok"
    [ -n "$COST" ] && hl="$hl · \$$COST"
  fi
  set -- $(printf '%s' "$HERDR_PANE_ID" | cksum); h=$1
  set -- ⡪ ⣷ ⢝ ⡵ ⣫ ⢵ ⡿ ⣰ ⢾ ⣢ ⡮ ⣟ ⢜ ⡞ ⣳ ⢫
  i=$(( h % 16 + 1 )); eval "g1=\${$i}"
  set -- ◈ ◆ ✦ ❖ ▲ ⬢ ● ◉ ■ ✚ ◍ ⬡ ◐ ✱ ◮ ⬗
  i=$(( (h / 16) % 16 + 1 )); eval "g2=\${$i}"
  herdr pane report-metadata "$HERDR_PANE_ID" --source claude-agents \
    --custom-status "$hl" --title "$g1$g2 $hl" >/dev/null 2>&1
  # herdr draws no border box around a lone pane, so the in-pane
  # statusline carries the full sigil + label; with splits it matches
  # the box title above it.
  printf '%s %s' "$g1$g2" "$hl"
  exit 0
fi

# Inside tmux the pane border already shows model · effort,
# so stay silent there; only print when there's no border HUD.
[ -n "$TMUX_PANE" ] && exit 0
out="${MODEL:-claude}"
[ -n "$EFFORT" ] && out="$out · $EFFORT"
printf '%s' "$out"
