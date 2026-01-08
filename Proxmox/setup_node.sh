
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
total=8
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

# Export so the subshell sees them
export GCNODE_URL GCCLI_URL

run_step "Downloading GreenCloud Node and CLI…" bash -c '
  set -Eeuo pipefail

  mkdir -p /var/lib/greencloud

  wget "$GCNODE_URL" -O gcnode
  chmod +x gcnode
  mv gcnode /var/lib/greencloud/gcnode

  wget "$GCCLI_URL" -O gccli
  chmod +x gccli
  mv gccli /usr/bin/gccli
'


echo -e "${GREEN}✔ GreenCloud node and CLI installed for $ARCH${NC}"


run_step "Downloading and setting up gcnode systemd service…" bash -c '
  set -Eeuo pipefail

  # === Variables ===
  UNIT_NAME="gcnode.service"
  SYSTEMD_DIR="/etc/systemd/system"
  UNIT_PATH="${SYSTEMD_DIR}/${UNIT_NAME}"
  WORKDIR="/var/lib/greencloud"
  LOG_FILE="${WORKDIR}/gcnode.log"
  LOGROTATE_RULE="/etc/logrotate.d/greencloud"

  # === Fetch unit file ===
  wget -O "${UNIT_NAME}" "https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/gcnode.service"
  mv "${UNIT_NAME}" "${UNIT_PATH}"

  # === Prepare log directory and file ===
  mkdir -p "${WORKDIR}"
  touch "${LOG_FILE}"
  chown root:root "${LOG_FILE}"
  chmod 0644 "${LOG_FILE}"

  # === Ensure unit logs to file (append mode) ===
  # Insert/replace StandardOutput/StandardError inside the [Service] section
  tmp_unit="$(mktemp)"

  awk -v logfile="${LOG_FILE}" '
    BEGIN { in_service=0 }
    {
      if ($0 ~ /^\[Service\]/) { in_service=1 }
      else if ($0 ~ /^\[/ && $0 !~ /^\[Service\]/) { in_service=0 }

      # Drop existing StandardOutput/StandardError lines; we will re-add
      if (in_service && ($1 ~ /^StandardOutput=/ || $1 ~ /^StandardError=/)) { next }
      print
    }
  ' "${UNIT_PATH}" > "${tmp_unit}"

  # Add the append directives immediately after the [Service] header
  sed -i "/^\[Service\]/a StandardOutput=append:${LOG_FILE}\nStandardError=append:${LOG_FILE}" "${tmp_unit}"

  # Replace original unit atomically
  install -m 0644 "${tmp_unit}" "${UNIT_PATH}"
  rm -f "${tmp_unit}"

  # === Logrotate: daily, keep only 1 day ===
  cat > "${LOGROTATE_RULE}" <<EOF
${LOG_FILE} {
    daily
    rotate 1
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF
  chmod 0644 "${LOGROTATE_RULE}"

  # === Reload systemd and enable/start service ===
  systemctl daemon-reload
  systemctl enable gcnode
  systemctl restart gcnode

  # === Optional: force a first rotation test (comment out if not needed) ===
  # logrotate -f "${LOGROTATE_RULE}"
'

echo -e "\n${YELLOW}🎉 All $((step - 1)) install steps completed successfully!${NC}"
