
#!/bin/bash
set -euo pipefail

# ========= Settings (override via environment) =========
VMID=${VMID:-9000}                          # CT ID to create
NODE=${NODE:-$(hostname)}                   # PVE node name
ROOTFS_STORAGE=${ROOTFS_STORAGE:-local-lvm} # Storage for rootfs (thin/thick)
VZTMPL_STORAGE=${VZTMPL_STORAGE:-local}     # Storage with 'vztmpl' content enabled
BACKUP_STORAGE=${BACKUP_STORAGE:-local}     # Storage with 'backup' content enabled
HOSTNAME=${HOSTNAME:-greencloud-node-template}
CPU_CORES=${CPU_CORES:-2}
MEMORY_MB=${MEMORY_MB:-2048}
ROOTFS_GB=${ROOTFS_GB:-8}

# Export naming
OS_NAME=debian-13
APP_NAME=greencloud
VERSION_TAG=${VERSION_TAG:-1.0}
ARCH=amd64

# ========= Ensure Debian 13 base template exists =========
if ! ls /var/lib/vz/template/cache/debian-13-standard_13.*_amd64.tar.zst >/dev/null 2>&1; then
  echo "[INFO] Downloading Debian 13 LXC template to 'local' storage..."
  pveam update
  pveam download local debian-13-standard_13.*_amd64.tar.zst
fi

BASE_TEMPLATE=$(ls /var/lib/vz/template/cache/debian-13-standard_13.*_amd64.tar.zst | head -n 1)
echo "[INFO] Using base CT template: $BASE_TEMPLATE"

# ========= Create privileged container with DHCP =========
pct create "$VMID" "$BASE_TEMPLATE" \
  -hostname "$HOSTNAME" \
  -storage "$ROOTFS_STORAGE" \
  -cores "$CPU_CORES" \
  -memory "$MEMORY_MB" \
  -rootfs "$ROOTFS_STORAGE:$ROOTFS_GB" \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged 0 \
  -features nesting=1

# Optional: set DNS explicitly (uncomment if needed)
# pct set "$VMID" -nameserver 1.1.1.1

pct start "$VMID"
echo "[INFO] Waiting for container to come up..."
sleep 6

# ========= Run your setup and place configure script =========
echo "[INFO] Running setup_node.sh..."
pct exec "$VMID" -- bash -lc \
  "curl -fsSL https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/setup_node.sh | bash"

echo "[INFO] Placing configure_node.sh into /root (executable)..."
pct exec "$VMID" -- bash -lc \
  "curl -fsSL -o /root/configure_node.sh https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/configure_node.sh && chmod +x /root/configure_node.sh"

# ========= Slim down image (optional) =========
pct exec "$VMID" -- bash -lc "apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"

# ========= Convert to template (cloneable in CT list) =========
echo "[INFO] Shutting down..."
pct shutdown "$VMID"
echo "[INFO] Converting to template..."
pct template "$VMID"

# ========= Create vzdump backup (downloadable) =========
echo "[INFO] Creating vzdump backup to storage '$BACKUP_STORAGE'..."
vzdump "$VMID" --node "$NODE" --mode stop --compress zstd --storage "$BACKUP_STORAGE"

# ========= Export a CT template archive to 'vztmpl' =========
echo "[INFO] Exporting CT template archive to storage '$VZTMPL_STORAGE' (CT Templates)..."
VZTMPL_PATH=$(pvesm path "$VZTMPL_STORAGE":vztmpl)
mkdir -p "$VZTMPL_PATH"

EXPORT_NAME="${APP_NAME}-${OS_NAME}_${VERSION_TAG}_${ARCH}.tar.zst"
EXPORT_PATH="${VZTMPL_PATH%/}/$EXPORT_NAME"

# Temporarily un-template to access rootfs, start, pack, then re-template
echo "[INFO] Temporarily converting template back to normal CT for packing..."
pct untemplate "$VMID"
pct start "$VMID"
sleep 3

ROOTFS_HOST_PATH="/var/lib/lxc/${VMID}/rootfs"
if [ ! -d "$ROOTFS_HOST_PATH" ]; then
  echo "[ERROR] Could not find rootfs at $ROOTFS_HOST_PATH"
  echo "Skipping CT template archive export."
  pct shutdown "$VMID" || true
else
  echo "[INFO] Packing rootfs from $ROOTFS_HOST_PATH to $EXPORT_PATH ..."
  tar --numeric-owner --xattrs --xattrs-include='*' \
      --one-file-system \
      --exclude=proc/* --exclude=sys/* --exclude=dev/* --exclude=run/* \
      --exclude=mnt/* --exclude=media/* \
      -C "$ROOTFS_HOST_PATH" -cf - . | zstd -19 -T0 > "$EXPORT_PATH"
  echo "[INFO] CT template archive created: $EXPORT_PATH"
fi

echo "[INFO] Re-templating the container..."
pct shutdown "$VMID"
pct template "$VMID"

echo "[SUCCESS] Done.
- CT ${VMID} marked as TEMPLATE (cloneable from CT list).
- vzdump backup created on storage '${BACKUP_STORAGE}' (downloadable under Storage → Backups).
- CT template archive placed in '${VZTMPL_STORAGE}' (Storage → CT Templates → ${EXPORT_NAME}).
- Base: Debian 13 (Trixie), privileged, DHCP, setup run, configure_node.sh in /root."
