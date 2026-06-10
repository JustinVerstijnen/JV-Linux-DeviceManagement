#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Deploy Wi-Fi Network
# Description:
#   Creates or updates a Wi-Fi profile using NetworkManager.
#   This is useful for lab/demo purposes. Do not store production
#   Wi-Fi passwords in plain text scripts.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
SSID="JV-WiFi"
WPA_PSK="Pa$$w0rd!"
CONNECTION_NAME="JV-WiFi"
CONNECT_NOW="false"
AUTOCONNECT="yes"
LOG_FILE="/var/log/intune-wifi-profile.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Wi-Fi configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

if [[ -z "$SSID" || -z "$WPA_PSK" ]]; then
    echo "SSID and WPA_PSK must be configured."
    exit 1
fi

if ! command -v nmcli >/dev/null 2>&1; then
    echo "NetworkManager CLI not found. Installing network-manager..."
    apt-get update
    apt-get install -y network-manager
fi

if nmcli connection show "$CONNECTION_NAME" >/dev/null 2>&1; then
    echo "Updating existing Wi-Fi connection: $CONNECTION_NAME"
else
    echo "Creating new Wi-Fi connection: $CONNECTION_NAME"
    nmcli connection add type wifi ifname "*" con-name "$CONNECTION_NAME" ssid "$SSID"
fi

nmcli connection modify "$CONNECTION_NAME" \
    wifi.ssid "$SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$WPA_PSK" \
    connection.autoconnect "$AUTOCONNECT"

chmod 600 /etc/NetworkManager/system-connections/* 2>/dev/null || true

if [[ "$CONNECT_NOW" == "true" ]]; then
    echo "Connecting to Wi-Fi network..."
    nmcli connection up "$CONNECTION_NAME" || true
fi

echo "Wi-Fi profile configuration completed."
exit 0
