#!/bin/bash
# N8N Project Initialization Script
# Prepares the environment before running podman compose up -d
# Sets up admin credentials, environment variables, and directory permissions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/.env"

echo "=========================================="
echo "N8N Project Initialization"
echo "=========================================="
echo ""

# Function to validate email format
validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate password
validate_password() {
    local password=$1
    if [ ${#password} -lt 6 ]; then
        return 1
    else
        return 0
    fi
}

# Check prerequisites
echo "1. Checking prerequisites..."
if ! command -v podman &> /dev/null; then
    echo "   ERROR: podman is not installed or not in PATH"
    exit 1
fi
echo "   ✓ podman found"

if [ ! -f "docker-compose.yml" ]; then
    echo "   ERROR: docker-compose.yml not found in current directory"
    exit 1
fi
echo "   ✓ docker-compose.yml found"
echo ""

# Get admin credentials interactively
echo "2. Setting up admin credentials..."
echo "   Please provide the admin user credentials for N8N:"
echo ""

# Get email
while true; do
    read -p "   Admin email: " ADMIN_EMAIL
    if [ -z "$ADMIN_EMAIL" ]; then
        echo "   ⚠ Email cannot be empty. Please try again."
        continue
    fi
    if validate_email "$ADMIN_EMAIL"; then
        break
    else
        echo "   ⚠ Invalid email format. Please try again."
    fi
done

# Get password with confirmation
while true; do
    read -sp "   Admin password (min 6 characters): " ADMIN_PASSWORD
    echo ""
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo "   ⚠ Password cannot be empty. Please try again."
        continue
    fi
    if ! validate_password "$ADMIN_PASSWORD"; then
        echo "   ⚠ Password must be at least 6 characters long. Please try again."
        continue
    fi
    read -sp "   Confirm password: " ADMIN_PASSWORD_CONFIRM
    echo ""
    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        echo "   ⚠ Passwords do not match. Please try again."
        continue
    fi
    break
done

echo "   ✓ Credentials validated"
echo ""

# Get current user UID and GID
echo "3. Determining user/group IDs..."
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
N8N_UID=$CURRENT_UID
N8N_GID=$CURRENT_GID
echo "   Current user: $(whoami)"
echo "   UID: $N8N_UID"
echo "   GID: $N8N_GID"
echo ""

# Create volumes directories
echo "4. Creating volumes directories..."
VOLUMES_DIRS=(
    "volumes/n8n_data"
    "volumes/postgres_data"
    "volumes/redis_data"
    "volumes/redisinsight_data"
    "volumes/workflows"
    "volumes/config"
)

for vol_dir in "${VOLUMES_DIRS[@]}"; do
    if [ ! -d "$vol_dir" ]; then
        mkdir -p "$vol_dir"
        echo "   ✓ Created: $vol_dir"
    else
        echo "   ✓ Exists: $vol_dir"
    fi
done
echo ""

# Fix permissions using podman unshare
echo "5. Verifying and fixing permissions..."
for vol_dir in "${VOLUMES_DIRS[@]}"; do
    if [ -d "$vol_dir" ]; then
        echo "   Fixing permissions for $vol_dir..."
        # Try with podman unshare first (for podman namespace)
        if podman unshare chown -R "$N8N_UID:$N8N_GID" "$vol_dir" 2>/dev/null; then
            echo "   ✓ Permissions set using podman unshare"
        else
            # Fallback to regular chown (might need sudo, but we'll try)
            if chown -R "$N8N_UID:$N8N_GID" "$vol_dir" 2>/dev/null; then
                echo "   ✓ Permissions set"
            else
                echo "   ⚠ Could not set ownership for $vol_dir (may need manual fix)"
            fi
        fi
        chmod -R 755 "$vol_dir" 2>/dev/null || echo "   ⚠ Could not set permissions for $vol_dir"
    fi
done
echo ""

# Generate .env file
echo "6. Generating .env file..."
cat > "$ENV_FILE" << EOF
# N8N Admin Credentials
# These will be used by init-n8n.sh to create the admin user
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASSWORD

# N8N User/Group IDs
# These are used by docker-compose.yml to set the container user
N8N_UID=$N8N_UID
N8N_GID=$N8N_GID

# N8N API Key (optional, can be set later)
# This is used by the n8n-mcp service
# You can generate it from N8N UI: Settings > API
N8N_API_KEY=

# Database credentials (used by docker-compose.yml)
# These are set in docker-compose.yml but can be overridden here if needed
# POSTGRES_USER=n8n
# POSTGRES_PASSWORD=n8npass
# POSTGRES_DB=n8n
EOF

# Set secure permissions on .env file
chmod 600 "$ENV_FILE"
echo "   ✓ .env file created with secure permissions (600)"
echo ""

# Summary
echo "=========================================="
echo "Initialization Complete!"
echo "=========================================="
echo ""
echo "Configuration saved to: $ENV_FILE"
echo ""
echo "Admin Credentials:"
echo "  Email: $ADMIN_EMAIL"
echo "  Password: ********"
echo ""
echo "Environment Variables:"
echo "  N8N_UID=$N8N_UID"
echo "  N8N_GID=$N8N_GID"
echo "  N8N_API_KEY=(empty - can be set later)"
echo ""
echo "Next Steps:"
echo "  1. Source the .env file (optional, if you want to use variables in current shell):"
echo "     source .env"
echo ""
echo "  2. Start the containers:"
echo "     podman compose up -d"
echo ""
echo "  3. Wait for containers to be ready (about 30-60 seconds), then initialize N8N:"
echo "     ./init-n8n.sh"
echo ""
echo "  4. Access N8N at: http://localhost:5678"
echo ""
echo "Note: The init-n8n.sh script will read ADMIN_EMAIL and ADMIN_PASSWORD"
echo "      from the .env file to create the admin user."
echo ""
echo "=========================================="
