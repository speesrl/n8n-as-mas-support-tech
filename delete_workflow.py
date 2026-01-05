#!/usr/bin/env python3
"""
Script to delete a workflow from N8N by name.
Uses the N8N REST API with either API key or username/password authentication.
"""

import json
import logging
import os
import re
import requests
import sys
from pathlib import Path
from typing import Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Configuration
SCRIPT_DIR = Path(__file__).parent
CONFIG_DIR = SCRIPT_DIR / "volumes" / "config"
API_KEY_FILE = CONFIG_DIR / "n8n_api_key.txt"
SECRET_FILE = SCRIPT_DIR / ".secret"
N8N_URL = os.getenv("N8N_URL", "http://localhost:5678")
N8N_API_ENDPOINT = f"{N8N_URL}/api/v1/workflows"
N8N_REST_ENDPOINT = f"{N8N_URL}/rest/workflows"
N8N_LOGIN_ENDPOINT = f"{N8N_URL}/rest/login"


def load_credentials() -> Tuple[Optional[str], Optional[str]]:
    """
    Load N8N credentials from .secret file.
    
    Returns:
        Tuple of (email, password) or (None, None) if not found
    """
    if not SECRET_FILE.exists():
        return None, None
    
    try:
        with open(SECRET_FILE, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Parse email and password from .secret file
        email_match = re.search(r'N8N_ADMIN_EMAIL=([^\s]+)', content)
        password_match = re.search(r'N8N_ADMIN_PASSWORD=([^\s]+)', content)
        
        email = email_match.group(1) if email_match else None
        password = password_match.group(1) if password_match else None
        
        if email and password:
            logging.info("Credentials loaded from .secret file")
            return email, password
        else:
            logging.warning("Could not parse credentials from .secret file")
            return None, None
    except Exception as e:
        logging.warning(f"Error reading .secret file: {str(e)}")
        return None, None


def load_api_key() -> Optional[str]:
    """
    Load N8N API key from persistent volume file.
    
    Returns:
        API key string or None if not found
    """
    if not API_KEY_FILE.exists():
        return None
    
    try:
        with open(API_KEY_FILE, 'r', encoding='utf-8') as f:
            api_key = f.read().strip()
            if api_key:
                logging.info("API key loaded successfully")
                return api_key
            else:
                return None
    except Exception as e:
        logging.warning(f"Error reading API key file: {str(e)}")
        return None


def login_with_credentials(email: str, password: str) -> Optional[requests.Session]:
    """
    Login to N8N using username/password and return a session with cookies.
    
    Args:
        email: User email
        password: User password
        
    Returns:
        requests.Session object with authentication cookies, or None on failure
    """
    session = requests.Session()
    
    try:
        login_data = {
            "emailOrLdapLoginId": email,
            "password": password
        }
        
        response = session.post(
            N8N_LOGIN_ENDPOINT,
            json=login_data,
            headers={"Content-Type": "application/json"},
            timeout=30
        )
        
        if response.status_code == 200:
            logging.info(f"Successfully logged in as {email}")
            return session
        else:
            logging.error(f"Login failed: {response.status_code} - {response.text}")
            return None
            
    except requests.exceptions.RequestException as e:
        logging.error(f"Error during login: {str(e)}")
        return None


def find_workflow_by_name(workflow_name: str, session: Optional[requests.Session] = None,
                          api_key: Optional[str] = None) -> Optional[dict]:
    """
    Find a workflow by name in N8N.
    
    Args:
        workflow_name: Name of the workflow to find
        session: requests.Session with authentication cookies (for username/password auth)
        api_key: N8N API key (for API key auth)
        
    Returns:
        Workflow dictionary if found, None otherwise
    """
    try:
        headers = {}
        # Use REST endpoint with session, API endpoint with API key
        if session:
            # Use REST endpoint which supports cookie-based auth
            endpoint = N8N_REST_ENDPOINT
            response = session.get(endpoint, headers=headers, timeout=30)
        else:
            # Use API endpoint with API key
            if api_key:
                headers["X-N8N-API-KEY"] = api_key
            endpoint = N8N_API_ENDPOINT
            response = requests.get(endpoint, headers=headers, timeout=30)
        
        if response.status_code == 200:
            workflows_data = response.json()
            # REST endpoint might return data in a different format
            if isinstance(workflows_data, dict):
                # If it's a dict, try to get the workflows array
                workflows = workflows_data.get("data", workflows_data.get("workflows", []))
            elif isinstance(workflows_data, list):
                workflows = workflows_data
            else:
                logging.warning(f"Unexpected response format: {type(workflows_data)}")
                return None
            
            # Find workflow by name
            for workflow in workflows:
                if isinstance(workflow, dict) and workflow.get("name") == workflow_name:
                    return workflow
            
            return None
        else:
            logging.error(f"Error fetching workflows: {response.status_code} - {response.text}")
            return None
    except Exception as e:
        logging.error(f"Error finding workflow: {str(e)}")
        return None


def delete_workflow(workflow_id: str, workflow_name: str,
                   session: Optional[requests.Session] = None,
                   api_key: Optional[str] = None) -> bool:
    """
    Delete a workflow from N8N.
    
    Args:
        workflow_id: ID of the workflow to delete
        workflow_name: Name of the workflow (for logging)
        session: requests.Session with authentication cookies (for username/password auth)
        api_key: N8N API key (for API key auth)
        
    Returns:
        True if successful, False otherwise
    """
    try:
        headers = {}
        # Use REST endpoint with session, API endpoint with API key
        if session:
            # Use REST endpoint which supports cookie-based auth
            endpoint = f"{N8N_REST_ENDPOINT}/{workflow_id}"
            response = session.delete(endpoint, headers=headers, timeout=30)
        else:
            # Use API endpoint with API key
            if api_key:
                headers["X-N8N-API-KEY"] = api_key
            endpoint = f"{N8N_API_ENDPOINT}/{workflow_id}"
            response = requests.delete(endpoint, headers=headers, timeout=30)
        
        if response.status_code in [200, 204]:
            logging.info(f"✓ Workflow '{workflow_name}' (ID: {workflow_id}) deleted successfully")
            return True
        else:
            logging.error(f"✗ Error deleting workflow '{workflow_name}': {response.status_code} - {response.text}")
            return False
    except requests.exceptions.RequestException as e:
        logging.error(f"✗ Connection error deleting workflow '{workflow_name}': {str(e)}")
        return False
    except Exception as e:
        logging.error(f"✗ Unexpected error deleting workflow '{workflow_name}': {str(e)}")
        return False


def main():
    """Main function to delete a workflow."""
    import argparse
    
    global N8N_API_ENDPOINT, N8N_REST_ENDPOINT, N8N_LOGIN_ENDPOINT, N8N_URL
    
    parser = argparse.ArgumentParser(
        description="Delete a workflow from N8N by name"
    )
    parser.add_argument(
        "workflow_name",
        type=str,
        help="Name of the workflow to delete"
    )
    parser.add_argument(
        "--url",
        type=str,
        default=None,
        help=f"N8N URL (default: {N8N_URL})"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip confirmation prompt"
    )
    
    args = parser.parse_args()
    
    # Override N8N URL if provided
    if args.url:
        N8N_URL = args.url
        N8N_API_ENDPOINT = f"{args.url}/api/v1/workflows"
        N8N_REST_ENDPOINT = f"{args.url}/rest/workflows"
        N8N_LOGIN_ENDPOINT = f"{args.url}/rest/login"
        logging.info(f"Using N8N URL: {args.url}")
    
    # Try to authenticate: first with username/password, then with API key as fallback
    session = None
    api_key = None
    
    # Try username/password first
    email, password = load_credentials()
    if email and password:
        logging.info("Using username/password authentication")
        session = login_with_credentials(email, password)
        if not session:
            logging.warning("Failed to login with username/password, trying API key...")
            session = None
        else:
            logging.info("Successfully authenticated with username/password")
    
    # Fall back to API key if username/password failed or not available
    if not session:
        api_key = load_api_key()
        if api_key:
            logging.info("Using API key authentication")
        else:
            logging.error("No authentication method available!")
            logging.error("Please either:")
            logging.error("  1. Ensure .secret file contains N8N_ADMIN_EMAIL and N8N_ADMIN_PASSWORD")
            logging.error("  2. Or generate an API key in N8N Settings > API and save it to volumes/config/n8n_api_key.txt")
            sys.exit(1)
    
    # Check N8N connection
    logging.info(f"Connecting to N8N at {N8N_URL}...")
    try:
        headers = {}
        # Use REST endpoint with session, API endpoint with API key
        if session:
            # Use REST endpoint which supports cookie-based auth
            endpoint = N8N_REST_ENDPOINT
            response = session.get(endpoint, headers=headers, timeout=10)
        else:
            # Use API endpoint with API key
            if api_key:
                headers["X-N8N-API-KEY"] = api_key
            endpoint = N8N_API_ENDPOINT
            response = requests.get(endpoint, headers=headers, timeout=10)
        
        if response.status_code != 200:
            logging.error(f"Cannot connect to N8N: {response.status_code} - {response.text}")
            sys.exit(1)
    except requests.exceptions.RequestException as e:
        logging.error(f"Cannot connect to N8N: {str(e)}")
        logging.error(f"Make sure N8N is running at {N8N_URL}")
        sys.exit(1)
    
    logging.info("Connected to N8N successfully")
    
    # Find workflow by name
    logging.info(f"Searching for workflow: '{args.workflow_name}'...")
    workflow = find_workflow_by_name(args.workflow_name, session=session, api_key=api_key)
    
    if not workflow:
        logging.error(f"✗ Workflow '{args.workflow_name}' not found")
        sys.exit(1)
    
    workflow_id = workflow.get("id")
    if not workflow_id:
        logging.error(f"✗ Workflow found but has no ID")
        sys.exit(1)
    
    # Confirm deletion
    if not args.force:
        print(f"\n⚠ WARNING: You are about to delete workflow:")
        print(f"   Name: {args.workflow_name}")
        print(f"   ID: {workflow_id}")
        print(f"\nThis action cannot be undone!")
        response = input("\nAre you sure you want to delete this workflow? (yes/no): ")
        if response.lower() not in ['yes', 'y']:
            logging.info("Deletion cancelled by user")
            sys.exit(0)
    
    # Delete workflow
    logging.info(f"\nDeleting workflow '{args.workflow_name}'...")
    if delete_workflow(workflow_id, args.workflow_name, session=session, api_key=api_key):
        logging.info(f"\n✓ Workflow '{args.workflow_name}' deleted successfully")
        sys.exit(0)
    else:
        logging.error(f"\n✗ Failed to delete workflow '{args.workflow_name}'")
        sys.exit(1)


if __name__ == "__main__":
    main()
