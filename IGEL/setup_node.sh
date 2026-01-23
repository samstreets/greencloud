
#!/usr/bin/env bash
set -euo pipefail

# =============================
# Detect architecture
# =============================
detect_arch() {
  local uname_m
  uname_m="$(uname -m)"
  case "$uname_m" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "arm" ;;
    *) echo "Unsupported architecture: $uname_m" >&2; exit 1 ;;
  esac
}
ARCH="$(detect_arch)"




CONTAINERD_VERSION="1.7.12"

INSTALL_BASE="/wfs/containerd"
BIN_DIR="$INSTALL_BASE/bin"
CONFIG_DIR="/etc/containerd"
SERVICE_FILE="/etc/systemd/system/containerd.service"

echo "=== Installing Containerd via CLI on IGEL OS ==="

# Ensure root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root"
  exit 1
fi

# Create directories
echo "Creating directories..."
mkdir -p "$BIN_DIR" "$CONFIG_DIR"

cd /tmp

echo "Downloading Containerd ${CONTAINERD_VERSION}..."
curl -fsSL \
  https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz \
  -o containerd.tar.gz

echo "Extracting Containerd..."
tar -xzf containerd.tar.gz
cp -r bin/* "$BIN_DIR"

# Symlink binaries into PATH
echo "Linking binaries..."
ln -sf "$BIN_DIR/containerd" /usr/bin/containerd
ln -sf "$BIN_DIR/ctr" /usr/bin/ctr
ln -sf "$BIN_DIR/containerd-shim" /usr/bin/containerd-shim
ln -sf "$BIN_DIR/containerd-shim-runc-v2" /usr/bin/containerd-shim-runc-v2

echo "Generating default containerd config..."
containerd config default > "$CONFIG_DIR/config.toml"

echo "Installing systemd service..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStart=/usr/bin/containerd
Restart=always
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd..."
systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

sleep 2

echo "Checking containerd status..."
systemctl is-active --quiet containerd || {
  echo "ERROR: containerd is not running"
  exit 1
}

echo "Containerd is running."

echo "=== Containerd installation complete ✅ ==="

sed -i 's/^#\? \?snapshotter *= *.*/snapshotter = "native"/' /etc/containerd/config.toml || true
# If the line doesn't exist, append it under the [containerd] section:
grep -q '^\[containerd\]' /etc/containerd/config.toml || echo '[containerd]' | sudo tee -a /etc/containerd/config.toml
grep -q '^snapshotter = "native"$' /etc/containerd/config.toml || echo 'snapshotter = "native"' | sudo tee -a /etc/containerd/config.toml

systemctl daemon-reload
systemctl restart containerd

# Stop containerd
systemctl stop containerd

# Move any existing state (if present)
mkdir -p /wfs/containerd
if [ -d /var/lib/containerd ] && [ ! -L /var/lib/containerd ]; then
  rsync -aHAX /var/lib/containerd/ /wfs/containerd/
  rm -rf /var/lib/containerd
fi

# Symlink to /wfs
ln -sf /wfs/containerd /var/lib/containerd

# Start containerd
systemctl start containerd

# Check again
which runc || {
  # Download a matching runc (example version; choose one appropriate for your containerd)
  cd /tmp
  RUNC_VER="1.1.12"
  curl -fsSLo runc.amd64 https://github.com/opencontainers/runc/releases/download/v${RUNC_VER}/runc.amd64
  install -m 755 runc.amd64 /usr/bin/runc
  runc --version
}

# Map architecture to standardized label
case "$ARCH" in
  x86_64|amd64)
    echo -e "✔ x86_64 architecture detected"
    GCNODE_URL="https://repo.emeraldcloud.co.uk/wp-content/gcnode"
    GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64"
    ;;
  aarch64|arm64)
    echo -e "✔ ARM64 architecture detected"
    GCNODE_URL="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-arm64"
    GCCLI_URL="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-arm64"
    ;;
  *)
    echo -e "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

mkdir -p /var/lib/greencloud
tmpdir="$(mktemp -d)"
trap "rm -rf \"$tmpdir\"" RETURN
curl -fsSL "$GCNODE_URL" -o "$tmpdir/gcnode"
chmod +x "$tmpdir/gcnode"
mv "$tmpdir/gcnode" /var/lib/greencloud/gcnode
mkdir -p /wfs/bin /usr/local/bin
curl -fsSL "$GCCLI_URL" -o "$tmpdir/gccli"
chmod +x "$tmpdir/gccli"
mv "$tmpdir/gccli" /wfs/bin/gccli
export PATH="$PATH:/usr/local/bin:/wfs/bin"
tmpdir="$(mktemp -d)"
trap "rm -rf \"$tmpdir\"" RETURN
curl -fsSL https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/IGEL/gcnode.service -o "$tmpdir/gcnode.service"
mv "$tmpdir/gcnode.service" /etc/systemd/system/gcnode.service
systemctl daemon-reload
systemctl enable gcnode

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
  
# --- Authentication & Node registration ---
gccli logout -q >/dev/null 2>&1 || true

echo -ne "\nPlease enter your GreenCloud API key (input hidden):"
read -rs API_KEY
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
