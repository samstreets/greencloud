# GreenCloud on Ubuntu & Debian

This section documents how to install and remove **GreenCloud** on **Ubuntu and Debian** systems using the official setup and removal scripts.

---

## Overview

GreenCloud provides automated installation and removal scripts for Debian-based operating systems. These scripts handle dependency installation, service setup, and system configuration through guided prompts.

Both scripts include **real-time logging** by default, allowing you to see exactly what's happening during each step while automatically saving all output to timestamped log files.

---

> **Note:** Root or sudo access is required for both installation and removal.

---

## Installation

### Step 1: Download the Installer Script

Use `wget` to download the latest GreenCloud setup script:

```bash
wget https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/Ubuntu/setup_greencloud.sh
```

---

### Step 2: Run the Installer

**Default mode (with logging and real-time output):**
```bash
sudo bash setup_greencloud.sh
```

**What happens:**
- Real-time output is displayed for each installation step
- A timestamped log file is automatically created: `greencloud-setup-YYYYMMDD-HHMMSS.log` in the same directory
- All output shown on screen is also saved to the log file

**Silent mode (no logging, spinner only):**
```bash
sudo GREENCLOUD_ENABLE_LOGGING=false bash setup_greencloud.sh
```

**Custom log location:**
```bash
sudo GREENCLOUD_LOG_FILE=/var/log/greencloud-setup.log bash setup_greencloud.sh
```

---

### Step 3: Follow the Prompts

The installer will guide you through:

1. **System Updates** - Updates package lists
2. **Dependency Installation** - Installs curl, wget, certificates, containerd, and CNI plugins
3. **Service Configuration** - Configures containerd and system settings
4. **GreenCloud Installation** - Downloads and installs GreenCloud Node and CLI
5. **Authentication** - You'll be prompted to enter your GreenCloud API key
6. **Node Registration** - You'll name your node and it will be registered with GreenCloud

Follow the on-screen prompts until the installation completes.

---

### Installation Output Example

```
✓ Logging enabled: /path/to/greencloud-setup-20250130-142345.log

Step 1 of 9: Updating system packages…
--- Begin output ---
Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease
Get:2 http://archive.ubuntu.com/ubuntu noble-updates InRelease [126 kB]
Fetched 252 kB in 1s (252 kB/s)
Reading package lists... Done
--- End output ---
✓ Updating system packages completed

Step 2 of 9: Installing prerequisites (curl, wget, certs)…
--- Begin output ---
...
```

---

## Log Files

### Default Behavior

By default, the installer creates a log file in the same directory where you run the script:
- **Filename format:** `greencloud-setup-YYYYMMDD-HHMMSS.log`
- **Contains:** All command output, timestamps, success/failure status, and any errors

### Viewing Logs

**Find your log file:**
```bash
ls -lh greencloud-setup-*.log
```

**View the most recent log:**
```bash
cat $(ls -t greencloud-setup-*.log | head -1)
```

**Search for errors:**
```bash
grep -i "error\|failed" greencloud-setup-*.log
```

**Follow log in real-time (from another terminal):**
```bash
tail -f greencloud-setup-*.log
```

---

## Uninstallation

### Step 1: Download the Removal Script

```bash
wget https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/Ubuntu/remove_greencloud.sh
```

---

### Step 2: Run the Removal Script

**Default mode (with logging and real-time output):**
```bash
sudo bash remove_greencloud.sh
```

**What happens:**
- Real-time output is displayed for each removal step
- A timestamped log file is automatically created: `greencloud-remove-YYYYMMDD-HHMMSS.log` in the same directory
- All output shown on screen is also saved to the log file

**Silent mode (no logging, spinner only):**
```bash
sudo GREENCLOUD_ENABLE_LOGGING=false bash remove_greencloud.sh
```

**Custom log location:**
```bash
sudo GREENCLOUD_LOG_FILE=/var/log/greencloud-removal.log bash remove_greencloud.sh
```

---

### Step 3: Follow the Prompts

The removal script will:

1. **Authenticate** - You'll be prompted to enter your GreenCloud API key
2. **Extract Node ID** - Automatically retrieves your node's ID from the system
3. **Unregister Node** - Removes the node from your GreenCloud account
4. **Remove Services** - Stops and removes the gcnode systemd service
5. **Remove Components** - Removes containerd, runc, GreenCloud Node, and CLI
6. **Clean Up** - Removes configuration files and directories

Follow the prompts to fully remove GreenCloud from the system.

---

## Configuration Options

Both scripts support the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `GREENCLOUD_ENABLE_LOGGING` | `true` | Set to `false` to disable logging and real-time output |
| `GREENCLOUD_LOG_FILE` | `./greencloud-[setup\|remove]-YYYYMMDD-HHMMSS.log` | Custom path for the log file |

---

## Troubleshooting

### Permission Issues

If you encounter permission errors:
```bash
# Ensure you're running with sudo
sudo bash setup_greencloud.sh

# Or run from a directory where you have write permissions
cd /tmp
sudo bash /path/to/setup_greencloud.sh
```

### Log File Not Created

Check if logging is disabled:
```bash
# Explicitly enable logging
sudo GREENCLOUD_ENABLE_LOGGING=true bash setup_greencloud.sh
```

### Installation Fails

1. Check the log file for detailed error messages
2. Ensure you have a stable internet connection
3. Verify you have sufficient disk space
4. Make sure you're running Ubuntu or Debian (compatible versions)

### Viewing Previous Installation Logs

All log files are timestamped, making it easy to review past installations:
```bash
# List all setup logs
ls -lt greencloud-setup-*.log

# View a specific log
cat greencloud-setup-20250130-142345.log
```

---

## Advanced Usage

### Automated Deployments

For scripted deployments, use silent mode to minimize output:
```bash
#!/bin/bash
# Deploy script
sudo GREENCLOUD_ENABLE_LOGGING=false bash setup_greencloud.sh <<EOF
your-api-key-here
your-node-name
EOF
```

### Centralized Logging

For enterprise environments, specify a centralized log location:
```bash
# Installation
sudo GREENCLOUD_LOG_FILE=/var/log/greencloud/install-$(hostname)-$(date +%Y%m%d).log bash setup_greencloud.sh

# Removal
sudo GREENCLOUD_LOG_FILE=/var/log/greencloud/remove-$(hostname)-$(date +%Y%m%d).log bash remove_greencloud.sh
```

### Running Without Prompts

You can pipe credentials to the script (use with caution in production):
```bash
# Installation
echo -e "your-api-key\nyour-node-name" | sudo bash setup_greencloud.sh

# Removal
echo "your-api-key" | sudo bash remove_greencloud.sh
```

---

## Security Notes

- **API keys are never logged** - Input is hidden and not written to log files
- **Log files may contain system information** - Ensure proper permissions on production systems
- **Secure your log files** - Consider using `chmod 600` on logs containing sensitive data:
  ```bash
  chmod 600 greencloud-*.log
  ```

---

**GreenCloud is now installed (or removed) on your Ubuntu/Debian system.**

For additional support, please refer to the [GreenCloud Documentation](https://docs.greencloudcomputing.io) or contact support.
