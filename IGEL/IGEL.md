# GreenCloud on IGEL

This repository provides instructions for installing **GreenCloud** on an **IGEL** OS using the official automated installer script.

---

## Overview

GreenCloud includes an automated installer designed for the IGEL operating system.
The installer handles:

- Dependency installation
- System configuration
- Service setup and initialization

---

## Prerequisites

- An IGEL OS device
- Internet connectivity
- Root access

---

## Installation

### Download the Installer Script

```bash
wget https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/IGEL/setup_node.sh
```

### Run the Installer

```bash
bash setup_node.sh
```

---

## Notes

This installation is **not persistent**. GreenCloud must be reinstalled after reboot.
