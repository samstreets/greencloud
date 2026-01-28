
# GCNode Usage Guide

This document explains how to manage the **gcnode** service using `systemctl`, including how to stop, start, restart the service, and how to view logs.
All commands must be run using sudo or as root
By default the node is set to start after completing the install and start at boot of the OS

---

## 1. Stopping GCNode

To stop the `gcnode` service:

```bash
systemctl stop gcnode
```

---

## 2. Starting GCNode

To start the `gcnode` service:

```bash
systemctl start gcnode
```

---

## 3. Restarting GCNode

To restart the service:

```bash
systemctl restart gcnode
```

---

## 4. Checking Service Status

To check if the service is active, inactive, or failed:

```bash
systemctl status gcnode
```

---

## 5. Viewing Logs on Linux

To see the last 10 lines

```bash
journalctl -u gcnode -n 10
```

To See Logs in Real Time

```bash
journalctl -u gcnode -f
```

---

## 6. Viewing GCNode Logs on LXC

GCNode logs are stored here on the LXC container:

```text
/var/lib/greencloud/gcnode.log
```

### View the log file

```bash
cat /var/lib.greencloud/gcnode.log
```

### Follow logs in real time

```bash
tail -f /var/lib.greencloud/gcnode.log
```

---

## 6. Summary

- **Start:** `systemctl start gcnode`
- **Stop:** `systemctl stop gcnode`
- **Restart:** `systemctl restart gcnode`
- **Status:** `systemctl status gcnode`
