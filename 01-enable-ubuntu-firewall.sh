#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Enable Ubuntu Firewall
# Description:
#   Enables and configures the Ubuntu firewall using UFW.
#   By default, incoming connections are blocked and outgoing
#   connections are allowed. Optional variables can be used to
#   allow SSH or additional TCP/UDP ports.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
ENABLE_FIREWALL="true"

# Default firewall behavior
DEFAULT_INCOMING_POLICY="deny"
DEFAULT_OUTGOING_POLICY="allow"

# Allow SSH before enabling the firewall.
# Set to "false" if SSH should not be allowed.
ALLOW_SSH="true"
SSH_PORT="22"

# Optional additional allowed TCP ports.
# Example: ALLOWED_TCP_PORTS=("80" "443" "3389")
ALLOWED_TCP_PORTS=()

# Optional additional allowed UDP ports.
# Example: ALLOWED_UDP_PORTS=("51820")
ALLOWED_UDP_PORTS=()

LOG_FILE="/var/log/intune-enable-ubuntu-firewall.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Ubuntu firewall configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

if [[ "$ENABLE_FIREWALL" != "true" ]]; then
    echo "ENABLE_FIREWALL is set to false. No changes will be made."
    exit 0
fi

echo "Installing UFW if needed..."
apt-get update
apt-get install -y ufw

echo "Setting default firewall policies..."
ufw default "$DEFAULT_INCOMING_POLICY" incoming
ufw default "$DEFAULT_OUTGOING_POLICY" outgoing

if [[ "$ALLOW_SSH" == "true" ]]; then
    echo "Allowing SSH on TCP port $SSH_PORT..."
    ufw allow "$SSH_PORT/tcp"
fi

if [[ ${#ALLOWED_TCP_PORTS[@]} -gt 0 ]]; then
    for port in "${ALLOWED_TCP_PORTS[@]}"; do
        echo "Allowing TCP port $port..."
        ufw allow "$port/tcp"
    done
fi

if [[ ${#ALLOWED_UDP_PORTS[@]} -gt 0 ]]; then
    for port in "${ALLOWED_UDP_PORTS[@]}"; do
        echo "Allowing UDP port $port..."
        ufw allow "$port/udp"
    done
fi

echo "Enabling UFW..."
ufw --force enable

echo "Firewall status:"
ufw status verbose

echo "Ubuntu firewall configuration completed."
exit 0
