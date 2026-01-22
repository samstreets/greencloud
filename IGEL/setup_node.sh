
#!/usr/bin/env bash
set -euo pipefail

# =============================
# Configurable versions
# =============================
CONTAINERD_VERSION="${CONTAINERD_VERSION:-1.7.20}"
RUNC_VERSION="${RUNC_VERSION:-1.1.12}"
CNI_VERSION="${CNI_VERSION:-1.5.1}"

# =============================
# Install/Runtime Paths (IGEL-friendly)
# =============================
BASE_DIR="/custom/container-runtime"
BIN_DIR="$BASE_DIR/bin"
ETC_DIR="$BASE_DIR/etc"
SYSTEMD_DIR="$BASE_DIR/systemd"
CNI_BIN_DIR="$BASE_DIR/cni/bin"
CNI_CONF_DIR="$BASE_DIR/cni/conf"
CONTAINERD_ROOT_DIR="$BASE_DIR/containerd-root"
CONTAINERD_STATE_DIR="$BASE_DIR/containerd-state"

# Optional symlink targets (if writable)
USR_LOCAL_BIN="/usr/local/bin"
OPT_CNI_BIN="/opt/cni/bin"

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

# =============================
# Ensure directories
# =============================
mkdir -p "$BIN_DIR" "$ETC_DIR" "$SYSTEMD_DIR" "$CNI_BIN_DIR" "$CNI_CONF_DIR" \
         "$CONTAINERD_ROOT_DIR" "$CONTAINERD_STATE_DIR"

# =============================
# Helper: download file
# =============================
fetch() {
  local url="$1" out="$2"
  echo "Downloading: $url"
  curl -fsSL --retry 3 --retry-delay 2 -o "$out" "$url"
}

# =============================
# Download binaries
# =============================

# containerd
CONTAINERD_TGZ="containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz"
CONTAINERD_URL="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/${CONTAINERD_TGZ}"

# runc
RUNC_URL="https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH}"

# CNI plugins
CNI_TGZ="cni-plugins-linux-${ARCH}-v${CNI_VERSION}.tgz"
CNI_URL="https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/${CNI_TGZ}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fetch "$CONTAINERD_URL" "$TMP_DIR/$CONTAINERD_TGZ"
fetch "$RUNC_URL" "$TMP_DIR/runc"
fetch "$CNI_URL" "$TMP_DIR/$CNI_TGZ"

# =============================
# Install containerd + ctr + containerd-shim*
# =============================
echo "Installing containerd..."
tar -xzf "$TMP_DIR/$CONTAINERD_TGZ" -C "$TMP_DIR"
# Tar contains bin/{containerd,containerd-shim*,ctr}
install -m 0755 "$TMP_DIR/bin/containerd" "$BIN_DIR/containerd"
install -m 0755 "$TMP_DIR/bin/ctr" "$BIN_DIR/ctr"
# Install all shims if present
if compgen -G "$TMP_DIR/bin/containerd-shim*" > /dev/null; then
  install -m 0755 "$TMP_DIR"/bin/containerd-shim* "$BIN_DIR/"
fi

# =============================
# Install runc
# =============================
echo "Installing runc..."
install -m 0755 "$TMP_DIR/runc" "$BIN_DIR/runc"

# =============================
# Install CNI plugins
# =============================
echo "Installing CNI plugins..."
mkdir -p "$CNI_BIN_DIR"
tar -xzf "$TMP_DIR/$CNI_TGZ" -C "$CNI_BIN_DIR"

