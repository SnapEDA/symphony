#!/bin/bash
# SnapMagic Symphony — Update Script
#
# Pulls latest from upstream (openai/symphony), merges, rebuilds, and restarts.
# Can be run manually or via weekly cron.
#
# Usage: /opt/snapmagic/symphony/elixir/deploy/update.sh

set -euo pipefail

LOG_FILE="/var/log/snapmagic/update.log"
SYMPHONY_DIR="/opt/snapmagic/symphony"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log "=== Starting Symphony update ==="

cd "$SYMPHONY_DIR"

# Ensure upstream remote exists
if ! git remote | grep -q upstream; then
    git remote add upstream https://github.com/openai/symphony.git
    log "Added upstream remote"
fi

# Fetch upstream
log "Fetching upstream..."
git fetch upstream main 2>&1 | tee -a "$LOG_FILE"

# Check if there are new commits
LOCAL=$(git rev-parse HEAD)
UPSTREAM=$(git rev-parse upstream/main)

if [ "$LOCAL" = "$UPSTREAM" ]; then
    log "Already up to date. No changes."
    exit 0
fi

# Count new commits
NEW_COMMITS=$(git log HEAD..upstream/main --oneline | wc -l)
log "Found $NEW_COMMITS new commits from upstream"

# Attempt merge
log "Merging upstream/main..."
if git merge upstream/main --no-edit 2>&1 | tee -a "$LOG_FILE"; then
    log "Merge successful"
else
    log "ERROR: Merge conflict detected!"
    log "Aborting merge. Manual resolution required."
    git merge --abort
    # Notify via a comment — could also send Slack/email
    log "Run 'cd $SYMPHONY_DIR && git merge upstream/main' to resolve manually."
    exit 1
fi

# Push merged changes to our fork
log "Pushing to origin..."
git push origin main 2>&1 | tee -a "$LOG_FILE"

# Rebuild Symphony
log "Rebuilding..."
cd elixir
eval "$(~/.local/bin/mise activate bash)"
mix deps.get 2>&1 | tee -a "$LOG_FILE"
mix escript.build 2>&1 | tee -a "$LOG_FILE"
log "Build complete"

# Restart the service
log "Restarting symphony service..."
sudo systemctl restart snapmagic-symphony
log "Service restarted"

# Verify it's running
sleep 5
if sudo systemctl is-active --quiet snapmagic-symphony; then
    log "Symphony is running after update"
else
    log "WARNING: Symphony failed to start after update!"
    log "Check: sudo journalctl -u snapmagic-symphony -n 50"
fi

log "=== Update complete: $LOCAL → $(git rev-parse HEAD) ==="
