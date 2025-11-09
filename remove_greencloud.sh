#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Spinner animation
spin() {
  local pid=$!
  local delay=0.1
  local spinstr='|/-\\'
  while ps -p $pid > /dev/null 2>&1; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# Step counter
step=1
total=4

step_progress() {
  echo -e "${CYAN}Step $step of $total: $1${NC}"
  ((step++))
}

# Prompt user for GreenCloud API key and login
sudo gccli logout -q > /dev/null 2>&1
echo -e "\n${CYAN}Please enter your GreenCloud API key:${NC}"
read -r API_KEY
gccli login -k "$API_KEY" > /dev/null 2>&1

# Extract and display GreenCloud Node ID
echo -e "\n${CYAN}Extracting GreenCloud Node ID...${NC}"
sudo systemctl restart gcnode
sleep 2
NODE_ID=$(sudo systemctl status gcnode | grep -oP '(?<=ID → )[a-f0-9-]+')
echo -e "${GREEN}✔ Captured Node ID: $NODE_ID${NC}"

# Removing node from GreenCloud using captured NODE_ID
echo -e "\n${CYAN}Removing node from GreenCloud...${NC}"
gccli node delete -i $NODE_ID #> /dev/null 2>&1
echo -e "${GREEN}✔ Node removed successfully!${NC}"


# Begin script
step_progress "Removing containerd..."
(sudo apt remove -y containerd) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ containerd removed${NC}"

step_progress "Removing runc..."
(sudo apt remove runc -y) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ runc removed${NC}"

step_progress "Removing GreenCloud Node and CLI..."
(
  sudo rm -r /var/lib/greencloud
  sudo rm /usr/local/bin/gccli
) & spin
echo -e "${GREEN}✔ GreenCloud node and CLI removed"

step_progress "Removing gcnode systemd service..."
(
  sudo rm /etc/systemd/system/gcnode.service
  sudo systemctl stop gcnode
  sudo systemctl daemon-reload
) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ gcnode service removed${NC}"

echo -e "\n${YELLOW}🎉 All $((step - 1)) removal steps completed successfully!${NC}"
