#!/bin/bash
# Test Redis connection from N8N container

echo "Testing Redis connection from N8N container..."
echo ""

echo "1. Checking if Redis container is running:"
podman ps | grep redis
echo ""

echo "2. Testing network connectivity:"
podman exec n8n-app nc -zv redis 6379
echo ""

echo "3. Testing DNS resolution:"
podman exec n8n-app getent hosts redis
echo ""

echo "4. Testing Redis directly:"
podman exec n8n-redis redis-cli ping
echo ""

echo "5. If all above work, the issue is likely in N8N credential configuration."
echo "   Make sure in N8N UI:"
echo "   - Host is set to: redis"
echo "   - Port is set to: 6379 (NOT 6389! Port 6389 is only for host access)"
echo "   - Password is empty (unless Redis has password)"
echo "   - Database is 0"
echo "   - Credentials are saved and selected in the Redis node"
echo ""
echo "   ⚠️  IMPORTANT: Use port 6379, not 6389!"
echo "      Port 6389 is the mapped port for host access (see docker-compose.yml: 6389:6379)"
echo "      When N8N (container) connects to Redis (container), use internal port 6379"
