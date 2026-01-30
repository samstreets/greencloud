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
DEFAULT_LOG_FILE="$SCRIPT_DIR/greencloud-setup-$(date +%Y%m%d-%H%M%S).log"
LOG_FILE="${GREENCLOUD_LOG_FILE:-$DEFAULT_LOG_FILE}"
LOG_ENABLED="${LOGGING:-false}"  # Set to "true" to disable

# Check if logging is enabled
if [ "$LOG_ENABLED" = "true" ]; then
  # Create log directory if it doesn't exist
  mkdir -p "$(dirname "$LOG_FILE")"
  # Initialize log file
  {
    echo "========================================"
    echo "GreenCloud Setup Log"
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
total=9
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

export DEBIAN_FRONTEND=noninteractive

log "Starting GreenCloud setup script"

run_step "Updating system packages…" \
  bash -c 'apt-get update -y'

run_step "Installing prerequisites (curl, wget, certs)…" \
  bash -c 'apt-get install -y curl wget ca-certificates'

run_step "Installing containerd and CNI plugins…" \
  bash -c 'apt-get install -y containerd runc containernetworking-plugins'

run_step "Configuring containerd…" bash -c '
  mkdir -p /etc/containerd
  command -v containerd >/dev/null
  containerd config default | tee /etc/containerd/config.toml >/dev/null
  # Ensure CNI binaries are in expected path
  mkdir -p /opt/cni/bin
  if [ -d /usr/lib/cni ]; then
    ln -sf /usr/lib/cni/* /opt/cni/bin/ || true
  elif [ -d /usr/libexec/cni ]; then
    ln -sf /usr/libexec/cni/* /opt/cni/bin/ || true
  fi
  systemctl enable --now containerd
'

run_step "Making ping group range persistent…" bash -c '
  set -euo pipefail

  SYSCTL_CONF="/etc/sysctl.d/99-ping-group.conf"
  PING_RANGE_LINE="net.ipv4.ping_group_range = 0 2147483647"
  PROC_NODE="/proc/sys/net/ipv4/ping_group_range"

  # 1) Persist the setting
  mkdir -p /etc/sysctl.d
  if [ -f "$SYSCTL_CONF" ] && grep -q "^net\.ipv4\.ping_group_range" "$SYSCTL_CONF"; then
    sed -i "s/^net\.ipv4\.ping_group_range.*/$PING_RANGE_LINE/" "$SYSCTL_CONF"
  else
    printf "%s\n" "$PING_RANGE_LINE" > "$SYSCTL_CONF"
  fi

  # 2) Apply immediately without relying on sysctl --system
  if [ -e "$PROC_NODE" ]; then
    # Write the two numbers directly into /proc node
    echo "0 2147483647" > "$PROC_NODE"
  else
    echo "WARNING: $PROC_NODE does not exist. Your kernel may not support ping_group_range." >&2
    exit 0
  fi

  # 3) Verify
  CURRENT=$(cat "$PROC_NODE")
  echo "Applied: net.ipv4.ping_group_range = $CURRENT"
'

# Architecture detection
step_progress "Detecting CPU architecture…"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    echo -e "${GREEN}✓ x86_64 architecture detected${NC}"
    log "Architecture detected: x86_64"
    GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-amd64"
    GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64"
    ;;
  aarch64|arm64)
    echo -e "${GREEN}✓ ARM64 architecture detected${NC}"
    log "Architecture detected: ARM64"
    GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-arm64"
    GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-arm64"
    ;;
  *)
    echo -e "${YELLOW}Unsupported architecture: $ARCH${NC}"
    log "ERROR: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

run_step "Downloading GreenCloud Node and CLI…" bash -c '
  set -Eeuo pipefail
  mkdir -p /var/lib/greencloud
  tmpdir="$(mktemp -d)"
  trap "rm -rf \"$tmpdir\"" RETURN
  curl -fsSL "'"$GCNODE_URL"'" -o "$tmpdir/gcnode"
  chmod +x "$tmpdir/gcnode"
  mv "$tmpdir/gcnode" /var/lib/greencloud/gcnode
  curl -fsSL "'"$GCCLI_URL"'" -o "$tmpdir/gccli"
  chmod +x "$tmpdir/gccli"
  mv "$tmpdir/gccli" /usr/local/bin/gccli
'
echo -e "${GREEN}✓ GreenCloud node and CLI installed for $ARCH${NC}"
log "GreenCloud node and CLI installed for $ARCH"

run_step "Downloading and setting up gcnode systemd service…" bash -c '
  set -Eeuo pipefail
  tmpdir="$(mktemp -d)"
  trap "rm -rf \"$tmpdir\"" RETURN
  curl -fsSL https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/Ubuntu/gcnode.service -o "$tmpdir/gcnode.service"
  mv "$tmpdir/gcnode.service" /etc/systemd/system/gcnode.service
  systemctl daemon-reload
  systemctl enable gcnode
'

echo -e "\n${YELLOW}🎉 All $((step - 1)) install steps completed successfully!${NC}"
log "All $((step - 1)) install steps completed successfully"

# --- Authentication & Node registration ---
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

echo -ne "\n${CYAN}Please enter what you would like to name the node: ${NC}"
read -r NODE_NAME
log "Node name set to: $NODE_NAME"

echo -e "\n${CYAN}Starting gcnode and extracting Node ID…${NC}"
log "Starting gcnode service"
systemctl start gcnode

# Wait for Node ID in logs
NODE_ID=""
attempts=0
max_attempts=30
sleep 2
while [ -z "$NODE_ID" ] && [ "$attempts" -lt "$max_attempts" ]; do
  NODE_ID="$(journalctl -u gcnode --no-pager -n 200 | sed -n "s/.*ID → \([a-f0-9-]\+\).*/\1/p" | tail -1)"
  if [ -z "$NODE_ID" ]; then
    echo -e "${YELLOW}Waiting for Node ID... (${attempts}/${max_attempts})${NC}"
    log "Waiting for Node ID (attempt ${attempts}/${max_attempts})"
    sleep 2
    attempts=$((attempts+1))
  fi
done

if [ -z "$NODE_ID" ]; then
  echo -e "${YELLOW}Failed to extract Node ID from logs${NC}"
  log "ERROR: Failed to extract Node ID after $max_attempts attempts"
  exit 1
fi

echo -e "${GREEN}✓ Captured Node ID: $NODE_ID${NC}"
log "Node ID captured: $NODE_ID"

echo -e "\n${CYAN}Adding node to GreenCloud...${NC}"
log "Adding node to GreenCloud with ID: $NODE_ID and name: $NODE_NAME"
if gccli node add --external --id "$NODE_ID" --description "$NODE_NAME" 2>&1 | log_output >/dev/null; then
  echo -e "${GREEN}✓ Node added successfully!${NC}"
  log "SUCCESS: Node added successfully"
else
  echo -e "${YELLOW}Failed to add node via gccli. Please retry manually:${NC}"
  echo "gccli node add --external --id $NODE_ID --description \"$NODE_NAME\""
  log "ERROR: Failed to add node via gccli"
  exit 1
fi

log "GreenCloud setup completed successfully"

if [ "$LOG_ENABLED" = "true" ]; then
  echo -e "\n${GREEN}✓ Full log saved to: $LOG_FILE${NC}"
fi
