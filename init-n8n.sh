#!/bin/bash
# N8N Initialization Script
# Creates admin user and personal project if they don't exist

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

DB_CONTAINER="n8n-db"
DB_USER="n8n"
DB_NAME="n8n"

# Load credentials from .env file if it exists, otherwise use defaults
if [ -f "$ENV_FILE" ]; then
    echo "Loading configuration from .env file..."
    source "$ENV_FILE"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@spee.it}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
else
    echo "No .env file found, using default credentials..."
    ADMIN_EMAIL="admin@spee.it"
    ADMIN_PASSWORD="admin"
fi

ADMIN_FIRST_NAME="Admin"
ADMIN_LAST_NAME="User"

echo "Waiting for PostgreSQL to be ready..."
until podman exec $DB_CONTAINER pg_isready -U $DB_USER > /dev/null 2>&1; do
  echo "Waiting for database..."
  sleep 2
done

echo "Waiting for N8N to create database tables..."
MAX_ATTEMPTS=60
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  # Check if essential tables exist (user, role, project)
  USER_TABLE=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user');" 2>/dev/null | tr -d ' ')
  ROLE_TABLE=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'role');" 2>/dev/null | tr -d ' ')
  PROJECT_TABLE=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'project');" 2>/dev/null | tr -d ' ')
  
  if [ "$USER_TABLE" = "t" ] && [ "$ROLE_TABLE" = "t" ] && [ "$PROJECT_TABLE" = "t" ]; then
    echo "Database tables created by N8N"
    break
  fi
  
  ATTEMPT=$((ATTEMPT + 1))
  if [ $((ATTEMPT % 5)) -eq 0 ]; then
    echo "Waiting for N8N to create tables... ($ATTEMPT/$MAX_ATTEMPTS)"
  fi
  sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo "WARNING: N8N tables might not be created yet. Verifying..."
  # Verify essential tables exist before proceeding
  USER_TABLE=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user');" 2>/dev/null | tr -d ' ')
  ROLE_TABLE=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'role');" 2>/dev/null | tr -d ' ')
  PROJECT_TABLE=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'project');" 2>/dev/null | tr -d ' ')
  
  if [ "$USER_TABLE" != "t" ] || [ "$ROLE_TABLE" != "t" ] || [ "$PROJECT_TABLE" != "t" ]; then
    echo "ERROR: Required N8N tables have not been created yet."
    echo "Missing tables:"
    [ "$USER_TABLE" != "t" ] && echo "  - user"
    [ "$ROLE_TABLE" != "t" ] && echo "  - role"
    [ "$PROJECT_TABLE" != "t" ] && echo "  - project"
    echo ""
    echo "Please:"
    echo "  1. Check that n8n container is running: podman ps | grep n8n"
    echo "  2. Check n8n logs: podman logs n8n-app"
    echo "  3. Wait for n8n to fully initialize and run this script again"
    exit 1
  fi
fi

echo "Checking if admin user exists..."
USER_EXISTS=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM \"user\" WHERE email = '$ADMIN_EMAIL';" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$USER_EXISTS" = "0" ]; then
  echo "Creating admin user..."
  
  # Generate bcrypt hash for password
  PASSWORD_HASH=$(podman run --rm docker.io/python:3.11-slim sh -c "pip install -q bcrypt 2>/dev/null && python3 -c \"import bcrypt; print(bcrypt.hashpw(b'$ADMIN_PASSWORD', bcrypt.gensalt()).decode())\"")
  
  # Get owner role slug
  OWNER_ROLE=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT slug FROM role WHERE slug = 'global:owner' LIMIT 1;" | tr -d ' ')
  
  # Create user
  podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    INSERT INTO \"user\" (email, \"firstName\", \"lastName\", password, \"roleSlug\", disabled, \"mfaEnabled\", \"createdAt\", \"updatedAt\")
    VALUES ('$ADMIN_EMAIL', '$ADMIN_FIRST_NAME', '$ADMIN_LAST_NAME', '$PASSWORD_HASH', '$OWNER_ROLE', false, false, NOW(), NOW())
    ON CONFLICT (email) DO NOTHING;
  "
  
  echo "Admin user created: $ADMIN_EMAIL"
else
  echo "Admin user already exists: $ADMIN_EMAIL"
fi

# Get user ID
USER_ID=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT id FROM \"user\" WHERE email = '$ADMIN_EMAIL';" 2>/dev/null | tr -d ' ')

if [ -z "$USER_ID" ] || [ "$USER_ID" = "" ]; then
  echo "ERROR: Could not find user ID for $ADMIN_EMAIL"
  echo "This might happen if:"
  echo "  1. The user was not created successfully"
  echo "  2. The database tables are not ready yet"
  echo "Please check the n8n container logs and try again."
  exit 1
fi

echo "User ID: $USER_ID"

# Check if personal project exists
PROJECT_EXISTS=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM project WHERE type = 'personal' LIMIT 1;" | tr -d ' ')

if [ "$PROJECT_EXISTS" = "0" ]; then
  echo "Creating personal project..."
  
  # Generate project ID (n8n uses short IDs)
  PROJECT_ID=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT gen_random_uuid()::text;" | tr -d ' ' | cut -c1-15)
  
  podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    INSERT INTO project (id, name, type, \"creatorId\", \"createdAt\", \"updatedAt\")
    VALUES ('$PROJECT_ID', 'Personal Project', 'personal', '$USER_ID', NOW(), NOW());
  "
  
  echo "Personal project created: $PROJECT_ID"
else
  PROJECT_ID=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT id FROM project WHERE type = 'personal' LIMIT 1;" | tr -d ' ')
  echo "Personal project already exists: $PROJECT_ID"
  
  # Update creatorId if not set
  podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    UPDATE project SET \"creatorId\" = '$USER_ID' WHERE id = '$PROJECT_ID' AND (\"creatorId\" IS NULL OR \"creatorId\" != '$USER_ID');
  "
  echo "Updated project creatorId"
fi

# Check if project relation exists
RELATION_EXISTS=$(podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM project_relation WHERE \"userId\" = '$USER_ID' AND \"projectId\" = '$PROJECT_ID';" | tr -d ' ')

if [ "$RELATION_EXISTS" = "0" ]; then
  echo "Linking user to personal project..."
  
  podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    INSERT INTO project_relation (\"projectId\", \"userId\", role, \"createdAt\", \"updatedAt\")
    VALUES ('$PROJECT_ID', '$USER_ID', 'project:personalOwner', NOW(), NOW())
    ON CONFLICT DO NOTHING;
  "
  
  echo "User linked to personal project"
else
  echo "User already linked to personal project"
fi

# Update user settings to avoid notification errors
echo "Setting up user settings..."
podman exec $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
  UPDATE \"user\" SET 
    settings = '{\"versionNotifications\":{\"enabled\":true}}'::json,
    \"personalizationAnswers\" = '{
      \"companyType\":\"other\",
      \"role\":\"developer\",
      \"automationGoal\":\"personal\",
      \"companySize\":\"1-10\",
      \"howDidYouHear\":\"other\"
    }'::json
  WHERE email = '$ADMIN_EMAIL';
"

echo ""
echo "=========================================="
echo "N8N Initialization Complete!"
echo "=========================================="
echo "Email: $ADMIN_EMAIL"
echo "Password: $ADMIN_PASSWORD"
echo ""
echo "Access n8n at: http://localhost:5678"
echo "=========================================="
