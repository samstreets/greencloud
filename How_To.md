# GCNode Usage Guide

This document explains how to manage the **gcnode** service using `systemctl`, including how to stop, start, restart the service, view logs, and troubleshoot common issues.

---

## Overview

By default, the GCNode service is configured to:
- **Start automatically** after installation completes
- **Start at boot** - Enabled as a systemd service
- **Run in the background** as a system daemon

---

> **Note:** All commands must be run using `sudo` or as root.

---

## Service Management

### 1. Starting GCNode

To start the `gcnode` service:

```bash
systemctl start gcnode
```

**Expected output:** None (silent success)

**Verify it started:**
```bash
systemctl status gcnode
```

---

### 2. Stopping GCNode

To stop the `gcnode` service:

```bash
systemctl stop gcnode
```

**Expected output:** None (silent success)

**Verify it stopped:**
```bash
systemctl status gcnode
```

---

### 3. Restarting GCNode

To restart the service (stop then start):

```bash
systemctl restart gcnode
```

**Use when:**
- Configuration has been updated
- The service is misbehaving
- You want to apply changes without fully stopping

---

### 4. Checking Service Status

To check if the service is active, inactive, or failed:

```bash
systemctl status gcnode
```

**Example output:**
```
● gcnode.service - GreenCloud Node Service
     Loaded: loaded (/etc/systemd/system/gcnode.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2025-01-30 14:23:45 UTC; 5min ago
   Main PID: 12345 (gcnode)
      Tasks: 10 (limit: 4915)
     Memory: 45.2M
        CPU: 1.234s
     CGroup: /system.slice/gcnode.service
             └─12345 /var/lib/greencloud/gcnode

Jan 30 14:23:45 hostname gcnode[12345]: GreenCloud Node starting...
Jan 30 14:23:45 hostname gcnode[12345]: Node ID → a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

**Status indicators:**
- `active (running)` - Service is running normally
- `inactive (dead)` - Service is stopped
- `failed` - Service has crashed or failed to start

---

### 5. Enabling/Disabling Auto-Start

**Enable auto-start at boot:**
```bash
systemctl enable gcnode
```

**Disable auto-start at boot:**
```bash
systemctl disable gcnode
```

**Check if enabled:**
```bash
systemctl is-enabled gcnode
```

**Enable and start immediately:**
```bash
systemctl enable --now gcnode
```

---

## Viewing Logs

### Standard Linux Systems (Using journalctl)

**View the last 10 lines:**
```bash
journalctl -u gcnode -n 10
```

**View the last 50 lines:**
```bash
journalctl -u gcnode -n 50
```

**View all logs:**
```bash
journalctl -u gcnode
```

**View logs from today:**
```bash
journalctl -u gcnode --since today
```

**View logs from the last hour:**
```bash
journalctl -u gcnode --since "1 hour ago"
```

**View logs in real-time (follow mode):**
```bash
journalctl -u gcnode -f
```

**View logs with timestamps:**
```bash
journalctl -u gcnode -o short-iso
```

**View logs in reverse (newest first):**
```bash
journalctl -u gcnode -r
```

**Search logs for specific text:**
```bash
journalctl -u gcnode | grep "Node ID"
```

**Export logs to a file:**
```bash
journalctl -u gcnode > gcnode-logs-$(date +%Y%m%d).log
```

---

### LXC Containers (File-based Logging)

GCNode logs are stored in the LXC container at:

```
/var/lib/greencloud/gcnode.log
```

**View the entire log file:**
```bash
cat /var/lib/greencloud/gcnode.log
```

**View the last 20 lines:**
```bash
tail -n 20 /var/lib/greencloud/gcnode.log
```

**Follow logs in real-time:**
```bash
tail -f /var/lib/greencloud/gcnode.log
```

**Search logs for errors:**
```bash
grep -i "error\|fail" /var/lib/greencloud/gcnode.log
```

**View logs with line numbers:**
```bash
cat -n /var/lib/greencloud/gcnode.log
```

**Export recent logs:**
```bash
tail -n 100 /var/lib/greencloud/gcnode.log > gcnode-recent-$(date +%Y%m%d).log
```

---

## Extracting Node ID

The Node ID is displayed in the logs when the service starts.

**From journalctl:**
```bash
journalctl -u gcnode --no-pager | grep -oP '(?<=ID → )[a-f0-9-]+'
```

**From LXC log file:**
```bash
grep -oP '(?<=ID → )[a-f0-9-]+' /var/lib/greencloud/gcnode.log
```

**Get the most recent Node ID:**
```bash
# For journalctl
journalctl -u gcnode --no-pager -n 200 | sed -n "s/.*ID → \([a-f0-9-]\+\).*/\1/p" | tail -1

