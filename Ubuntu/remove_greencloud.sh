#!/usr/bin/env bash
set -Eeuo pipefail

# Colors - Must be defined first
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuration ---
# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default log file in script directory with timestamp
DEFAULT_LOG_FILE="$SCRIPT_DIR/greencloud-remove-$(date +%Y%m%d-%H%M%S).log"
LOG_FILE="${GREENCLOUD_LOG_FILE:-$DEFAULT_LOG_FILE}"
LOG_ENABLED="${LOGGING:-false}"  # Set to "true" to enable

# Check if logging is enabled
if [ "$LOG_ENABLED" = "true" ]; then
  # Create log directory if it doesn't exist
  mkdir -p "$(dirname "$LOG_FILE")"
  # Initialize log file
  {
    echo "========================================"
    echo "GreenCloud Removal Log"
    echo "Started: $(date)"
    echo "Script Location: $SCRIPT_DIR"
    echo "========================================"
  } > "$LOG_FILE"
  echo -e "${GREEN}✓ Logging enabled: $LOG_FILE${NC}\n"
else
  echo -e "${YELLOW}ℹ Logging disabled${NC}\n"
fi

# Logging function - pipes output to both stdout and log file
log_output() {
  if [ "$LOG_ENABLED" = "true" ]; then
    tee -a "$LOG_FILE"
  else
    cat
  fi
}

# Log a message
log() {
  local msg="$1"
  if [ "$LOG_ENABLED" = "true" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
  fi
}

# --- Error reporting ---
trap 'echo -e "\n\033[1;31m✖ Error on line $LINENO. Aborting.\033[0m" >&2; log "ERROR: Script failed on line $LINENO"' ERR

# Spinner that takes a PID and waits on it
spin() {
  local pid="${1:-}"
  local delay=0.1
  local spinstr='|/-\'
  [ -z "$pid" ] && return 1
  while kill -0 "$pid" 2>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep "$delay"
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# Step counter
step=1
total=4
step_progress() {
  echo -e "${CYAN}Step $step of $total: $1${NC}"
  log "Step $step of $total: $1"
  ((step++))
}

# Run a step with real-time output (when logging enabled) and hard failure on non-zero exit
run_step() {
  local title="$1"
  shift
  step_progress "$title"
  
  # Create temporary files for capturing output
  local tmpout tmperr
  tmpout="$(mktemp)"
  tmperr="$(mktemp)"
  trap "rm -f '$tmpout' '$tmperr'" RETURN
  
  local exit_code=0
  
  if [ "$LOG_ENABLED" = "true" ]; then
    # Show real-time output to screen AND log to file
    echo -e "${CYAN}--- Begin output ---${NC}"
    {
      set -Eeuo pipefail
      "$@" 2> >(tee "$tmperr" >&2)
    } 2>&1 | tee "$tmpout" | tee -a "$LOG_FILE" || exit_code=$?
    echo -e "${CYAN}--- End output ---${NC}"
  else
    # Silent execution with spinner
    {
      set -Eeuo pipefail
      "$@"
    } >"$tmpout" 2>"$tmperr" &
    local pid=$!
    spin "$pid"
    wait "$pid" || exit_code=$?
  fi
  
  if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}✓ ${title/…/} completed${NC}\n"
    log "SUCCESS: ${title/…/} completed"
    
    # Log output summary if logging is enabled
    if [ "$LOG_ENABLED" = "true" ]; then
      {
        echo "--- Step completed successfully ---"
        echo ""
      } >> "$LOG_FILE"
    fi
  else
    echo -e "${YELLOW}⚠ ${title/…/} failed${NC}"
    log "FAILED: ${title/…/} failed (exit code: $exit_code)"
    
    # Show error output if logging was disabled
    if [ "$LOG_ENABLED" != "true" ]; then
      echo -e "${YELLOW}Error output:${NC}" >&2
      cat "$tmpout" >&2
      cat "$tmperr" >&2
    fi
    
    # Log error output
    if [ "$LOG_ENABLED" = "true" ] && [ -s "$tmperr" ]; then
      {
        echo "--- Error output ---"
        cat "$tmperr"
        echo "--- End error output ---"
        echo ""
      } >> "$LOG_FILE"
    fi
    
    exit 1
  fi
}

log "Starting GreenCloud removal script"

# --- Authentication & Node removal ---
gccli logout -q >/dev/null 2>&1 || true

echo -ne "\n${CYAN}Please enter your GreenCloud API key (input hidden): ${NC}"
read -rs API_KEY
echo
log "Attempting login with API key"
if ! gccli login -k "$API_KEY" 2>&1 | log_output >/dev/null; then
  echo -e "${YELLOW}Login failed. Please check your API key.${NC}"
  log "ERROR: Login failed"
  exit 1
fi
log "Login successful"

# Extract and display GreenCloud Node ID
echo -e "\n${CYAN}Extracting GreenCloud Node ID…${NC}"
log "Restarting gcnode to extract Node ID"
systemctl restart gcnode
sleep 2

NODE_ID=""
attempts=0
max_attempts=30
while [ -z "$NODE_ID" ] && [ "$attempts" -lt "$max_attempts" ]; do
  NODE_ID="$(systemctl status gcnode 2>/dev/null | grep -oP '(?<=ID → )[a-f0-9-]+' || true)"
  if [ -z "$NODE_ID" ]; then
    echo -e "${YELLOW}Waiting for Node ID... (${attempts}/${max_attempts})${NC}"
    log "Waiting for Node ID (attempt ${attempts}/${max_attempts})"
    sleep 2
    attempts=$((attempts+1))
  fi
done

if [ -z "$NODE_ID" ]; then
  echo -e "${YELLOW}Failed to extract Node ID from systemctl status${NC}"
  log "ERROR: Failed to extract Node ID after $max_attempts attempts"
  exit 1
fi

echo -e "${GREEN}✓ Captured Node ID: $NODE_ID${NC}"
log "Node ID captured: $NODE_ID"

# Removing node from GreenCloud
echo -e "\n${CYAN}Removing node from GreenCloud...${NC}"
log "Stopping gcnode service"
systemctl stop gcnode

log "Deleting node from GreenCloud with ID: $NODE_ID"
if gccli node delete -i "$NODE_ID" 2>&1 | log_output >/dev/null; then
  echo -e "${GREEN}✓ Node removed successfully!${NC}"
  log "SUCCESS: Node removed from GreenCloud"
else
  echo -e "${YELLOW}Failed to remove node via gccli. Please retry manually:${NC}"
  echo "gccli node delete -i $NODE_ID"
  log "ERROR: Failed to remove node via gccli"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

run_step "Removing containerd…" \
  bash -c 'apt remove -y containerd'

run_step "Removing runc…" \
  bash -c 'apt remove -y runc'

run_step "Removing GreenCloud Node and CLI…" bash -c '
  rm -rf /var/lib/greencloud
  rm -f /usr/local/bin/gccli
'

run_step "Removing gcnode systemd service…" bash -c '
  rm -f /etc/systemd/system/gcnode.service
  systemctl daemon-reload
'

echo -e "\n${YELLOW}🎉 All $((step - 1)) removal steps completed successfully!${NC}"
log "GreenCloud removal completed successfully"

if [ "$LOG_ENABLED" = "true" ]; then
  echo -e "\n${GREEN}✓ Full log saved to: $LOG_FILE${NC}"
fi
