from mcp.server.fastmcp import FastMCP, Context
import json
import logging
import os
import requests
from typing import Optional
from datetime import datetime
from pathlib import Path

logging.basicConfig(level=logging.INFO)

# Configuration from environment variables
N8N_URL = os.getenv("N8N_URL", "http://n8n:5678")
WORKFLOWS_DIR = os.getenv("WORKFLOWS_DIR", "/app/workflows")
CONFIG_DIR = os.getenv("CONFIG_DIR", "/app/config")
API_KEY_FILE = Path(CONFIG_DIR) / "n8n_api_key.txt"

# Ensure directories exist
Path(WORKFLOWS_DIR).mkdir(parents=True, exist_ok=True)
Path(CONFIG_DIR).mkdir(parents=True, exist_ok=True)

def load_api_key() -> str:
    """
    Load N8N API key from persistent volume file, fallback to environment variable.
    
    Returns:
        API key string
    """
    # First try to load from persistent volume file
    if API_KEY_FILE.exists():
        try:
            with open(API_KEY_FILE, 'r', encoding='utf-8') as f:
                api_key = f.read().strip()
                if api_key:
                    logging.info("API key loaded from persistent volume")
                    return api_key
        except Exception as e:
            logging.warning(f"Error reading API key from file: {str(e)}")
    
    # Fallback to environment variable
    api_key = os.getenv("N8N_API_KEY", "")
    if api_key:
        logging.info("API key loaded from environment variable")
    else:
        logging.warning("No API key found in persistent volume or environment")
    
    return api_key

def _save_api_key_to_file(api_key: str) -> bool:
    """
    Save N8N API key to persistent volume file.
    
    Args:
        api_key: The API key to save
    
    Returns:
        True if successful, False otherwise
    """
    try:
        with open(API_KEY_FILE, 'w', encoding='utf-8') as f:
            f.write(api_key.strip())
        # Set restrictive permissions (read/write for owner only)
        os.chmod(API_KEY_FILE, 0o600)
        logging.info(f"API key saved to persistent volume: {API_KEY_FILE}")
        return True
    except Exception as e:
        logging.error(f"Error saving API key to file: {str(e)}")
        return False

# Load API key on startup
N8N_API_KEY = load_api_key()

mcp = FastMCP("N8N Workflow Builder", host='0.0.0.0', port=8012, sse_path='/')

def generate_workflow_json(requirements: str, workflow_name: str = "Generated Workflow") -> dict:
    """
    Generate N8N workflow JSON structure from requirements.
    This is a template generator - in production, you'd use an LLM here.
    """
    # Base workflow structure
    workflow = {
        "name": workflow_name,
        "nodes": [
            {
                "parameters": {},
                "id": "start-1",
                "name": "Start",
                "type": "n8n-nodes-base.start",
                "typeVersion": 1,
                "position": [250, 300]
            }
        ],
        "connections": {},
        "pinData": {},
        "settings": {
            "executionOrder": "v1"
        },
        "staticData": None,
        "tags": []
    }
    
    # TODO: Here you would use an LLM to parse requirements and generate nodes
    # For now, this is a template that can be extended
    
    return workflow

def save_workflow_to_file(workflow: dict, filename: Optional[str] = None) -> str:
    """
    Save workflow JSON to persistent volume.
    
    Args:
        workflow: Workflow dictionary
        filename: Optional filename (default: workflow name with timestamp)
    
    Returns:
        Path to saved file
    """
    if not filename:
        # Create filename from workflow name, sanitize it
        workflow_name = workflow.get("name", "workflow")
        safe_name = "".join(c for c in workflow_name if c.isalnum() or c in (' ', '-', '_')).strip()
        safe_name = safe_name.replace(' ', '_')
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{safe_name}_{timestamp}.json"
    
    # Ensure .json extension
    if not filename.endswith('.json'):
        filename += '.json'
    
    filepath = Path(WORKFLOWS_DIR) / filename
    
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(workflow, f, indent=2, ensure_ascii=False)
    
    logging.info(f"Workflow saved to: {filepath}")
    return str(filepath)

