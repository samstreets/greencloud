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
  local spinstr='|/-\'
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# Step counter
step=1
total=7

step_progress() {
  echo -e "${CYAN}Step $step of $total: $1${NC}"
  ((step++))
}

# Begin script
step_progress "Updating system packages..."
(sudo apt update -y && sudo apt upgrade -y) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ System updated${NC}"

step_progress "Installing containerd..."
(
  sudo apt install -y containerd
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
  sudo systemctl enable --now containerd
) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ Containerd installed${NC}"

step_progress "Installing runc..."
(
  wget -q https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64 -O runc
  sudo install -m 755 runc /usr/local/sbin/runc
) & spin
echo -e "${GREEN}✔ Runc installed${NC}"

step_progress "Configuring ping group range..."
(sudo sysctl -w net.ipv4.ping_group_range="0 2147483647") > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ Ping group range configured${NC}"

step_progress "Setting up GreenCloud node..."
(
  sudo mkdir -p /var/lib/greencloud
  wget -q https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-amd64 -O gcnode
  chmod +x gcnode
  sudo mv gcnode /var/lib/greencloud/
) & spin
echo -e "${GREEN}✔ GreenCloud node ready${NC}"

step_progress "Installing GreenCloud CLI..."
(
  wget -q https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64 -O gccli
  chmod +x gccli
  sudo mv gccli /usr/local/bin/
) & spin
echo -e "${GREEN}✔ GreenCloud CLI installed${NC}"

step_progress "Setting up gcnode systemd service..."
(
  sudo mv gcnode.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable gcnode
) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ gcnode service configured${NC}"

echo -e "\n${YELLOW}🎉 All $((step - 1)) steps completed successfully!${NC}"
