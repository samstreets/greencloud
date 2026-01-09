
#!/bin/bash
set -euo pipefail

# Enable fail for multi-stage pipelines
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
  -features nesting=1,keyctl=1

# ========= Apply low-level LXC options required by your workload =========
echo "[INFO] Applying LXC config hardening exceptions for container runtimes..."

# Optional but recommended for fuse-based tools
pct set "$VMID" -features fuse=1 || true

# Allow all kernel capabilities (drop none)
pct set "$VMID" -lxc 'lxc.cap.drop='

# Disable AppArmor confinement
pct set "$VMID" -lxc 'lxc.apparmor.profile=unconfined'

# Allow all device access (required by containerd/docker-in-LXC patterns)
pct set "$VMID" -lxc 'lxc.cgroup2.devices.allow=a'

# Allow sys and proc mounts
pct set "$VMID" -lxc 'lxc.mount.auto=proc:rw sys:rw'

# Allow fuse device (bind-mount)
pct set "$VMID" -lxc 'lxc.mount.entry=/dev/fuse dev/fuse none bind,create=file 0 0'

# Show resulting config (debug)
echo "[INFO] /etc/pve/lxc/$VMID.conf after updates:"
cat "/etc/pve/lxc/${VMID}.conf" || true

pct start "$VMID"
echo "[INFO] Waiting for container boot..."
sleep 6

# ========= Run your setup and wait for it to finish =========
echo "[INFO] Running setup_node.sh (this will block until it completes)..."
pct exec "$VMID" -- bash -lc '
  set -euo pipefail
  wget -qO- https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/setup_node.sh | bash -s --
'
echo "[INFO] setup_node.sh completed successfully."

# ========= Place configure_node.sh into /root (executable) =========
echo "[INFO] Placing configure_node.sh into /root (executable)..."
pct exec "$VMID" -- bash -lc '
  set -euo pipefail
  wget -qO /root/configure_node.sh https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/configure_node.sh
  chmod +x /root/configure_node.sh
'

# ========= Slim down image =========
pct exec "$VMID" -- bash -lc \
  "apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"

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

# ========= Export CT template archive =========
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
if [[ ! -d "$ROOTFS_HOST_PATH" ]]; then
  echo "[ERROR] Rootfs path missing: $ROOTFS_HOST_PATH"
  echo "[ERROR] Skipping archive export"
else
  echo "[INFO] Packing rootfs to $EXPORT_PATH..."
  tar --numeric-owner --xattrs --xattrs-include='*' \
      --one-file-system \
      --exclude=proc/* --exclude=sys/* --exclude=dev/* \
      --exclude=run/* --exclude=mnt/* --exclude=media/* \
      -C "$ROOTFS_HOST_PATH" -cf - . | zstd -19 -T0 > "$EXPORT_PATH"

  echo "[INFO] Template archive created: $EXPORT_PATH"
fi

# ========= Re-template =========
echo "[INFO] Re-marking CT as template..."
pct shutdown "$VMID" || true
pct template "$VMID"

echo
echo "========================================"
echo "[SUCCESS] Template Build Completed"
echo "CT $VMID is a cloneable Proxmox Template."
echo "Backup stored in:    $BACKUP_STORAGE (Backups menu)"
echo "Template archive in: $VZTMPL_STORAGE (CT Templates → $EXPORT_NAME)"
echo "========================================"
echo
``
