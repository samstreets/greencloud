#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "Installing containerd..."
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl enable --now containerd

echo "Installing runc..."
wget -q https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64 -O runc
sudo install -m 755 runc /usr/local/sbin/runc
runc --version

echo "Configuring ping group range..."
sudo sysctl -w net.ipv4.ping_group_range="0 2147483647"

echo "Setting up GreenCloud node..."
sudo mkdir -p /var/lib/greencloud
wget -q https://dl.greencloudcomputing.io/gcnode/main/gcnode-main-linux-amd64 -O gcnode
chmod +x gcnode
sudo mv gcnode /var/lib/greencloud/

echo "Installing GreenCloud CLI..."
wget -q https://dl.greencloudcomputing.io/gccli/main/gccli-main-linux-amd64 -O gccli
chmod +x gccli
sudo mv gccli /usr/local/bin/

echo "Setting up gcnode systemd service..."
sudo mv gcnode.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gcnode
sudo systemctl status gcnode
