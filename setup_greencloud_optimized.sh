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
total=9

step_progress() {
  echo -e "${CYAN}Step $step of $total: $1${NC}"
  ((step++))
}

# Begin script
step_progress "Updating system packages..."
(sudo apt update -y && sudo apt upgrade -y) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ System updated${NC}"

step_progress "Installing Arcade CLI..."
(curl -sLS https://get.arkade.dev | sudo sh) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ Arcade installed${NC}"

step_progress "Installing containerd via Arcade..."
(arkade get containerd && sudo mv containerd /usr/local/bin/) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ containerd installed${NC}"

step_progress "Installing runc via Arcade..."
(arkade get runc && sudo mv runc /usr/local/sbin/) > /dev/null 2>&1 & spin
runc --version
echo -e "${GREEN}✔ runc installed${NC}"

step_progress "Configuring containerd..."
(
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
  sudo systemctl enable --now containerd
) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ containerd configured${NC}"

step_progress "Configuring ping group range..."
(sudo sysctl -w net.ipv4.ping_group_range="0 2147483647") > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ Ping group range configured${NC}"

step_progress "Detecting CPU architecture and downloading GreenCloud binaries..."
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
  echo "✅ ARM architecture detected"
  GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-arm64"
  GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-arm64"
else
  echo "✅ x86_64 architecture detected"
  GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-amd64"
  GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64"
fi

(
  sudo mkdir -p /var/lib/greencloud
  wget -q "$GCNODE_URL" -O gcnode
  chmod +x gcnode && sudo mv gcnode /var/lib/greencloud/
  wget -q "$GCCLI_URL" -O gccli
  chmod +x gccli && sudo mv gccli /usr/local/bin/
) & spin
echo -e "${GREEN}✔ GreenCloud node and CLI installed for $ARCH${NC}"

step_progress "Setting up gcnode systemd service..."
(
  sudo mv gcnode.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable gcnode
) > /dev/null 2>&1 & spin
sudo systemctl status gcnode
echo -e "${GREEN}✔ gcnode service configured${NC}"

echo -e "\n${YELLOW}🎉 All $((step - 1)) steps completed successfully!${NC}"
