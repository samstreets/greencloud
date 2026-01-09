
#!/bin/bash
set -euo pipefail
set -o pipefail

# ========= Settings (override via environment) =========
VMID=${VMID:-9000}
NODE=${NODE:-$(hostname)}
ROOTFS_STORAGE=${ROOTFS_STORAGE:-local-lvm}
VZTMPL_STORAGE=${VZTMPL_STORAGE:-local}
BACKUP_STORAGE=${BACKUP_STORAGE:-local}

HOSTNAME=${HOSTNAME:-greencloud-node-template}
CPU_CORES=${CPU_CORES:-2}
MEMORY_MB=${MEMORY_MB:-2048}
ROOTFS_GB=${ROOTFS_GB:-8}

OS_NAME=debian-13
APP_NAME=greencloud
VERSION_TAG=${VERSION_TAG:-1.0}
ARCH=amd64

# ========= Functions =========

wait_for_ct() {
  echo "[INFO] Waiting for container $VMID to be fully ready..."

  for i in {1..30}; do
    if pct exec "$VMID" -- ping -c1 1.1.1.1 >/dev/null 2>&1; then
      echo "[INFO] Networking online."
      return 0
    fi
    sleep 2
  done

  echo "[ERROR] Container networking failed to come online!"
  exit 1
}

safe_exec() {
  if ! pct exec "$VMID" -- bash -lc "$1"; then
    echo "[ERROR] Command failed inside CT:"
    echo "        $1"
    exit 1
  fi
}

# ========= Ensure Debian 13 LXC template exists =========

echo "[INFO] Checking for Debian 13 LXC template..."

if ! ls /var/lib/vz/template/cache/debian-13-standard_13.*_amd64.tar.zst >/dev/null 2>&1; then
  echo "[INFO] Downloading Debian 13 template..."
  pveam update
  pveam download local debian-13-standard_13.*_amd64.tar.zst
fi

BASE_TEMPLATE=$(ls /var/lib/vz/template/cache/debian-13-standard_13.*_amd64.tar.zst | head -n 1)
echo "[INFO] Using base template: $BASE_TEMPLATE"

# ========= Create privileged container =========

echo "[INFO] Creating LXC container $VMID..."

pct create "$VMID" "$BASE_TEMPLATE" \
  -hostname "$HOSTNAME" \
  -storage "$ROOTFS_STORAGE" \
  -cores "$CPU_CORES" \
  -memory "$MEMORY_MB" \
  -rootfs "$ROOTFS_STORAGE:$ROOTFS_GB" \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged 0 \
  -features nesting=1,keyctl=1,fuse=1

# ========= Apply low-level LXC config options =========

echo "[INFO] Applying LXC config hardening exceptions..."

CONF_FILE="/etc/pve/lxc/${VMID}.conf"

{
  echo ""
  echo "# ==== GreenCloud runtime permissions ===="
  echo "lxc.cap.drop:"
  echo "lxc.apparmor.profile: unconfined"
  echo "lxc.cgroup2.devices.allow: a"
  echo "lxc.mount.auto: proc:rw sys:rw"
  echo "lxc.mount.entry: /dev/fuse dev/fuse none bind,create=file 0 0"
} >> "$CONF_FILE"

echo "[INFO] Updated $CONF_FILE:"
cat "$CONF_FILE"

# ========= Start the container =========

pct start "$VMID"
wait_for_ct

# ========= Execute setup_node.sh =========

echo "[INFO] Running setup_node.sh (this will block until it completes)..."

safe_exec 'wget -qO- https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/setup_node.sh | bash -s --'

echo "[INFO] setup_node.sh completed successfully."

# ========= Place configure_node.sh =========

echo "[INFO] Placing configure_node.sh into /root..."

safe_exec 'wget -qO /root/configure_node.sh https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/configure_node.sh'
safe_exec 'chmod +x /root/configure_node.sh'

# ========= Slim down image =========
echo "[INFO] Cleaning container filesystem..."

safe_exec '
  set -e

  # Clean apt cache safely
  apt-get clean || true

  # Clean apt lists (but keep the directory)
  if [ -d /var/lib/apt/lists ]; then
      find /var/lib/apt/lists -mindepth 1 -type f -delete || true
  fi

  # Clean /var/tmp
  if [ -d /var/tmp ]; then
      find /var/tmp -mindepth 1 -delete || true
  fi

  # CLEAN /tmp SAFELY — do NOT touch overlay mounts
  if [ -d /tmp ]; then
      find /tmp -mindepth 1 \
         -not -path "/tmp/ovl" \
         -not -path "/tmp/ovl/*" \
         -delete || true
  fi
'
# ========= Shutdown container safely =========
echo "[INFO] Shutting down container..."
pct shutdown "$VMID" || true

for i in {1..10}; do
  if pct status "$VMID" | grep -q "stopped"; then
    break
  fi
  sleep 1
done

# ========= Convert to template =========
echo "[INFO] Converting CT into Proxmox template..."
pct template "$VMID"

# ========= vzdump backup =========

echo "[INFO] Creating vzdump backup in storage '$BACKUP_STORAGE'..."
vzdump "$VMID" --node "$NODE" --mode stop --compress zstd --storage "$BACKUP_STORAGE"

# ========= Export CT filesystem as template tarball =========

echo "[INFO] Exporting CT template to '$VZTMPL_STORAGE'..."

VZTMPL_PATH=$(pvesm path "$VZTMPL_STORAGE":vztmpl)
mkdir -p "$VZTMPL_PATH"

EXPORT_NAME="${APP_NAME}-${OS_NAME}_${VERSION_TAG}_${ARCH}.tar.zst"
EXPORT_PATH="${VZTMPL_PATH%/}/$EXPORT_NAME"

echo "[INFO] Temporarily converting back to standard CT for filesystem access..."
pct untemplate "$VMID"
pct start "$VMID"
sleep 3

ROOTFS_HOST_PATH="/var/lib/lxc/${VMID}/rootfs"

if [[ -d "$ROOTFS_HOST_PATH" ]]; then
  echo "[INFO] Packing rootfs to $EXPORT_PATH..."
  tar --numeric-owner --xattrs --xattrs-include='*' \
      --one-file-system \
      --exclude=proc/* --exclude=sys/* --exclude=dev/* \
      --exclude=run/* --exclude=mnt/* --exclude=media/* \
      -C "$ROOTFS_HOST_PATH" -cf - . | zstd -19 -T0 > "$EXPORT_PATH"
  echo "[INFO] Template archive created: $EXPORT_PATH"
else
  echo "[ERROR] Rootfs missing: $ROOTFS_HOST_PATH"
fi

# ========= Re-template =========
echo "[INFO] Re-marking CT as template..."
pct shutdown "$VMID" || true
pct template "$VMID"

echo
echo "========================================"
echo "[SUCCESS] Template Build Completed"
echo "CT $VMID is ready for cloning."
echo "Backup stored in:    $BACKUP_STORAGE"
echo "Template archive in: $VZTMPL_STORAGE ($EXPORT_NAME)"
echo "========================================"
echo
