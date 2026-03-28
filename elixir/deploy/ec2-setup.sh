#!/bin/bash
# SnapMagic Symphony — EC2 Setup Script
#
# Provisions a fresh Ubuntu 24.04 EC2 instance to run Symphony with Claude Code.
#
# Usage:
#   1. Launch an EC2 instance (m5.2xlarge, Ubuntu 24.04, 100GB EBS)
#   2. SSH in: ssh -i your-key.pem ubuntu@<ip>
#   3. Run: curl -fsSL https://raw.githubusercontent.com/SnapEDA/symphony/main/elixir/deploy/ec2-setup.sh | bash
#   4. Set secrets: sudo nano /etc/snapmagic/env
#   5. Auth Claude: claude auth --method browser-no-open
#   6. Start: sudo systemctl start snapmagic-symphony

set -euo pipefail

echo "=========================================="
echo " SnapMagic Symphony — EC2 Setup"
echo "=========================================="

# --- System updates ---
echo "[1/9] Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get install -y -qq \
    git curl unzip build-essential \
    python3 python3-pip python3-venv \
    jq htop autoconf libncurses-dev \
    libssl-dev libwxgtk3.2-dev libwxgtk-webview3.2-dev \
    libgl1-mesa-dev libglu1-mesa-dev libpng-dev libssh-dev \
    xsltproc fop libxml2-utils

# --- mise (version manager for Erlang/Elixir) ---
echo "[2/9] Installing mise..."
if ! command -v mise &>/dev/null; then
    curl https://mise.run | sh
    echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
    eval "$(mise activate bash)"
fi
echo "  mise: $(mise --version)"

# --- Node.js (required for Claude Code CLI) ---
echo "[3/9] Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y -qq nodejs
echo "  Node: $(node --version)"

# --- Claude Code CLI ---
echo "[4/9] Installing Claude Code CLI..."
sudo npm install -g @anthropic-ai/claude-code
echo "  Claude: $(claude --version 2>/dev/null || echo 'installed, needs auth')"

# --- GitHub CLI ---
echo "[5/9] Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq gh
echo "  gh: $(gh --version | head -1)"

# --- Docker (for repos that need it) ---
echo "[6/9] Installing Docker..."
sudo apt-get install -y -qq docker.io docker-compose-v2
sudo usermod -aG docker ubuntu
echo "  Docker: $(docker --version)"

# --- Clone Symphony fork ---
echo "[7/9] Cloning SnapMagic Symphony..."
sudo mkdir -p /opt/snapmagic
sudo chown -R ubuntu:ubuntu /opt/snapmagic
cd /opt/snapmagic

if [ ! -d "symphony" ]; then
    git clone https://github.com/SnapEDA/symphony.git
else
    cd symphony && git pull && cd ..
fi

# Install Erlang/Elixir via mise
cd /opt/snapmagic/symphony/elixir
mise trust
mise install
echo "  Erlang/Elixir installed via mise"

# Build Symphony
eval "$(mise activate bash)"
mix local.hex --force
mix local.rebar --force
mix deps.get
mix escript.build
echo "  Symphony built: ./bin/symphony"

# --- Create directories ---
echo "[8/9] Setting up directories..."
sudo mkdir -p /etc/snapmagic
sudo mkdir -p /var/log/snapmagic
mkdir -p ~/snapmagic-workspaces
sudo chown -R ubuntu:ubuntu /var/log/snapmagic

# --- Environment file ---
if [ ! -f /etc/snapmagic/env ]; then
    sudo tee /etc/snapmagic/env > /dev/null << 'ENVEOF'
# SnapMagic Symphony — Environment Variables
# IMPORTANT: Fill in your actual values

# Required
LINEAR_API_KEY=
GITHUB_TOKEN=

# Optional
LOG_LEVEL=info
ENVEOF
    sudo chmod 600 /etc/snapmagic/env
    echo "  Created /etc/snapmagic/env — EDIT THIS FILE with your secrets!"
else
    echo "  /etc/snapmagic/env already exists, skipping"
fi

# --- Systemd service ---
echo "[9/9] Creating systemd service..."
sudo tee /etc/systemd/system/snapmagic-symphony.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=SnapMagic Symphony — Autonomous Agent Orchestrator
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/snapmagic/symphony/elixir
EnvironmentFile=/etc/snapmagic/env
ExecStart=/opt/snapmagic/symphony/elixir/bin/symphony /opt/snapmagic/symphony/elixir/WORKFLOW.md --i-understand-that-this-will-be-running-without-the-usual-guardrails
Restart=on-failure
RestartSec=30
StandardOutput=append:/var/log/snapmagic/symphony.log
StandardError=append:/var/log/snapmagic/symphony.log
LimitNOFILE=65536
MemoryMax=28G

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo systemctl daemon-reload
sudo systemctl enable snapmagic-symphony

# --- Log rotation ---
sudo tee /etc/logrotate.d/snapmagic > /dev/null << 'LOGEOF'
/var/log/snapmagic/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0644 ubuntu ubuntu
}
LOGEOF

echo ""
echo "=========================================="
echo " Setup complete!"
echo "=========================================="
echo ""
echo " Next steps:"
echo ""
echo " 1. Edit secrets:"
echo "    sudo nano /etc/snapmagic/env"
echo ""
echo " 2. Authenticate Claude Code:"
echo "    claude auth --method browser-no-open"
echo ""
echo " 3. Authenticate GitHub CLI:"
echo "    gh auth login"
echo ""
echo " 4. Start Symphony:"
echo "    sudo systemctl start snapmagic-symphony"
echo ""
echo " 5. Watch logs:"
echo "    tail -f /var/log/snapmagic/symphony.log"
echo ""
echo " 6. Stop:"
echo "    sudo systemctl stop snapmagic-symphony"
echo ""
