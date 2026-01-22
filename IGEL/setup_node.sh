
#!/bin/sh
# greencloud-cp-init-script.sh
# IGEL OS Custom Partition init/stop for GreenCloud with containerd, runc & CNI
# Runs entirely from /custom and does NOT modify the read-only base OS.

set -eu

CP_NAME="greencloud"
MP="$(get custom_partition.mountpoint 2>/dev/null || echo /custom)"
CP_DIR="${MP}/${CP_NAME}"

# Layout inside CP
BIN_DIR="${CP_DIR}/bin"                  # gccli, gcnode, ctr, containerd, runc
RUNTIME_DIR="${CP_DIR}/runtime"          # containerd state/root, sockets, etc.
CNI_DIR="${CP_DIR}/cni"                  # CNI binaries + conf
LOG_DIR="${CP_DIR}/log"
VAR_DIR="${CP_DIR}/var"                  # PID/env cache

CONTAINERD_ROOT="${RUNTIME_DIR}/root"
CONTAINERD_STATE="${RUNTIME_DIR}/state"
CONTAINERD_SOCK="${CONTAINERD_STATE}/containerd.sock"
CONTAINERD_CFG="${CP_DIR}/config/containerd.toml"
PID_FILE="${VAR_DIR}/gcnode.pid"
PID_CTRD="${VAR_DIR}/containerd.pid"
LOG_FILE="${LOG_DIR}/gcnode.log"
LOG_CTRD="${LOG_DIR}/containerd.log"
ENV_FILE="${VAR_DIR}/env"

PATH="${BIN_DIR}:${PATH}"

# ===== Parameters from UMS "Partition parameters" (recommended) =====
API_KEY="${API_KEY:-}"              # GreenCloud API key (UMS -> Partition parameters)
NODE_NAME="${NODE_NAME:-}"          # Friendly node name (UMS param)
# Optional version pins (override defaults below)
CONTAINERD_VER="${CONTAINERD_VER:-2.2.1}"   # GitHub release tag (e.g. 2.2.1)
RUNC_VER="${RUNC_VER:-1.4.0}"               # GitHub release tag (e.g. 1.4.0)
CNI_VER="${CNI_VER:-1.9.0}"                 # GitHub release tag (e.g. 1.9.0)

# ===== Detect arch and set upstream assets =====
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    CTD_TGZ="containerd-${CONTAINERD_VER}-linux-amd64.tar.gz"
    RUNC_BIN="runc.amd64"
    CNI_TGZ="cni-plugins-linux-amd64-v${CNI_VER}.tgz"
    ;;
  aarch64|arm64)
    CTD_TGZ="containerd-${CONTAINERD_VER}-linux-arm64.tar.gz"
    RUNC_BIN="runc.arm64"
    CNI_TGZ="cni-plugins-linux-arm64-v${CNI_VER}.tgz"
    ;;
  *)
    echo "Unsupported arch: $ARCH" >&2
    exit 1
    ;;
esac

# Upstream URLs (mirror these to UMS filetransfer for airgapped/ICG endpoints)
URL_CONTAINERD="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VER}/${CTD_TGZ}"
URL_RUNC="https://github.com/opencontainers/runc/releases/download/v${RUNC_VER}/${RUNC_BIN}"
URL_CNI="https://github.com/containernetworking/plugins/releases/download/v${CNI_VER}/${CNI_TGZ}"

# GreenCloud binaries
case "$ARCH" in
  x86_64|amd64)
    URL_GCNODE="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-amd64"
    URL_GCCLI="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64"
    ;;
  aarch64|arm64)
    URL_GCNODE="https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-arm64"
    URL_GCCLI="https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-arm64"
    ;;
esac

fetch() {
  # $1 URL, $2 OUT
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$1" -O "$2"
  else
    echo "Neither curl nor wget available on IGEL image." >&2
    return 1
  fi
}