@mcp.tool()
async def generate_workflow(requirements: str, workflow_name: Optional[str] = None, save_to_file: bool = True) -> str:
    """
    Generate N8N workflow JSON from requirements and specifications.
    The workflow is automatically saved to the persistent volume.
    
    Args:
        requirements: Description of the workflow requirements
        workflow_name: Optional name for the workflow (default: "Generated Workflow")
        save_to_file: Whether to save the workflow to persistent storage (default: True)
    
    Returns:
        JSON string of the N8N workflow and file path if saved
    """
    if not workflow_name:
        workflow_name = "Generated Workflow"
    
    logging.info(f"Generating workflow: {workflow_name}")
    logging.info(f"Requirements: {requirements}")
    
    workflow = generate_workflow_json(requirements, workflow_name)
    
    result = {
        "workflow": workflow,
        "workflow_json": json.dumps(workflow, indent=2)
    }
    
    if save_to_file:
        filepath = save_workflow_to_file(workflow)
        result["saved_to"] = filepath
        result["message"] = f"Workflow generated and saved to: {filepath}"
    else:
        result["message"] = "Workflow generated (not saved to file)"
    
    return json.dumps(result, indent=2)

@mcp.tool()
async def save_api_key(api_key: str) -> str:
    """
    Save N8N API key to persistent volume.
    
    Args:
        api_key: The N8N API key to save
    
    Returns:
        Success or error message
    """
    if _save_api_key_to_file(api_key):
        # Reload the API key in memory
        global N8N_API_KEY
        N8N_API_KEY = api_key
        return f"API key saved successfully to persistent volume: {API_KEY_FILE}"
    else:
        return "Error: Failed to save API key to persistent volume."

@mcp.tool()
async def import_workflow(workflow_json: str, ctx: Context, save_to_file: bool = True) -> str:
    """
    Import a workflow JSON into N8N instance.
    Optionally saves the workflow to persistent storage before importing.
    
    Args:
        workflow_json: JSON string of the N8N workflow
        save_to_file: Whether to save the workflow to persistent storage (default: True)
    
    Returns:
        Response message with workflow ID if successful
    """
    api_key = load_api_key()
    if not api_key:
        return "Error: N8N_API_KEY not configured. Please use save_api_key tool or set it in environment variables."
    
    try:
        workflow_data = json.loads(workflow_json)
        
        # Save to file if requested
        saved_path = None
        if save_to_file:
            saved_path = save_workflow_to_file(workflow_data)
            await ctx.report_progress(f"Workflow saved to: {saved_path}")
        
        api_key = load_api_key()
        headers = {
            "X-N8N-API-KEY": api_key,
            "Content-Type": "application/json"
        }
        
        await ctx.report_progress("Importing workflow to N8N...")
        response = requests.post(
            f"{N8N_URL}/api/v1/workflows",
            json=workflow_data,
            headers=headers,
            timeout=30
        )
        
        if response.status_code in [200, 201]:
            result = response.json()
            workflow_id = result.get("id", "unknown")
            await ctx.report_progress(f"Workflow imported successfully! ID: {workflow_id}")
            
            message = f"Workflow imported successfully! ID: {workflow_id}, Name: {result.get('name', 'N/A')}"
            if saved_path:
                message += f"\nWorkflow also saved to: {saved_path}"
            return message
        else:
            error_msg = f"Error importing workflow: {response.status_code} - {response.text}"
            logging.error(error_msg)
            return error_msg
            
    except json.JSONDecodeError as e:
        return f"Error: Invalid JSON format - {str(e)}"
    except requests.exceptions.RequestException as e:
        return f"Error connecting to N8N: {str(e)}"
    except Exception as e:
        logging.error(f"Unexpected error: {str(e)}")
        return f"Error: {str(e)}"

