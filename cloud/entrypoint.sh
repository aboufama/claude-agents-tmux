#!/bin/sh
# Container entrypoint: (re)install the scripts into the mounted
# ~/.claude volume (idempotent), then idle forever. Agents live in the
# tmux session inside this container and keep running as long as the
# container does — attach with:
#   docker exec -it claude-agents zsh -ilc claude
/opt/claude-agents-tmux/install.sh
exec tail -f /dev/null
