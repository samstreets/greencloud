# GreenCloud on Ubuntu & Debian

This section documents how to install and remove **GreenCloud** on **Ubuntu and Debian** systems using the official setup and removal scripts.

---

## Overview

GreenCloud provides automated installation and removal scripts for Debian-based operating systems. These scripts handle dependency installation, service setup, and system configuration through guided prompts.

---

> Root or sudo access is required.

---

## Installation

### Step 1: Download the Installer Script

Use `wget` to download the latest GreenCloud setup script:

```
wget https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/Ubuntu/setup_greencloud.sh
```

---

### Step 2: Run the Installer

```
bash setup_greencloud.sh
```

---

### Step 3: Follow the Prompts

The installer will guide you through:

- System dependency installation
- GreenCloud configuration
- Service initialization

Follow the on-screen prompts until the installation completes.

---

## Uninstallation

### Step 1: Download the Removal Script

```
wget https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/Ubuntu/remove_greencloud.sh
```

---

### Step 2: Run the Removal Script

```
bash remove_greencloud.sh
```

---

### Step 3: Follow the Prompts

The removal script will:

- Stop GreenCloud services
- Remove installed components
- Clean up configuration files

Follow the prompts to fully remove GreenCloud from the system.

---

**GreenCloud is now installed (or removed) on your Ubuntu/Debian system.**
