#!/bin/sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.claude/agents-tmux"

mkdir -p "$dest"
cp "$here/scripts/statusline.sh" "$here/scripts/pane-status.sh" "$here/scripts/tab-age.sh" "$dest/"
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

cat <<'EOF'

Last step — add this to ~/.claude/settings.json (merge with existing keys):

  "statusLine": {
    "type": "command",
    "command": "~/.claude/agents-tmux/statusline.sh"
  }

Then open a new terminal (or `source ~/.zshrc`) and run: claude
EOF
