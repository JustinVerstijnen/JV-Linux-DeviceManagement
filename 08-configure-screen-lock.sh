#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Configure Screen Lock
# Description:
#   Configures GNOME idle and lock screen settings for active users.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
IDLE_DELAY_SECONDS="300"
LOCK_ENABLED="true"
LOCK_DELAY_SECONDS="0"
LOG_FILE="/var/log/intune-screen-lock.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting screen lock configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

apply_lock_settings_for_user() {
    local username="$1"
    local uid
    uid="$(id -u "$username")"
    local bus="unix:path=/run/user/$uid/bus"

    if [[ ! -S "/run/user/$uid/bus" ]]; then
        echo "No active graphical session found for user: $username"
        return 0
    fi

    echo "Applying screen lock settings for user: $username"

    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.session idle-delay "uint32 $IDLE_DELAY_SECONDS" || true
    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.screensaver lock-enabled "$LOCK_ENABLED" || true
    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.screensaver lock-delay "uint32 $LOCK_DELAY_SECONDS" || true
}

for userhome in /home/*; do
    [[ -d "$userhome" ]] || continue
    username="$(basename "$userhome")"
    id "$username" >/dev/null 2>&1 || continue
    apply_lock_settings_for_user "$username"
done

echo "Screen lock configuration completed."
exit 0
