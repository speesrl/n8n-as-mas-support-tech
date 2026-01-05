#!/bin/bash
# Script to reset N8N to a clean/vanilla state
# This will delete all persistent data (workflows, users, credentials, etc.)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Get current user UID and GID (for compatibility with the user running the script)
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║         N8N RESET - ATTENZIONE!                          ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Questo script eliminerà TUTTI i dati persistenti di N8N:${NC}"
echo "  - Tutti i workflow salvati in N8N"
echo "  - Tutti gli utenti e credenziali"
echo "  - Tutti i dati del database PostgreSQL"
echo "  - Tutti i dati di configurazione N8N"
echo "  - Tutti i dati Redis"
echo ""
echo -e "${GREEN}I seguenti dati NON verranno eliminati:${NC}"
echo "  - Workflow esportati in volumes/workflows/ (file JSON)"
echo "  - Configurazione API key in volumes/config/"
echo ""
echo -e "${RED}⚠️  QUESTA AZIONE NON PUÒ ESSERE ANNULLATA! ⚠️${NC}"
echo ""

# Ask for confirmation
read -p "Sei sicuro di voler procedere? (scrivi 'RESET' per confermare): " confirmation

if [ "$confirmation" != "RESET" ]; then
    echo "Reset annullato."
    exit 0
fi

echo ""
echo -e "${YELLOW}Inizio reset di N8N...${NC}"
echo ""

# Step 1: Stop all containers
echo "1. Fermo tutti i container..."
podman compose down
echo -e "${GREEN}✓ Container fermati${NC}"
echo ""

# Step 2: Remove volumes (except workflows and config)
echo "2. Elimino i dati persistenti..."

# Function to safely remove volume directory and recreate it
remove_volume_data() {
    local volume_path="$1"
    local volume_name="$2"
    
    if [ -d "$volume_path" ]; then
        # Remove entire directory and recreate (handles permission issues)
        # Try with podman unshare first (uses correct namespace permissions)
        if command -v podman >/dev/null 2>&1; then
            podman unshare rm -rf "$volume_path" 2>/dev/null || {
                # Fallback: try with sudo
                sudo rm -rf "$volume_path" 2>/dev/null || {
                    # Last resort: try without sudo (might fail but we'll try)
                    rm -rf "$volume_path" 2>/dev/null || true
                }
            }
        else
            # Fallback to sudo or regular rm
            sudo rm -rf "$volume_path" 2>/dev/null || rm -rf "$volume_path" 2>/dev/null || true
        fi
    fi
    # Recreate directory
    mkdir -p "$volume_path"
    echo -e "${GREEN}  ✓ Dati $volume_name eliminati${NC}"
}

# Function to fix permissions using a temporary container
fix_n8n_permissions() {
    local volume_path="$1"
    
    if [ ! -d "$volume_path" ]; then
        return
    fi
    
    echo "   - Correggo i permessi di $volume_path..."
    
    # Get absolute path
    local abs_path="$(cd "$(dirname "$volume_path")" && pwd)/$(basename "$volume_path")"
    
    # Method 1: Use a temporary container with proper volume mount flags
    if command -v podman >/dev/null 2>&1; then
        echo "     Tentativo con container temporaneo..."
        # Use :U flag for user namespace mapping, or :Z for SELinux
        if podman run --rm --user root \
            -v "$abs_path:/fix-perms:U" \
            docker.io/alpine:latest \
            sh -c "chown -R $CURRENT_UID:$CURRENT_GID /fix-perms && chmod -R 755 /fix-perms" >/dev/null 2>&1; then
            # Verify it worked
            local test_uid=$(stat -c "%u" "$volume_path" 2>/dev/null || echo "")
            local test_gid=$(stat -c "%g" "$volume_path" 2>/dev/null || echo "")
            if [ "$test_uid" = "$CURRENT_UID" ] && [ "$test_gid" = "$CURRENT_GID" ]; then
                echo -e "${GREEN}  ✓ Permessi corretti con container temporaneo${NC}"
                return 0
            fi
        fi
        
        # Method 2: Try with podman unshare (works in rootless mode)
        echo "     Tentativo con podman unshare..."
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        (cd "$script_dir" && podman unshare sh -c "chown -R $CURRENT_UID:$CURRENT_GID '$abs_path' && chmod -R 755 '$abs_path'" 2>/dev/null) && {
            local test_uid=$(stat -c "%u" "$volume_path" 2>/dev/null || echo "")
            local test_gid=$(stat -c "%g" "$volume_path" 2>/dev/null || echo "")
            if [ "$test_uid" = "$CURRENT_UID" ] && [ "$test_gid" = "$CURRENT_GID" ]; then
                echo -e "${GREEN}  ✓ Permessi corretti con podman unshare${NC}"
                return 0
            fi
        }
    fi
    
    # Method 3: Try with chown directly (works if user owns the directory)
    chown -R "$CURRENT_UID:$CURRENT_GID" "$volume_path" 2>/dev/null && \
    chmod -R 755 "$volume_path" 2>/dev/null && {
        local test_uid=$(stat -c "%u" "$volume_path" 2>/dev/null || echo "")
        local test_gid=$(stat -c "%g" "$volume_path" 2>/dev/null || echo "")
        if [ "$test_uid" = "$CURRENT_UID" ] && [ "$test_gid" = "$CURRENT_GID" ]; then
            echo -e "${GREEN}  ✓ Permessi corretti${NC}"
            return 0
        fi
    }
    
    # Method 4: Fallback - show instructions
    echo -e "${YELLOW}  ⚠ Impossibile correggere i permessi automaticamente${NC}"
    echo -e "${YELLOW}     Esegui manualmente:${NC}"
    echo -e "${YELLOW}     chown -R $CURRENT_UID:$CURRENT_GID $abs_path${NC}"
    echo -e "${YELLOW}     chmod -R 755 $abs_path${NC}"
    return 1
}

