#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Set Timezone and Enable NTP
# Description:
#   Sets the Ubuntu timezone and enables or disables automatic
#   time synchronization using timedatectl.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
TIMEZONE="Europe/Amsterdam"
ENABLE_NTP="true"
LOG_FILE="/var/log/intune-timezone-ntp.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting timezone and NTP configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

if ! timedatectl list-timezones | grep -qx "$TIMEZONE"; then
    echo "Invalid timezone: $TIMEZONE"
    exit 1
fi

timedatectl set-timezone "$TIMEZONE"

if [[ "$ENABLE_NTP" == "true" ]]; then
    timedatectl set-ntp true
else
    timedatectl set-ntp false
fi

timedatectl status

echo "Timezone and NTP configuration completed."
exit 0
