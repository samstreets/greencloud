# GreenCloud on Proxmox

Welcome to the **GreenCloud Proxmox**. This documentation explains how to deploy GreenCloud using LXC containers on Proxmox, either manually or via the automated template builder.

---

## Overview

GreenCloud runs inside a **privileged Proxmox LXC container** with specific kernel and device permissions. This wiki documents the supported deployment workflow and required configuration.

---

## Deployment Methods

You may deploy GreenCloud using one of the following methods:

- **Manual setup** using a prebuilt `greencloud.tar.zst` template
- **Automated template builder** (recommended)

---

## Container Creation

### Step 1: Download the Container Template

1. Log in to the Proxmox web UI
2. Navigate to:

   **Local (pve) → CT Templates**

3. Choose one:
   - **Download from URL**, or
   - **Upload** the template manually

Ensure `greencloud.tar.zst` is available before continuing.

---

### Step 2: Create the Container

1. Click **Create CT** (top-right)
2. **Uncheck**: `Unprivileged Container`
3. Configure:
   - Hostname
   - Root password
4. Select template:
   - `greencloud.tar.zst`
5. Leave all other options at **defaults**
6. Network configuration:
   - IPv4: **DHCP**
7. Click **Finish**

---

### Step 3: Edit Container Configuration

On the Proxmox host, edit:

```
/etc/pve/lxc/<CONTAINER_ID>.conf
```

Append the following:

```
# ==== GreenCloud runtime permissions ====
lxc.cap.drop:
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.mount.auto: proc:rw sys:rw
lxc.mount.entry: /dev/fuse dev/fuse none bind,create=file 0 0
```

---

### Step 4: Start and Enter the Container

```
pct start <CONTAINER_ID>
pct enter <CONTAINER_ID>
```

---

## Post-Installation Configuration

Inside the container (as `root`), run:

```
bash configure_node.sh
```

Follow the prompts to complete GreenCloud node configuration.

---

## Template Builder

The template builder automatically:
- Builds a GreenCloud-ready LXC template
- Outputs a reusable `.tar.zst` template

### Step 1: Download the Script

```
wget https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/Proxmox/template_build.sh
```

---

### Step 2: Run the Builder

```
bash template_build.sh
```

The generated template will be placed in:

```
/var/lib/vz/dump
```

---

### Step 3: Move Template to Proxmox Cache

```
mv /var/lib/vz/dump/greencloud*.tar.zst /var/lib/vz/template/cache/
```

The template will now appear in:

**Local (pve) → CT Templates**

---
### Follow the steps in container creation



**You’re now ready to run GreenCloud on Proxmox.**

