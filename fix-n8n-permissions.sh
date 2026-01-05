#!/bin/bash
# Fix N8N permissions and restart containers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Get current user UID and GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

echo "=========================================="
echo "Fixing N8N Permissions"
echo "=========================================="
echo "User: $(whoami)"
echo "UID: $CURRENT_UID"
echo "GID: $CURRENT_GID"
echo ""

# Stop containers
echo "1. Stopping containers..."
podman compose down
echo ""

# Fix n8n_data permissions using podman unshare
echo "2. Fixing n8n_data volume permissions..."
if [ -d "volumes/n8n_data" ]; then
    # Remove any existing files that might have wrong permissions
    echo "   Cleaning n8n_data directory..."
    podman unshare rm -rf volumes/n8n_data/* 2>/dev/null || true
    
    # Set correct ownership
    echo "   Setting ownership to $CURRENT_UID:$CURRENT_GID..."
    podman unshare chown -R "$CURRENT_UID:$CURRENT_GID" volumes/n8n_data 2>/dev/null || {
        echo "   ⚠ Using sudo for chown..."
        sudo chown -R "$CURRENT_UID:$CURRENT_GID" volumes/n8n_data
    }
    
    # Set permissions
    chmod -R 755 volumes/n8n_data
    echo "   ✓ Permissions fixed"
else
    echo "   Creating n8n_data directory..."
    mkdir -p volumes/n8n_data
    chown -R "$CURRENT_UID:$CURRENT_GID" volumes/n8n_data
    chmod -R 755 volumes/n8n_data
fi
echo ""

# Fix other volumes
echo "3. Fixing other volume permissions..."
for vol in postgres_data redis_data redisinsight_data workflows config; do
    if [ -d "volumes/$vol" ]; then
        chown -R "$CURRENT_UID:$CURRENT_GID" "volumes/$vol" 2>/dev/null || true
        chmod -R 755 "volumes/$vol"
    fi
done
echo "   ✓ Other volumes fixed"
echo ""

# Export environment variables
echo "4. Setting environment variables..."
export N8N_UID=$CURRENT_UID
export N8N_GID=$CURRENT_GID
echo "   N8N_UID=$N8N_UID"
echo "   N8N_GID=$N8N_GID"
echo ""

# Start containers
echo "5. Starting containers with correct permissions..."
podman compose up -d
echo ""

# Wait a bit for containers to start
echo "6. Waiting for containers to initialize..."
sleep 5
echo ""

# Check container status
echo "7. Checking container status..."
podman ps | grep -E "n8n|postgres" || echo "   ⚠ Some containers might not be running"
echo ""

# Show n8n logs
echo "8. Recent n8n-app logs (check for errors)..."
echo "----------------------------------------"
podman logs n8n-app --tail 20 2>&1 | tail -20
echo ""

echo "=========================================="
echo "Fix Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Wait 30-60 seconds for n8n to fully start"
echo "2. Check logs: podman logs n8n-app --follow"
echo "3. Once n8n is ready, run: ./init-n8n.sh"
echo ""
echo "To make N8N_UID and N8N_GID persistent, add to ~/.bashrc:"
echo "  export N8N_UID=$CURRENT_UID"
echo "  export N8N_GID=$CURRENT_GID"
echo ""