wait_for_ctr() {
  # wait until containerd answers to ctr, or timeout ~30s
  for i in $(seq 1 30); do
    if CTR_CMD="ctr --address ${CONTAINERD_SOCK} version"; ${CTR_CMD} >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

link_into_rootfs() {
  # Safely expose CNI path expected by tools: /opt/cni/bin → CP CNI dir
  # IGEL CPs commonly symlink CP content into /usr,/opt as needed.  [4](https://kb.igel.com/en/igel-os/11.10/creating-the-initialization-script-1)
  if [ ! -e /opt/cni/bin ]; then
    mkdir -p /opt/cni 2>/dev/null || true
    ln -sf "${CNI_DIR}/bin" /opt/cni/bin 2>/dev/null || true
  fi
}

start_services() {
  mkdir -p "${BIN_DIR}" "${LOG_DIR}" "${VAR_DIR}" \
           "${RUNTIME_DIR}" "${CONTAINERD_ROOT}" "${CONTAINERD_STATE}" \
           "${CP_DIR}/config" "${CNI_DIR}/bin" "${CNI_DIR}/conf"

  # Record environment for troubleshooting
  {
    echo "START: $(date -Iseconds)"
    echo "ARCH=$ARCH"
    echo "API_KEY_SET=$([ -n "$API_KEY" ] && echo yes || echo no)"
    echo "NODE_NAME=${NODE_NAME:-}"
    echo "CTRD=${CONTAINERD_VER} RUNC=${RUNC_VER} CNI=${CNI_VER}"
  } > "${ENV_FILE}"

  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

  # --- Containerd ---
  if [ ! -x "${BIN_DIR}/containerd" ] || [ ! -x "${BIN_DIR}/ctr" ]; then
    fetch "${URL_CONTAINERD}" "${TMP}/containerd.tgz"
    tar -xzf "${TMP}/containerd.tgz" -C "${TMP}/"
    # tarball layout: ./bin/{containerd,ctr,...}
    install -m755 "${TMP}/bin/"* "${BIN_DIR}/"
  fi

  # --- runc ---
  if [ ! -x "${BIN_DIR}/runc" ]; then
    fetch "${URL_RUNC}" "${TMP}/runc"
    install -m755 "${TMP}/runc" "${BIN_DIR}/runc"
  fi

  # --- CNI plugins ---
  if [ ! -x "${CNI_DIR}/bin/bridge" ]; then
    fetch "${URL_CNI}" "${TMP}/cni.tgz"
    tar -xzf "${TMP}/cni.tgz" -C "${CNI_DIR}/bin"
  fi

  # Expose CNI as /opt/cni/bin for tools that expect the standard path.
  link_into_rootfs

  # Minimal containerd config referencing our local runc & CNI
  if [ ! -f "${CONTAINERD_CFG}" ]; then
    cat > "${CONTAINERD_CFG}" <<EOF
version = 2
root = "${CONTAINERD_ROOT}"
state = "${CONTAINERD_STATE}"
[grpc]
  address = "${CONTAINERD_SOCK}"
[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.9"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
    runtime_type = "io.containerd.runc.v2"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
      BinaryName = "${BIN_DIR}/runc"
  [plugins."io.containerd.grpc.v1.cri".cni]
    bin_dir = "${CNI_DIR}/bin"
    conf_dir = "${CNI_DIR}/conf"
EOF
  fi

  # Start containerd (no systemd on IGEL CP — run under nohup & PID file)
  if [ -f "${PID_CTRD}" ] && kill -0 "$(cat "${PID_CTRD}")" 2>/dev/null; then
    echo "containerd already running (PID $(cat "${PID_CTRD}"))"
  else
    nohup "${BIN_DIR}/containerd" --config "${CONTAINERD_CFG}" \
      >> "${LOG_CTRD}" 2>&1 &
    echo $! > "${PID_CTRD}"
    sleep 1
  fi

  if ! wait_for_ctr; then
    echo "ERROR: containerd failed to become ready" >&2
    exit 1
  fi

  # --- GreenCloud binaries ---
  fetch "${URL_GCNODE}" "${TMP}/gcnode"; install -m755 "${TMP}/gcnode" "${BIN_DIR}/gcnode"
  fetch "${URL_GCCLI}" "${TMP}/gccli";  install -m755 "${TMP}/gccli"  "${BIN_DIR}/gccli"

  # GreenCloud login (optional but recommended)
  if [ -n "${API_KEY}" ]; then
    "${BIN_DIR}/gccli" logout >/dev/null 2>&1 || true
    if ! "${BIN_DIR}/gccli" login -k "${API_KEY}" >/dev/null 2>&1; then
      echo "WARN: gccli login failed — continuing" >&2
    fi
  fi

  # Start gcnode (logs to CP)
  if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    echo "gcnode already running (PID $(cat "${PID_FILE}"))"
  else
    nohup "${BIN_DIR}/gcnode" >> "${LOG_FILE}" 2>&1 &
    echo $! > "${PID_FILE}"
    echo "gcnode started (PID $(cat "${PID_FILE}"))"
  fi

  # Auto-register node if we have both API_KEY & NODE_NAME
  if [ -n "${API_KEY}" ] && [ -n "${NODE_NAME}" ]; then
    NODE_ID=""
    for i in $(seq 1 30); do
      NODE_ID="$(sed -n 's#.*ID → \([a-f0-9-]\+\).*#\1#p' "${LOG_FILE}" | tail -n1 || true)"
      [ -n "${NODE_ID}" ] && break
      sleep 2
    done
    if [ -n "${NODE_ID}" ]; then
      if "${BIN_DIR}/gccli" node add --external --id "${NODE_ID}" --description "${NODE_NAME}" >/dev/null 2>&1; then
        echo "Registered Node ID ${NODE_ID} as '${NODE_NAME}'"
      else
        echo "WARN: Manual registration needed:"
        echo "      ${BIN_DIR}/gccli node add --external --id ${NODE_ID} --description '${NODE_NAME}'"
      fi
    else
      echo "WARN: Node ID not detected in ${LOG_FILE}"
    fi
  fi
}

stop_services() {
  # Stop gcnode
  if [ -f "${PID_FILE}" ]; then
    PID="$(cat "${PID_FILE}" || true)"
    [ -n "${PID}" ] && kill "${PID}" 2>/dev/null || true
    sleep 1
    [ -n "${PID}" ] && kill -9 "${PID}" 2>/dev/null || true
    rm -f "${PID_FILE}"
  fi
  # Stop containerd
  if [ -f "${PID_CTRD}" ]; then
    CPID="$(cat "${PID_CTRD}" || true)"
    [ -n "${CPID}" ] && kill "${CPID}" 2>/dev/null || true
    sleep 1
    [ -n "${CPID}" ] && kill -9 "${CPID}" 2>/dev/null || true
    rm -f "${PID_CTRD}"
  fi
}

case "${1:-}" in
  init) start_services ;;
  stop) stop_services  ;;
  *) echo "Usage: $0 {init|stop}" >&2; exit 1 ;;
esac
