FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      zsh tmux git curl ca-certificates python3 procps locales openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 SHELL=/usr/bin/zsh \
    PATH=/root/.local/bin:$PATH

# Claude Code native installer
RUN curl -fsSL https://claude.ai/install.sh | bash

COPY . /opt/claude-agents-tmux
RUN chmod +x /opt/claude-agents-tmux/install.sh \
             /opt/claude-agents-tmux/scripts/*.sh \
             /opt/claude-agents-tmux/cloud/entrypoint.sh

WORKDIR /root/work
ENTRYPOINT ["/opt/claude-agents-tmux/cloud/entrypoint.sh"]
