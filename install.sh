#!/bin/sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.claude/agents-tmux"

# Backends: herdr when installed (the wrapper picks it automatically),
# tmux as the fallback. Set up both; at least one must end up usable.
has() { command -v "$1" >/dev/null 2>&1; }

if ! has herdr && ! [ -x "$HOME/.local/bin/herdr" ]; then
  echo "herdr not found — installing (https://herdr.dev)..."
  curl -fsSL https://herdr.dev/install.sh | sh || \
    echo "herdr install failed; the wrapper will use tmux" >&2
fi
if ! has jq; then
  if command -v brew >/dev/null 2>&1; then
    echo "jq not found — installing with Homebrew..."
    brew install jq
  else
    echo "jq not found; the herdr backend needs it, so the wrapper will use tmux until you install it" >&2
  fi
fi
if ! has tmux; then
  if command -v brew >/dev/null 2>&1; then
    echo "tmux not found — installing with Homebrew..."
    brew install tmux
  else
    echo "tmux not found; skipping the fallback backend" >&2
  fi
fi
{ { has herdr || [ -x "$HOME/.local/bin/herdr" ]; } && has jq; } || has tmux || {
  echo "no usable backend: install herdr + jq (curl -fsSL https://herdr.dev/install.sh | sh) or tmux" >&2
  exit 1
}

mkdir -p "$dest"
cp "$here/scripts/statusline.sh" "$here/scripts/pane-status.sh" \
   "$here/scripts/tab-age.sh" "$here/scripts/agent-launch.sh" \
   "$here/scripts/herdr-ensure.sh" "$dest/"
chmod +x "$dest"/*.sh
echo "installed scripts to $dest"

line="source \"$here/claude-agents.zsh\""
if grep -qF "$line" "$HOME/.zshrc" 2>/dev/null; then
  echo "~/.zshrc already sources claude-agents.zsh"
elif grep -q "claude-agents" "$HOME/.zshrc" 2>/dev/null; then
  echo "~/.zshrc already contains a claude-agents block; not adding a second one"
else
  printf '\n%s\n' "$line" >> "$HOME/.zshrc"
  echo "added source line to ~/.zshrc"
fi

# Wire the statusLine hook into ~/.claude/settings.json (backing it up first).
settings="$HOME/.claude/settings.json"
merge() {
  python3 - "$settings" <<'PY'
import json, os, sys
p = sys.argv[1]
data = {}
if os.path.exists(p):
    with open(p) as f:
        data = json.load(f)
want = {"type": "command", "command": "~/.claude/agents-tmux/statusline.sh"}
if data.get("statusLine") == want:
    print("statusLine already configured in", p)
    sys.exit(0)
if os.path.exists(p):
    os.replace(p, p + ".bak")
data["statusLine"] = want
with open(p, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("set statusLine in", p, "(previous file saved as settings.json.bak)")
PY
}
if command -v python3 >/dev/null 2>&1 && merge; then
  echo
  echo "Done. Open a new terminal (or \`source ~/.zshrc\`) and run: claude"
else
  cat <<'EOF'

Last step — add this to ~/.claude/settings.json (merge with existing keys):

  "statusLine": {
    "type": "command",
    "command": "~/.claude/agents-tmux/statusline.sh"
  }

Then open a new terminal (or `source ~/.zshrc`) and run: claude
EOF
fi
