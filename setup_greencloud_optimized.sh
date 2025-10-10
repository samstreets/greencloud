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

step_progress "Installing containerd..."
(sudo apt install -y containerd) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ containerd installed${NC}"

step_progress "Installing runc..."
(sudo apt install runc -y) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ runc installed${NC}"

step_progress "Configuring containerd..."
(
  sudo mkdir -p /etcd
  containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
  sudo systemctl enable --now containerd
) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ containerd configured${NC}"

step_progress "Configuring ping group range (temporary)..."
(sudo sysctl -w net.ipv4.ping_group_range="0 2147483647") > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ Ping group range configured${NC}"

step_progress "Making ping group range persistent..."
(
  SYSCTL_CONF="/etc/sysctl.d/99-ping-group.conf"
  PING_RANGE="net.ipv4.ping_group_range = 0 2147483647"

  if grep -q "net.ipv4.ping_group_range" "$SYSCTL_CONF" 2>/dev/null; then
    sudo sed -i "s/^net\.ipv4\.ping_group_range.*/$PING_RANGE/" "$SYSCTL_CONF"
  else
    echo "$PING_RANGE" | sudo tee "$SYSCTL_CONF" > /dev/null
  fi

  sudo sysctl --system
) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ Ping group range made persistent${NC}"

step_progress "Detecting CPU architecture..."
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
  echo -e "${GREEN}✔ ARM architecture detected${NC}"
  GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-arm64"
  GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-arm64"
else
  echo -e "${GREEN}✔ x86_64 architecture detected${NC}"
  GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-amd64"
  GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64"
fi

step_progress "Downloading GreenCloud Node and CLI..."
(
  sudo mkdir -p /var/lib/greencloud
  wget -q "$GCNODE_URL" -O gcnode
  chmod +x gcnode && sudo mv gcnode /var/lib/greencloud/
  wget -q "$GCCLI_URL" -O gccli
  chmod +x gccli && sudo mv gccli /usr/local/bin/
) & spin
echo -e "${GREEN}✔ GreenCloud node and CLI installed for $ARCH${NC}"

step_progress "Downloading and setting up gcnode systemd service..."
(
  curl -O https://raw.githubusercontent.com/samstreets/greencloud/main/gcnode.service
  sudo mv gcnode.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable gcnode
) > /dev/null 2>&1 & spin
echo -e "${GREEN}✔ gcnode service configured${NC}"

echo -e "\n${YELLOW}🎉 All $((step - 1)) install steps completed successfully!${NC}"

# Prompt user for GreenCloud API key and login
echo -e "\n${CYAN}Please enter your GreenCloud API key:${NC}"
read -r API_KEY
gccli login -k "$API_KEY" > /dev/null 2>&1

# Prompt user for the node name
echo -e "\n${CYAN}Please enter what you would like to name the node:${NC}"
read -r NODE_NAME

# Extract and display GreenCloud Node ID
echo -e "\n${CYAN}Extracting GreenCloud Node ID...${NC}"
sudo systemctl start gcnode
sleep 10
NODE_ID=$(sudo systemctl status gcnode  | grep -oP '(?<=ID → )[a-f0-9-]+')
echo -e "${GREEN}✔ Captured Node ID: $NODE_ID${NC}"

# Add node to GreenCloud using captured NODE_ID
echo -e "\n${CYAN}Adding node to GreenCloud...${NC}"
gccli node add --external --id $NODE_ID --description $NODE_NAME > /dev/null 2>&1
echo -e "${GREEN}✔ Node added successfully!${NC}"