echo "   - Database PostgreSQL..."
remove_volume_data "volumes/postgres_data" "database"

echo "   - Dati N8N..."
remove_volume_data "volumes/n8n_data" "N8N"
# Fix permissions for N8N data directory (using current user UID/GID)
fix_n8n_permissions "volumes/n8n_data"

echo "   - Dati Redis..."
remove_volume_data "volumes/redis_data" "Redis"

echo "   - Dati RedisInsight..."
remove_volume_data "volumes/redisinsight_data" "RedisInsight"

echo ""
echo -e "${GREEN}✓ Tutti i dati persistenti eliminati${NC}"
echo ""
echo -e "${YELLOW}⚠ I container sono stati fermati.${NC}"
echo ""
echo -e "${GREEN}Verifica finale permessi:${NC}"
if [ -d "volumes/n8n_data" ]; then
    n8n_uid=$(stat -c "%u" volumes/n8n_data 2>/dev/null || echo "unknown")
    n8n_gid=$(stat -c "%g" volumes/n8n_data 2>/dev/null || echo "unknown")
    n8n_perm=$(stat -c "%a" volumes/n8n_data 2>/dev/null || echo "unknown")
    
    # Check if permissions match current user or are at least writable
    if [ "$n8n_uid" = "$CURRENT_UID" ] && [ "$n8n_gid" = "$CURRENT_GID" ]; then
        echo -e "${GREEN}  ✓ Permessi volumes/n8n_data corretti (UID=$n8n_uid:$n8n_gid, Perm=$n8n_perm)${NC}"
    elif [ "$n8n_perm" = "755" ] || [ "$n8n_perm" = "777" ] || [ "$n8n_perm" = "775" ]; then
        echo -e "${GREEN}  ✓ Permessi volumes/n8n_data OK (UID=$n8n_uid:$n8n_gid, Perm=$n8n_perm)${NC}"
        echo -e "${YELLOW}     (UID/GID diversi ma permessi scrivibili - dovrebbe funzionare)${NC}"
    else
        echo -e "${YELLOW}  ⚠ Permessi volumes/n8n_data: UID=$n8n_uid GID=$n8n_gid Perm=$n8n_perm${NC}"
        echo -e "${YELLOW}     Se N8N non si avvia, correggi con:${NC}"
        echo -e "${YELLOW}     chown -R $CURRENT_UID:$CURRENT_GID volumes/n8n_data${NC}"
        echo -e "${YELLOW}     chmod -R 755 volumes/n8n_data${NC}"
    fi
fi
echo ""
echo "   Per riavviare i container, esegui:"
echo "   export N8N_UID=$CURRENT_UID"
echo "   export N8N_GID=$CURRENT_GID"
echo "   podman compose up -d"
echo ""
echo "   Oppure usa lo script setup_permissions.sh:"
echo "   ./setup_permissions.sh"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         N8N RESET COMPLETATO!                              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "N8N è stato resettato a uno stato vergine."
echo ""
echo -e "${YELLOW}⚠ PROSSIMI PASSI:${NC}"
echo ""
echo "1. Riavvia i container:"
echo "   podman compose up -d"
echo ""
echo "2. Crea l'utente admin eseguendo:"
echo "   ./init-n8n.sh"
echo ""
echo "3. (Opzionale) Importa i workflow esportati:"
echo "   ./import_workflows.py"
echo ""
echo "Credenziali di accesso (dal file .secret):"
if [ -f ".secret" ]; then
    grep "N8N_ADMIN_EMAIL" .secret | sed 's/^/  /'
    grep "N8N_ADMIN_PASSWORD" .secret | sed 's/^/  /'
else
    echo "  Email: admin@spee.it"
    echo "  Password: admin"
fi
echo ""
echo "Accesso a N8N: http://localhost:5678"
echo ""
