#!/bin/sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.claude/agents-tmux"

command -v tmux >/dev/null 2>&1 || {
  if command -v brew >/dev/null 2>&1; then
    echo "tmux not found — installing with Homebrew..."
    brew install tmux
  else
    echo "tmux is required. Install it first:  brew install tmux" >&2
    exit 1
  fi
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
