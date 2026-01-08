
#!/usr/bin/env bash
set -Eeuo pipefail

# --- Error reporting ---
trap 'echo -e "\n\033[1;31m✖ Error on line $LINENO. Aborting.\033[0m" >&2' ERR

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Authentication & Node registration ---
gccli logout -q >/dev/null 2>&1 || true

echo -ne "\n${CYAN}Please enter your GreenCloud API key (input hidden): ${NC}"
read -rs API_KEY
echo
if ! gccli login -k "$API_KEY"  >/dev/null 2>&1; then
  echo -e "${YELLOW}Login failed. Please check your API key.${NC}"
  exit 1
fi

echo -ne "\n${CYAN}Please enter what you would like to name the node: ${NC}"
read -r NODE_NAME

echo -e "\n${CYAN}Starting gcnode and extracting Node ID…${NC}"
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
    sleep 2
    attempts=$((attempts+1))
  fi
done


echo -e "${GREEN}✔ Captured Node ID: $NODE_ID${NC}"

echo -e "\n${CYAN}Adding node to GreenCloud...${NC}"
if gccli node add --external --id "$NODE_ID" --description "$NODE_NAME" >/dev/null 2>&1; then
  echo -e "${GREEN}✔ Node added successfully!${NC}"
else
  echo -e "${YELLOW}Failed to add node via gccli. Please retry manually:${NC}"
  echo "gccli node add --external --id $NODE_ID --description \"$NODE_NAME\""
  exit 1
fi

