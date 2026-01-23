
#!/usr/bin/env bash
set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────
# Globals & Configuration
# ─────────────────────────────────────────────────────────────
CONTAINERD_VERSION="2.2.1"
RUNC_VERSION="1.1.12"

INSTALL_BASE="/wfs/containerd"
BIN_DIR="${INSTALL_BASE}/bin"
CONFIG_DIR="/etc/containerd"
SERVICE_FILE="/etc/systemd/system/containerd.service"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

export DEBIAN_FRONTEND=noninteractive

# ─────────────────────────────────────────────────────────────
# Error handling
# ─────────────────────────────────────────────────────────────
trap 'echo -e "\n${YELLOW}✖ Error on line ${LINENO}. Aborting.${NC}" >&2' ERR

# ─────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────
die() {
  echo -e "${YELLOW}ERROR:${NC} $*" >&2
  exit 1
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "Run as root"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "arm" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

spin() {
  local pid="$1"
  local spin='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    for c in ${spin}; do
      printf " [%c]  " "$c"
      sleep 0.1
      printf "\b\b\b\b\b\b"
    done
  done
}

STEP=1
TOTAL=9
run_step() {
  local title="$1"; shift
  echo -e "${CYAN}Step ${STEP}/${TOTAL}: ${title}${NC}"
  ((STEP++))

  (
    set -Eeuo pipefail
    "$@"
  ) &>/dev/null &

  local pid=$!
  spin "$pid"

  wait "$pid" \
    && echo -e "${GREEN}✔ ${title} completed${NC}" \
    || die "${title} failed"
}

mktempdir() {
  local d
  d="$(mktemp -d)"
  trap "rm -rf '${d}'" RETURN
  echo "$d"
}

# ─────────────────────────────────────────────────────────────
# Begin installation
# ─────────────────────────────────────────────────────────────
require_root
ARCH="$(detect_arch)"

run_step "Creating directories" mkdir -p "${BIN_DIR}" "${CONFIG_DIR}"

run_step "Downloading containerd" \
  curl -fsSL \
  "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz" \
  -o /tmp/containerd.tgz

run_step "Installing containerd" bash -c '
  tar -xzf /tmp/containerd.tgz -C /tmp
  cp -r /tmp/bin/* "'"${BIN_DIR}"'"
  ln -sf "'"${BIN_DIR}"'/containerd" /usr/bin/containerd
  ln -sf "'"${BIN_DIR}"'/ctr" /usr/bin/ctr
  ln -sf "'"${BIN_DIR}"'/containerd-shim"* /usr/bin/
'

run_step "Configuring containerd" bash -c '
  containerd config default > "'"${CONFIG_DIR}"'/config.toml"

  cat > "'"${SERVICE_FILE}"'" <<EOF
[Unit]
Description=containerd container runtime
After=network.target

[Service]
ExecStart=/usr/bin/containerd
Restart=always
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now containerd
'

run_step "Persist containerd state to /wfs" bash -c '
  systemctl stop containerd

  mkdir -p /wfs/containerd
  if [[ -d /var/lib/containerd && ! -L /var/lib/containerd ]]; then
    rsync -aHAX /var/lib/containerd/ /wfs/containerd/
    rm -rf /var/lib/containerd
  fi

  ln -sf /wfs/containerd /var/lib/containerd
  systemctl start containerd
'

run_step "Installing runc" bash -c '
  command -v runc && exit 0

  curl -fsSL \
    "https://github.com/opencontainers/runc/releases/download/v'"${RUNC_VERSION}"'/runc.'"${ARCH}"'" \
    -o /usr/bin/runc

  chmod +x /usr/bin/runc
'

# ─────────────────────────────────────────────────────────────
# GreenCloud binaries
# ─────────────────────────────────────────────────────────────
case "$ARCH" in
  amd64)
    GCNODE_URL="https://repo.emeraldcloud.co.uk/wp-content/gcnode"
    GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64"
    ;;
  arm64)
    GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-arm64"
    GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-arm64"
    ;;
  *) die "Unsupported GreenCloud arch" ;;
esac

run_step "Installing GreenCloud binaries" bash -c '
  mkdir -p /var/lib/greencloud /wfs/bin

  curl -fsSL "'"${GCNODE_URL}"'" -o /var/lib/greencloud/gcnode
  chmod +x /var/lib/greencloud/gcnode

  curl -fsSL "'"${GCCLI_URL}"'" -o /wfs/bin/gccli
  chmod +x /wfs/bin/gccli
  export PATH="$PATH:/usr/local/bin:/wfs/bin"
'

run_step "Installing gcnode systemd service" bash -c '
  curl -fsSL \
    https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/IGEL/gcnode.service \
    -o /etc/systemd/system/gcnode.service

  systemctl daemon-reload
  systemctl enable gcnode
'

run_step "Configuring ping_group_range" bash -c '
  conf=/etc/sysctl.d/99-ping-group.conf
  echo "net.ipv4.ping_group_range = 0 2147483647" > "$conf"
  [[ -e /proc/sys/net/ipv4/ping_group_range ]] \
    && echo "0 2147483647" > /proc/sys/net/ipv4/ping_group_range
'

# ─────────────────────────────────────────────────────────────
# Authentication & Node registration
# ─────────────────────────────────────────────────────────────
gccli logout -q >/dev/null 2>&1 || true

read -rsp "Enter GreenCloud API key: " API_KEY; echo
echo
if ! gccli login -k "$API_KEY"  >/dev/null 2>&1; then
  echo -e "Login failed. Please check your API key."
  exit 1
fi
echo -ne "\nPlease enter what you would like to name the node:"
read -r NODE_NAME

echo -e "\nStarting gcnode and extracting Node ID…"
systemctl start gcnode
# Wait for Node ID in logs
NODE_ID=""
attempts=0
max_attempts=30
sleep 2
while [ -z "$NODE_ID" ] && [ "$attempts" -lt "$max_attempts" ]; do
  NODE_ID="$(journalctl -u gcnode --no-pager -n 200 | sed -n "s/.*ID → \([a-f0-9-]\+\).*/\1/p" | tail -1)"
  if [ -z "$NODE_ID" ]; then
    echo -e "Waiting for Node ID... (${attempts}/${max_attempts})"
    sleep 2
    attempts=$((attempts+1))
  fi
done


echo -e "✔ Captured Node ID: $NODE_ID"

echo -e "\nAdding node to GreenCloud..."
if gccli node add --external --id "$NODE_ID" --description "$NODE_NAME" >/dev/null 2>&1; then
  echo -e "✔ Node added successfully!"
else
  echo -e "Failed to add node via gccli. Please retry manually:"
  echo "gccli node add --external --id $NODE_ID --description \"$NODE_NAME\""
  exit 1
fi
