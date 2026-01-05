#!/usr/bin/env python3
"""
Script to save N8N API key to persistent volume.
This script can be executed inside the n8n-mcp container.
"""
import os
import sys
from pathlib import Path

# Configuration - same as in n8n_mcp_server.py
CONFIG_DIR = os.getenv("CONFIG_DIR", "/app/config")
API_KEY_FILE = Path(CONFIG_DIR) / "n8n_api_key.txt"

def save_api_key(api_key: str) -> bool:
    """
    Save N8N API key to persistent volume file.
    
    Args:
        api_key: The API key to save
    
    Returns:
        True if successful, False otherwise
    """
    try:
        # Ensure directory exists
        Path(CONFIG_DIR).mkdir(parents=True, exist_ok=True)
        
        # Save the API key
        with open(API_KEY_FILE, 'w', encoding='utf-8') as f:
            f.write(api_key.strip())
        
        # Set restrictive permissions (read/write for owner only)
        os.chmod(API_KEY_FILE, 0o600)
        
        print(f"API key saved successfully to: {API_KEY_FILE}")
        return True
    except Exception as e:
        print(f"Error saving API key: {str(e)}", file=sys.stderr)
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python save_api_key.py <api_key>", file=sys.stderr)
        sys.exit(1)
    
    api_key = sys.argv[1]
    if save_api_key(api_key):
        sys.exit(0)
    else:
        sys.exit(1)

