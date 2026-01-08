
#!/bin/bash
set -euo pipefail

# ========= Settings =========
VMID=${VMID:-9000}
ROOTFS_STORAGE=${ROOTFS_STORAGE:-local-lvm}
VZTMPL_STORAGE=${VZTMPL_STORAGE:-local}
BACKUP_STORAGE=${BACKUP_STORAGE:-local}
HOSTNAME=${HOSTNAME:-greencloud-node-template}
CPU_CORES=${CPU_CORES:-2}
MEMORY_MB=${MEMORY_MB:-2048}
ROOTFS_GB=${ROOTFS_GB:-8}

# ========= Ensure Debian 13 template exists =========
TEMPLATE_FILE="/var/lib/vz/template/cache/debian-13-standard_13.0-1_amd64.tar.zst"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "[ERROR] Debian 13 LXC template not found:"
  echo "  $TEMPLATE_FILE"
  echo ""
  echo "Download it manually:"
  echo "  wget https://download.proxmox.com/images/system/debian-13-standard_13.0-1_amd64.tar.zst -O $TEMPLATE_FILE"
  exit 1
fi

# ========= Create privileged DHCP container =========
pct create "$VMID" "$TEMPLATE_FILE" \
  -hostname "$HOSTNAME" \
  -storage "$ROOTFS_STORAGE" \
  -cores "$CPU_CORES" \
  -memory "$MEMORY_MB" \
  -rootfs "$ROOTFS_STORAGE:$ROOTFS_GB" \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged 0 \
  -features nesting=1

pct start "$VMID"
sleep 6

# ========= Run your setup script =========
pct exec "$VMID" -- bash -lc \
  "curl -fsSL https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/setup_node.sh | bash"

# ========= Put configure_node.sh in /root =========
pct exec "$VMID" -- bash -lc \
  "curl -fsSL -o /root/configure_node.sh https://raw.githubusercontent.com/samstreets/greencloud/refs/heads/main/Proxmox/configure_node.sh && chmod +x /root/configure_node.sh"

# ========= Cleanup =========
pct exec "$VMID" -- bash -lc \
  "apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"

pct shutdown "$VMID"
pct template "$VMID"

# ========= vzdump backup =========
vzdump "$VMID" --mode stop --compress zstd --storage "$BACKUP_STORAGE"

# ========= Export CT template to 'vztmpl' =========
VZTMPL_PATH=$(pvesm path "$VZTMPL_STORAGE":vztmpl)
EXPORT_NAME="greencloud-debian-13_1.0_amd64.tar.zst"
EXPORT_PATH="${VZTMPL_PATH%/}/$EXPORT_NAME"

pct untemplate "$VMID"
pct start "$VMID"
sleep 3

ROOTFS_HOST_PATH="/var/lib/lxc/${VMID}/rootfs"

tar --numeric-owner --xattrs --xattrs-include='*' \
    --one-file-system \
    --exclude=proc/* --exclude=sys/* --exclude=dev/* \
    --exclude=run/* --exclude=mnt/* --exclude=media/* \
    -C "$ROOTFS_HOST_PATH" -cf - . | zstd -19 -T0 > "$EXPORT_PATH"

pct shutdown "$VMID"
pct template "$VMID"

echo "Export completed: $EXPORT_PATH"