# For LXC
grep -oP '(?<=ID → )[a-f0-9-]+' /var/lib/greencloud/gcnode.log | tail -1
```

---

## Troubleshooting

### Service Won't Start

**Check the status for error messages:**
```bash
systemctl status gcnode
```

**View detailed logs:**
```bash
journalctl -u gcnode -n 100 --no-pager
```

**Check if the binary exists:**
```bash
ls -lh /var/lib/greencloud/gcnode
```

**Check if the service file exists:**
```bash
cat /etc/systemd/system/gcnode.service
```

**Reload systemd and try again:**
```bash
systemctl daemon-reload
systemctl start gcnode
```

---

### Service Keeps Crashing

**View recent crash logs:**
```bash
journalctl -u gcnode -p err -n 50
```

**Check for resource issues:**
```bash
# Check memory usage
free -h

# Check disk space
df -h

# Check CPU load
top -bn1 | head -20
```

**Restart the service with verbose output:**
```bash
systemctl restart gcnode
journalctl -u gcnode -f
```

---

### Service Not Auto-Starting at Boot

**Check if the service is enabled:**
```bash
systemctl is-enabled gcnode
```

**Enable it if disabled:**
```bash
systemctl enable gcnode
```

**Verify the service file:**
```bash
systemctl cat gcnode
```

---

### Cannot Find Logs

**For journalctl systems:**
```bash
# Check if journald is running
systemctl status systemd-journald

# Try viewing all available logs
journalctl --list-boots
journalctl -b -u gcnode
```

**For LXC systems:**
```bash
# Check if log directory exists
ls -ld /var/lib/greencloud/

# Check log file permissions
ls -lh /var/lib/greencloud/gcnode.log

# Create log directory if missing
mkdir -p /var/lib/greencloud
```

---

### High Resource Usage

**Check current resource usage:**
```bash
# Memory and CPU
systemctl status gcnode

# Detailed process info
ps aux | grep gcnode

# Resource limits
systemctl show gcnode | grep -i limit
```

**Restart the service:**
```bash
systemctl restart gcnode
```

---

## Advanced Operations

### Changing Service Configuration

**Edit the service file:**
```bash
systemctl edit --full gcnode
```

**After making changes, reload and restart:**
```bash
systemctl daemon-reload
systemctl restart gcnode
```

---

### Setting Resource Limits

**Create a drop-in configuration:**
```bash
systemctl edit gcnode
```

**Add resource limits (example):**
```ini
[Service]
MemoryLimit=512M
CPUQuota=50%
```

**Apply changes:**
```bash
systemctl daemon-reload
systemctl restart gcnode
```

---

### Running Manual Debug

**Stop the service:**
```bash
systemctl stop gcnode
```

**Run manually to see output:**
```bash
/var/lib/greencloud/gcnode
```

**Press Ctrl+C to stop, then restart the service:**
```bash
systemctl start gcnode
```

---

## Quick Reference

### Essential Commands

| Command | Description |
|---------|-------------|
| `systemctl start gcnode` | Start the service |
| `systemctl stop gcnode` | Stop the service |
| `systemctl restart gcnode` | Restart the service |
| `systemctl status gcnode` | Check service status |
| `systemctl enable gcnode` | Enable auto-start at boot |
| `systemctl disable gcnode` | Disable auto-start at boot |
| `journalctl -u gcnode -f` | Follow logs in real-time |
| `journalctl -u gcnode -n 50` | View last 50 log lines |

---

### Log Commands

| Command | Description |
|---------|-------------|
| `journalctl -u gcnode` | View all logs (journalctl) |
| `journalctl -u gcnode -f` | Follow logs in real-time |
| `journalctl -u gcnode -n 50` | View last 50 lines |
| `journalctl -u gcnode --since today` | View today's logs |
| `tail -f /var/lib/greencloud/gcnode.log` | Follow LXC logs in real-time |
| `cat /var/lib/greencloud/gcnode.log` | View entire LXC log file |

---

### Troubleshooting Commands

| Command | Description |
|---------|-------------|
| `systemctl status gcnode` | Check service status |
| `journalctl -u gcnode -p err` | View only error logs |
| `systemctl is-enabled gcnode` | Check if auto-start is enabled |
| `systemctl daemon-reload` | Reload systemd configuration |
| `ls -lh /var/lib/greencloud/gcnode` | Verify binary exists |

---

## Additional Resources

- **GreenCloud Documentation:** [https://docs.greencloudcomputing.io](https://docs.greencloudcomputing.io)
- **Systemd Manual:** `man systemd` or `man systemctl`
- **Journal Manual:** `man journalctl`

For additional support, contact GreenCloud support or refer to the official documentation.
