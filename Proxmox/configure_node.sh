#!/bin/bash
set -euo pipefail
set -o pipefail

# --- Error reporting ---
trap 'echo -e "\n\033[1;31m✖ Error on line $LINENO. Aborting.\033[0m" >&2' ERR

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Spinner that takes a PID and waits on it
spin() {
  local pid="${1:-}"
  local delay=0.1
  local chars='|/-\'
  local i=0

  [ -z "$pid" ] && return 1
  while kill -0 "$pid" 2>/dev/null; do
    # Print rotating char
    printf "\r[%c] " "${chars:i++%${#chars}:1}"
    sleep "$delay"
  done
  printf "\r    \r"
}

# --- Authentication & Node registration ---
gccli logout -q >/dev/null 2>&1 || true

echo -ne "\n${CYAN}Please enter your GreenCloud API key (input hidden): ${NC}"
read -rs API_KEY
echo
if ! gccli login -k "$API_KEY" >/dev/null 2>&1; then
  echo -e "${YELLOW}Login failed. Please check your API key.${NC}"
  exit 1
fi

echo -ne "\n${CYAN}Please enter what you would like to name the node: ${NC}"
read -r NODE_NAME

echo -e "\n${CYAN}Starting gcnode and extracting Node ID…${NC}"
rm /var/lib/greencloud/gcnode.log
systemctl restart gcnode

LOG_FILE="/var/lib/greencloud/gcnode.log"

# Wait for log file to appear (in case systemd creates it slightly later)
attempts=0
max_attempts=10
while [ ! -f "$LOG_FILE" ] && [ "$attempts" -lt "$max_attempts" ]; do
  echo -e "${YELLOW}Waiting for gcnode log to appear... (${attempts}/${max_attempts})${NC}"
  sleep 1
  attempts=$((attempts+1))
done

if [ ! -f "$LOG_FILE" ]; then
  echo -e "${RED}Log file not created — cannot extract Node ID.${NC}"
  exit 1
fi

# Extract Node ID from file
NODE_ID=""
attempts=0
max_attempts=10

sleep 2

while [ -z "$NODE_ID" ] && [ "$attempts" -lt "$max_attempts" ]; do
  NODE_ID="$(sed -n 's/.*ID → \([a-f0-9-]\+\).*/\1/p' "$LOG_FILE" | tail -1)"
  if [ -z "$NODE_ID" ]; then
    echo -e "${YELLOW}Waiting for Node ID... (${attempts}/${max_attempts})${NC}"
    sleep 2
    attempts=$((attempts+1))
  fi
done

if [ -z "$NODE_ID" ]; then
  echo -e "${RED}Failed to detect Node ID after $((max_attempts*2)) seconds.${NC}"
  exit 1
fi

echo -e "${GREEN}✔ Captured Node ID: $NODE_ID${NC}"

echo -e "\n${CYAN}Adding node to GreenCloud...${NC}"
if gccli node add --external --id "$NODE_ID" --description "$NODE_NAME" >/dev/null 2>&1; then
  echo -e "${GREEN}✔ Node added successfully!${NC}"
else
  echo -e "${YELLOW}Failed to add node via gccli. Please retry manually:${NC}"
  echo "gccli node add --external --id $NODE_ID --description \"$NODE_NAME\""
  exit 1

fi

