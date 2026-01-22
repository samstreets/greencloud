
#!/usr/bin/env bash
set -euo pipefail

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

run_step "Downlaoding Containerd" fetch "$CONTAINERD_URL" "$TMP_DIR/$CONTAINERD_TGZ"
run_step "Downlaoding Runc" fetch "$RUNC_URL" "$TMP_DIR/runc"
run_step "Downlaoding Containerd Networking" fetch "$CNI_URL" "$TMP_DIR/$CNI_TGZ"

# =============================
# Install containerd + ctr + containerd-shim*
# =============================
run_step "Installing containerd..." bash -c '
tar -xzf "$TMP_DIR/$CONTAINERD_TGZ" -C "$TMP_DIR"
# Tar contains bin/{containerd,containerd-shim*,ctr}
install -m 0755 "$TMP_DIR/bin/containerd" "$BIN_DIR/containerd"
install -m 0755 "$TMP_DIR/bin/ctr" "$BIN_DIR/ctr"
# Install all shims if present
if compgen -G "$TMP_DIR/bin/containerd-shim*" > /dev/null; then
  install -m 0755 "$TMP_DIR"/bin/containerd-shim* "$BIN_DIR/"
fi
'

# =============================
# Install runc
# =============================
run_step "Installing runc..." bash -c '
install -m 0755 "$TMP_DIR/runc" "$BIN_DIR/runc"
'
# =============================
# Install CNI plugins
# =============================
run_step "Installing CNI plugins..." bash -c '
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
'
# =============================
# Generate containerd config
# =============================
run_step "Generating containerd config..." bash -c '
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
'
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

run_step "Linking and enabling containerd.service..." bash -c '
systemctl daemon-reload
# systemctl link lets us keep the unit outside /etc/systemd/system
systemctl link "$CONTAINERD_SERVICE"
systemctl enable containerd.service
systemctl restart containerd.service
'

echo "Installation complete!"
echo
echo "Binaries:        $BIN_DIR (linked to $USR_LOCAL_BIN if possible)"
echo "containerd root: $CONTAINERD_ROOT_DIR"
echo "containerd state:$CONTAINERD_STATE_DIR"
echo "CNI bin:         $CNI_BIN_DIR (mirrored to $OPT_CNI_BIN if possible)"
echo "CNI conf:        $CNI_CONF_DIR"
echo
echo "Try:   $BIN_DIR/ctr version"
echo "Check: systemctl status containerd --no-pager"
``
