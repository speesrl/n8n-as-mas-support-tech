#!/bin/bash
# Script to configure Git remote to use GitHub token from .env file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/.env"

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env file not found at $ENV_FILE"
    echo "Please run ./init-project.sh first or create the .env file manually"
    exit 1
fi

# Load GITHUB_TOKEN from .env file
if [ -f "$ENV_FILE" ]; then
    # Source the .env file to load variables
    set -a
    source "$ENV_FILE"
    set +a
fi

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GITHUB_TOKEN not found in .env file"
    echo "Please add GITHUB_TOKEN to your .env file"
    exit 1
fi

# Get the current remote URL
CURRENT_URL=$(git remote get-url origin 2>/dev/null || echo "")

if [ -z "$CURRENT_URL" ]; then
    echo "ERROR: No Git remote 'origin' found"
    exit 1
fi

# Extract repository path from URL (handles both https://github.com/user/repo.git and https://TOKEN@github.com/user/repo.git)
if [[ "$CURRENT_URL" =~ https://.*@github\.com/(.+)\.git$ ]] || [[ "$CURRENT_URL" =~ https://github\.com/(.+)\.git$ ]]; then
    REPO_PATH="${BASH_REMATCH[1]}"
else
    echo "ERROR: Could not parse repository path from remote URL: $CURRENT_URL"
    exit 1
fi

# Set new remote URL with token
NEW_URL="https://${GITHUB_TOKEN}@github.com/${REPO_PATH}.git"
git remote set-url origin "$NEW_URL"

echo "✓ Git remote 'origin' configured to use GitHub token from .env"
echo "  Repository: $REPO_PATH"
echo ""
echo "You can now use 'git push' and it will authenticate automatically with the token."
