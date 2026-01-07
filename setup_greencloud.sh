
#!/usr/bin/env bash
set -Eeuo pipefail

# --- Error reporting ---
trap 'echo -e "\n\033[1;31m✖ Error on line $LINENO. Aborting.\033[0m" >&2' ERR

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
  ((step++))
}

# Run a step with spinner and hard failure on non-zero exit
run_step() {
  local title="$1"
  shift
  step_progress "$title"
  (
    set -Eeuo pipefail
    "$@"
  ) >/dev/null 2>&1 &
  local pid=$!
  spin "$pid"
  if wait "$pid"; then
    echo -e "${GREEN}✔ ${title/…/} completed${NC}"
  else
    echo -e "${YELLOW}⚠ ${title/…/} failed${NC}"
    exit 1
  fi
}

export DEBIAN_FRONTEND=noninteractive

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

#run_step "Making ping group range persistent…" bash -c '
#  set -euo pipefail

#  SYSCTL_CONF="/etc/sysctl.d/99-ping-group.conf"
#  PING_RANGE_LINE="net.ipv4.ping_group_range = 0 2147483647"
#  PROC_NODE="/proc/sys/net/ipv4/ping_group_range"

  # 1) Persist the setting
  #mkdir -p /etc/sysctl.d
  #if [ -f "$SYSCTL_CONF" ] && grep -q "^net\.ipv4\.ping_group_range" "$SYSCTL_CONF"; then
  #  sed -i "s/^net\.ipv4\.ping_group_range.*/$PING_RANGE_LINE/" "$SYSCTL_CONF"
  #else
  #  printf "%s\n" "$PING_RANGE_LINE" > "$SYSCTL_CONF"
  #fi

  # 2) Apply immediately without relying on sysctl --system
  #if [ -e "$PROC_NODE" ]; then
    # Write the two numbers directly into /proc node
  #  echo "0 2147483647" > "$PROC_NODE"
  #else
  #  echo "WARNING: $PROC_NODE does not exist. Your kernel may not support ping_group_range." >&2
  #  exit 0
  #fi

  # 3) Verify
  #CURRENT=$(cat "$PROC_NODE")
  #echo "Applied: net.ipv4.ping_group_range = $CURRENT"

  #apt install procps
  #SYSCTL_CONF="/etc/sysctl.d/99-ping-group.conf"
  #PING_RANGE="net.ipv4.ping_group_range = 0 2147483647"
 # if [ -f "$SYSCTL_CONF" ] && grep -q "^net\.ipv4\.ping_group_range" "$SYSCTL_CONF"; then
#    sed -i "s/^net\.ipv4\.ping_group_range.*/$PING_RANGE/" "$SYSCTL_CONF"
#  else
#    echo "$PING_RANGE" | tee "$SYSCTL_CONF" >/dev/null
#  fi
#  sysctl --system
'

# Architecture detection
step_progress "Detecting CPU architecture…"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    echo -e "${GREEN}✔ x86_64 architecture detected${NC}"
    GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-amd64"
    GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64"
    ;;
  aarch64|arm64)
    echo -e "${GREEN}✔ ARM64 architecture detected${NC}"
    GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-arm64"
    GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-arm64"
    ;;
  *)
    echo -e "${YELLOW}Unsupported architecture: $ARCH${NC}"
    exit 1
    ;;
esac

run_step "Downloading GreenCloud Node and CLI…" bash -c '
  set -Eeuo pipefail
  mkdir -p /var/lib/greencloud
  tmpdir="$(mktemp -d)"
  trap "rm -rf \"$tmpdir\"" RETURN
  wget -fsSL "'"$GCNODE_URL"'" -o "$tmpdir/gcnode"
  chmod +x "$tmpdir/gcnode"
  mv "$tmpdir/gcnode" /var/lib/greencloud/gcnode
  wget -fsSL "'"$GCCLI_URL"'" -o "$tmpdir/gccli"
  chmod +x "$tmpdir/gccli"
  mv "$tmpdir/gccli" /usr/local/bin/gccli
'
echo -e "${GREEN}✔ GreenCloud node and CLI installed for $ARCH${NC}"

run_step "Downloading and setting up gcnode systemd service…" bash -c '
  set -Eeuo pipefail
  tmpdir="$(mktemp -d)"
  trap "rm -rf \"$tmpdir\"" RETURN
  wget https://raw.githubusercontent.com/samstreets/greencloud/main/gcnode.service -o "$tmpdir/gcnode.service"
  mv "$tmpdir/gcnode.service" /etc/systemd/system/gcnode.service
  systemctl daemon-reload
  systemctl enable gcnode
'

echo -e "\n${YELLOW}🎉 All $((step - 1)) install steps completed successfully!${NC}"

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
