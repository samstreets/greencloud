# GreenCloud Node Installer

GreenCloud is a powerful cloud management platform that enables you to efficiently deploy and manage containerized workloads across distributed infrastructure. This repository provides automated installation scripts and comprehensive documentation for setting up GreenCloud Nodes on various platforms.

---

## 🚀 Features

- **Automated Installation** - One-command setup with intelligent dependency management
- **Real-Time Logging** - See exactly what's happening during installation with optional log files
- **Multi-Platform Support** - Works on Ubuntu, Debian, Proxmox, and LXC containers
- **Service Management** - Automatic systemd service configuration with auto-start on boot
- **Easy Removal** - Clean uninstallation scripts that remove all components
- **Node Management** - Simple CLI tools for managing your GreenCloud nodes
- **Scalable Architecture** - Efficiently manage multiple nodes across your infrastructure

---

## 📋 Prerequisites

### System Requirements
- **Operating Systems:** Ubuntu 20.04+, Debian 11+, Proxmox VE 9+
- **Architecture:** x86_64 (AMD64) or ARM64 (aarch64)
- **Privileges:** Root or sudo access required
- **Network:** Active internet connection for downloading components
- **Resources:** Minimum 512MB RAM, 1GB available disk space

### Required Account
- GreenCloud API Key (obtain from [GreenCloud Dashboard](https://greencloudcomputing.io))

---

## 🔧 Quick Start

### Ubuntu / Debian
```bash
wget https://raw.githubusercontent.com/greencloudcomputing/node-installer/refs/heads/main/Ubuntu/setup_greencloud.sh
bash setup_greencloud.sh
```

### Proxmox
See the [Proxmox Installation Guide](https://github.com/greencloudcomputing/node-installer/blob/main/Proxmox/Proxmox.md)

---

## 📚 Documentation

### Installation Guides
- **[Ubuntu/Debian](https://github.com/greencloudcomputing/node-installer/blob/main/Ubuntu/ubuntu_debian.md)** - Complete installation and removal guide for Debian-based systems
- **[Proxmox](https://github.com/greencloudcomputing/node-installer/blob/main/Proxmox/Proxmox.md)** - Installation guide for Proxmox Virtual Environment

### Usage Guide
- **[GCNode Management](https://github.com/greencloudcomputing/node-installer/blob/main/How_To.md)** - Service management, logging, and troubleshooting

---

## 🏗️ Repository Structure

```
node-installer/
├── Ubuntu/
│   ├── setup_greencloud.sh      # Ubuntu/Debian installation script
│   ├── remove_greencloud.sh     # Ubuntu/Debian removal script
│   ├── ubuntu_debian.md         # Ubuntu/Debian documentation
│   └── gcnode.service           # Systemd service file
├── Proxmox/
│   └── Proxmox.md               # Proxmox installation guide
├── How_To.md                    # Service management guide
└── README.md                    # This file
```

---

## 🤝 Support

### Getting Help

- **Documentation:** [https://docs.greencloudcomputing.io](https://docs.greencloudcomputing.io)
- **GitHub Issues:** [Report a bug or request a feature](https://github.com/greencloudcomputing/node-installer/issues)
- **Community Support:** Join our community forums
- **Email Support:** hello@greencloudcomputing.io

### Before Reporting Issues

Please include:
1. Your operating system and version
2. Installation log file (if available)
3. Output of `systemctl status gcnode`
4. Output of `journalctl -u gcnode -n 100`
5. Steps to reproduce the issue

---

## 🔐 Security

- **API Keys:** Never share your API key or commit it to version control
- **Log Files:** Installation logs may contain system information - review before sharing
- **Permissions:** Scripts require root/sudo access to install system packages
- **Network:** Scripts download binaries from `dl.greencloudcomputing.io` and configuration from GitHub

---

## 📜 License

This project is licensed under the terms specified by GreenCloud Computing.

---

## 🌐 Links

- **Website:** [https://greencloudcomputing.io](https://greencloudcomputing.io)
- **Documentation:** [https://docs.greencloudcomputing.io](https://docs.greencloudcomputing.io)
- **Dashboard:** [https://dashboard.greencloudcomputing.io](https://dashboard.greencloudcomputing.io)
- **GitHub:** [https://github.com/greencloudcomputing](https://github.com/greencloudcomputing)

---

**Ready to get started?** Choose your platform above and follow the installation guide!
