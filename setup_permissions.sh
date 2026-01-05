#!/bin/bash
# Script to set up permissions for N8N volumes based on current user
# This should be run before starting containers for the first time

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Get current user UID and GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

echo "Setting up N8N permissions for user UID=$CURRENT_UID GID=$CURRENT_GID"
echo ""

# Create volumes directory if it doesn't exist
mkdir -p volumes/n8n_data volumes/postgres_data volumes/redis_data volumes/redisinsight_data volumes/workflows volumes/config

# Set permissions for n8n_data (most important)
if [ -d "volumes/n8n_data" ]; then
    echo "Setting permissions for volumes/n8n_data..."
    chown -R "$CURRENT_UID:$CURRENT_GID" volumes/n8n_data 2>/dev/null || {
        echo "  ⚠ Could not set ownership, trying with podman unshare..."
        podman unshare chown -R "$CURRENT_UID:$CURRENT_GID" volumes/n8n_data 2>/dev/null || true
    }
    chmod -R 755 volumes/n8n_data
    echo "  ✓ Done"
fi

# Set permissions for other volumes
for vol in postgres_data redis_data redisinsight_data workflows config; do
    if [ -d "volumes/$vol" ]; then
        chown -R "$CURRENT_UID:$CURRENT_GID" "volumes/$vol" 2>/dev/null || true
        chmod -R 755 "volumes/$vol"
    fi
done

echo ""
echo "✓ Permissions set up. You can now start containers with:"
echo "  export N8N_UID=$CURRENT_UID"
echo "  export N8N_GID=$CURRENT_GID"
echo "  podman compose up -d"
echo ""
echo "Or add to your shell profile:"
echo "  export N8N_UID=$CURRENT_UID"
echo "  export N8N_GID=$CURRENT_GID"