@mcp.tool()
async def list_workflows() -> str:
    """
    List all workflows in the N8N instance.
    
    Returns:
        JSON string with list of workflows
    """
    api_key = load_api_key()
    if not api_key:
        return "Error: N8N_API_KEY not configured. Please use save_api_key tool or set it in environment variables."
    
    try:
        headers = {"X-N8N-API-KEY": api_key}
        response = requests.get(
            f"{N8N_URL}/api/v1/workflows",
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            workflows = response.json()
            return json.dumps(workflows, indent=2)
        else:
            return f"Error: {response.status_code} - {response.text}"
            
    except requests.exceptions.RequestException as e:
        return f"Error connecting to N8N: {str(e)}"
    except Exception as e:
        logging.error(f"Unexpected error: {str(e)}")
        return f"Error: {str(e)}"

@mcp.tool()
async def get_workflow(workflow_id: str, save_to_file: bool = False) -> str:
    """
    Get a specific workflow by ID from N8N.
    Optionally saves the workflow to persistent storage.
    
    Args:
        workflow_id: The ID of the workflow to retrieve
        save_to_file: Whether to save the workflow to persistent storage (default: False)
    
    Returns:
        JSON string of the workflow
    """
    api_key = load_api_key()
    if not api_key:
        return "Error: N8N_API_KEY not configured. Please use save_api_key tool or set it in environment variables."
    
    try:
        headers = {"X-N8N-API-KEY": api_key}
        response = requests.get(
            f"{N8N_URL}/api/v1/workflows/{workflow_id}",
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            workflow = response.json()
            result = {"workflow": workflow}
            
            if save_to_file:
                filepath = save_workflow_to_file(workflow)
                result["saved_to"] = filepath
                result["message"] = f"Workflow retrieved and saved to: {filepath}"
            else:
                result["message"] = "Workflow retrieved"
            
            return json.dumps(result, indent=2)
        else:
            return f"Error: {response.status_code} - {response.text}"
            
    except requests.exceptions.RequestException as e:
        return f"Error connecting to N8N: {str(e)}"
    except Exception as e:
        logging.error(f"Unexpected error: {str(e)}")
        return f"Error: {str(e)}"

@mcp.tool()
async def list_saved_workflows() -> str:
    """
    List all workflow JSON files saved in the persistent volume.
    
    Returns:
        JSON string with list of saved workflow files
    """
    try:
        workflows_dir = Path(WORKFLOWS_DIR)
        if not workflows_dir.exists():
            return json.dumps({"workflows": [], "message": "Workflows directory does not exist"})
        
        workflow_files = []
        for filepath in sorted(workflows_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True):
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    workflow_data = json.load(f)
                    workflow_files.append({
                        "filename": filepath.name,
                        "path": str(filepath),
                        "name": workflow_data.get("name", "Unknown"),
                        "size": filepath.stat().st_size,
                        "modified": datetime.fromtimestamp(filepath.stat().st_mtime).isoformat()
                    })
            except Exception as e:
                logging.warning(f"Error reading {filepath}: {str(e)}")
        
        return json.dumps({
            "workflows": workflow_files,
            "count": len(workflow_files),
            "directory": WORKFLOWS_DIR
        }, indent=2)
        
    except Exception as e:
        logging.error(f"Error listing workflows: {str(e)}")
        return f"Error: {str(e)}"

if __name__ == "__main__":
    logging.info(f"Starting N8N MCP Server on port 8012")
    logging.info(f"N8N URL: {N8N_URL}")
    logging.info(f"N8N API Key configured: {bool(N8N_API_KEY)}")
    logging.info(f"API Key file: {API_KEY_FILE}")
    logging.info(f"Workflows directory: {WORKFLOWS_DIR}")
    logging.info(f"Config directory: {CONFIG_DIR}")
    mcp.run(transport="sse")