# Try to mirror CNI plugins to /opt/cni/bin if writable (helpful for tooling)
if mkdir -p "$OPT_CNI_BIN" 2>/dev/null && [ -w "$OPT_CNI_BIN" ]; then
  echo "Mirroring CNI plugins to $OPT_CNI_BIN..."
  cp -f "$CNI_BIN_DIR"/* "$OPT_CNI_BIN"/
fi

# Try to symlink tools into /usr/local/bin for convenience
if mkdir -p "$USR_LOCAL_BIN" 2>/dev/null && [ -w "$USR_LOCAL_BIN" ]; then
  for b in containerd ctr runc; do
    ln -sf "$BIN_DIR/$b" "$USR_LOCAL_BIN/$b"
  done
fi

# =============================
# Generate containerd config
# =============================
echo "Generating containerd config..."
mkdir -p "$ETC_DIR/containerd"
# -- NOTE: We keep everything in /custom, and point containerd accordingly
"$BIN_DIR/containerd" config default > "$ETC_DIR/containerd/config.toml"

# Patch config.toml:
# - Use systemd cgroups
# - Point to persistent root & state
# - Point CNI dirs to our /custom paths
# - Enable CRI plugin if needed (default is true)
sed -i \
  -e 's#\(root = \).*#\1"'"$CONTAINERD_ROOT_DIR"'"#' \
  -e 's#\(state = \).*#\1"'"$CONTAINERD_STATE_DIR"'"#' \
  "$ETC_DIR/containerd/config.toml"

# Ensure SystemdCgroup = true under [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
awk '
  BEGIN {in_runc=0; in_opts=0}
  /plugins\."io\.containerd\.grpc\.v1\.cri"\.containerd\.runtimes\.runc/ {in_runc=1}
  in_runc && /^\[/ && $0 !~ /runtimes\.runc/ {in_runc=0}
  in_runc && /\.options\]/ {in_opts=1}
  in_opts && /^\[/ {in_opts=0}
  {print}
  in_opts && $0 ~ /{/ && !printed {print "            SystemdCgroup = true"; printed=1}
' "$ETC_DIR/containerd/config.toml" > "$ETC_DIR/containerd/config.toml.tmp" && mv "$ETC_DIR/containerd/config.toml.tmp" "$ETC_DIR/containerd/config.toml"

# CNI settings (add if missing)
if ! grep -q '\[plugins."io.containerd.grpc.v1.cri".cni\]' "$ETC_DIR/containerd/config.toml"; then
cat >> "$ETC_DIR/containerd/config.toml" <<'EOF'

[plugins."io.containerd.grpc.v1.cri".cni]
  bin_dir = ""
  conf_dir = ""
EOF
fi

# Set our custom CNI paths
sed -i \
  -e 's#\(bin_dir = \).*#\1"'"$CNI_BIN_DIR"'"#' \
  -e 's#\(conf_dir = \).*#\1"'"$CNI_CONF_DIR"'"#' \
  "$ETC_DIR/containerd/config.toml"

# Minimal CNI bridge config if none exists
if [ -z "$(ls -A "$CNI_CONF_DIR" 2>/dev/null || true)" ]; then
cat > "$CNI_CONF_DIR/10-bridge.conf" <<'EOF'
{
  "cniVersion": "1.0.1",
  "name": "igel0",
  "type": "bridge",
  "bridge": "cni0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "routes": [ { "dst": "0.0.0.0/0" } ],
    "ranges": [ [ { "subnet": "10.88.0.0/16" } ] ]
  }
}
EOF
fi

# =============================
# systemd unit for containerd
# =============================
CONTAINERD_SERVICE="$SYSTEMD_DIR/containerd.service"
cat > "$CONTAINERD_SERVICE" <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
# Point containerd at our config and paths under /custom
Environment=CONTAINERD_CONFIG=$ETC_DIR/containerd/config.toml
ExecStart=$BIN_DIR/containerd --config \$CONTAINERD_CONFIG
KillMode=process
Delegate=yes
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

echo "Linking and enabling containerd.service..."
systemctl daemon-reload
# systemctl link lets us keep the unit outside /etc/systemd/system
systemctl link "$CONTAINERD_SERVICE"
systemctl enable containerd.service
systemctl restart containerd.service

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
  

# Map architecture to standardized label
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

set -Eeuo pipefail
  mkdir -p /var/lib/greencloud
  tmpdir="$(mktemp -d)"
  trap "rm -rf \"$tmpdir\"" RETURN
  curl -fsSL "$GCNODE_URL" -o "$tmpdir/gcnode"
  chmod +x "$tmpdir/gcnode"
  mv "$tmpdir/gcnode" /var/lib/greencloud/gcnode
  curl -fsSL "$GCCLI_URL" -o "$tmpdir/gccli"
  chmod +x "$tmpdir/gccli"
  mv "$tmpdir/gccli" /usr/local/bin/gccli
  set -Eeuo pipefail
  tmpdir="$(mktemp -d)"
  trap "rm -rf \"$tmpdir\"" RETURN
  curl -fsSL https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/Ubuntu/gcnode.service -o "$tmpdir/gcnode.service"
  mv "$tmpdir/gcnode.service" /etc/systemd/system/gcnode.service
  systemctl daemon-reload
  systemctl enable gcnode
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
