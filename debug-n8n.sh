#!/bin/bash
# Diagnostic script for N8N setup issues

set -e

echo "=========================================="
echo "N8N Diagnostic Script"
echo "=========================================="
echo ""

echo "1. Checking container status..."
echo "----------------------------------------"
podman ps -a | grep -E "n8n|postgres|redis" || echo "No n8n containers found"
echo ""

echo "2. Checking if n8n-app container is running..."
echo "----------------------------------------"
if podman ps | grep -q n8n-app; then
    echo "✓ n8n-app is running"
    echo ""
    echo "3. Checking n8n-app logs (last 50 lines)..."
    echo "----------------------------------------"
    podman logs n8n-app --tail 50
else
    echo "✗ n8n-app is NOT running"
    echo ""
    echo "3. Checking why n8n-app is not running..."
    echo "----------------------------------------"
    if podman ps -a | grep -q n8n-app; then
        echo "Container exists but is stopped. Last logs:"
        podman logs n8n-app --tail 50
    else
        echo "Container n8n-app does not exist"
    fi
fi
echo ""

echo "4. Checking database container status..."
echo "----------------------------------------"
if podman ps | grep -q n8n-db; then
    echo "✓ n8n-db is running"
    echo ""
    echo "5. Testing database connection from host..."
    echo "----------------------------------------"
    podman exec n8n-db pg_isready -U n8n && echo "✓ Database is ready" || echo "✗ Database is not ready"
    echo ""
    echo "6. Checking database tables..."
    echo "----------------------------------------"
    TABLES=$(podman exec n8n-db psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
    echo "Number of tables in database: $TABLES"
    if [ "$TABLES" != "0" ] && [ -n "$TABLES" ]; then
        echo "Listing tables:"
        podman exec n8n-db psql -U n8n -d n8n -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;" 2>/dev/null | grep -v "^$" | head -20
    fi
else
    echo "✗ n8n-db is NOT running"
fi
echo ""

echo "7. Checking network connectivity..."
echo "----------------------------------------"
if podman ps | grep -q n8n-app && podman ps | grep -q n8n-db; then
    echo "Testing connection from n8n-app to n8n-db..."
    podman exec n8n-app nc -zv db 5432 2>&1 || echo "✗ Cannot connect to database"
    echo ""
    echo "Testing DNS resolution..."
    podman exec n8n-app getent hosts db || echo "✗ Cannot resolve 'db' hostname"
else
    echo "Skipping network test (containers not running)"
fi
echo ""

echo "8. Checking volume permissions..."
echo "----------------------------------------"
if [ -d "volumes/n8n_data" ]; then
    echo "n8n_data permissions:"
    ls -ld volumes/n8n_data
    echo "First level contents:"
    ls -la volumes/n8n_data 2>/dev/null | head -10 || echo "Cannot list contents (permission issue?)"
else
    echo "✗ volumes/n8n_data does not exist"
fi
echo ""

echo "9. Checking environment variables..."
echo "----------------------------------------"
echo "N8N_UID: ${N8N_UID:-not set}"
echo "N8N_GID: ${N8N_GID:-not set}"
echo ""

echo "10. Checking if n8n can access database from container..."
echo "----------------------------------------"
if podman ps | grep -q n8n-app && podman ps | grep -q n8n-db; then
    echo "Testing PostgreSQL connection from n8n-app container:"
    podman exec n8n-app sh -c "command -v psql >/dev/null 2>&1 && psql -h db -U n8n -d n8n -c 'SELECT version();' 2>&1 || echo 'psql not available in n8n-app container (this is normal)'"
else
    echo "Skipping (containers not running)"
fi
echo ""

echo "=========================================="
echo "Diagnostic Complete"
echo "=========================================="
echo ""
echo "Common issues and solutions:"
echo ""
echo "1. If n8n-app is not running:"
echo "   podman compose up -d"
echo ""
echo "2. If n8n-app is running but tables are not created:"
echo "   - Check logs: podman logs n8n-app"
echo "   - Look for database connection errors"
echo "   - Verify DB_POSTGRESDB_* environment variables"
echo ""
echo "3. If database connection fails:"
echo "   - Verify network: podman network ls"
echo "   - Check if containers are on same network"
echo "   - Verify extra_hosts in docker-compose.yml"
echo ""
echo "4. If permission errors:"
echo "   - Run: ./setup_permissions.sh"
echo "   - Set: export N8N_UID=\$(id -u) && export N8N_GID=\$(id -g)"
echo "   - Restart: podman compose down && podman compose up -d"
echo ""
