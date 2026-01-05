#!/usr/bin/env python3
"""
Script to test Redis connection from N8N container perspective.
"""

import sys

try:
    import redis
    print("✓ redis module available")
except ImportError:
    print("✗ redis module not available, installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "redis"])
    import redis

try:
    # Test connection
    r = redis.Redis(host='redis', port=6379, db=0, socket_connect_timeout=5)
    result = r.ping()
    print(f"✓ Redis connection successful: {result}")
    
    # Test basic operations
    r.set('test_key', 'test_value')
    value = r.get('test_key')
    print(f"✓ Redis read/write test successful: {value.decode()}")
    r.delete('test_key')
    print("✓ Redis connection fully functional")
    
except redis.ConnectionError as e:
    print(f"✗ Redis connection failed: {e}")
    print("\nTroubleshooting:")
    print("  1. Check if Redis container is running: podman ps | grep redis")
    print("  2. Check network connectivity: podman exec n8n-app nc -zv redis 6379")
    print("  3. Check Redis is listening: podman exec n8n-redis redis-cli ping")
    sys.exit(1)
except Exception as e:
    print(f"✗ Error: {e}")
    sys.exit(1)
