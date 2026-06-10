#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Set Desktop Wallpaper From URL
# Description:
#   Downloads a wallpaper image from a URL and applies it to
#   active GNOME user sessions.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
WALLPAPER_URL="https://justinverstijnen.nl/featured-background.jpg"
WALLPAPER_FILE="/usr/local/share/backgrounds/company-wallpaper.jpg"
PICTURE_OPTIONS="zoom"
LOG_FILE="/var/log/intune-wallpaper.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting wallpaper configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

apt-get update
apt-get install -y curl ca-certificates

mkdir -p "$(dirname "$WALLPAPER_FILE")"

echo "Downloading wallpaper from: $WALLPAPER_URL"
curl -L --fail --silent --show-error "$WALLPAPER_URL" -o "$WALLPAPER_FILE"
chmod 644 "$WALLPAPER_FILE"

set_wallpaper_for_user() {
    local username="$1"
    local uid
    uid="$(id -u "$username")"
    local bus="unix:path=/run/user/$uid/bus"

    if [[ ! -S "/run/user/$uid/bus" ]]; then
        echo "No active graphical session found for user: $username"
        return 0
    fi

    echo "Setting wallpaper for user: $username"

    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_FILE" || true
    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_FILE" || true
    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.background picture-options "$PICTURE_OPTIONS" || true
}

for userhome in /home/*; do
    [[ -d "$userhome" ]] || continue
    username="$(basename "$userhome")"
    id "$username" >/dev/null 2>&1 || continue
    set_wallpaper_for_user "$username"
done

echo "Wallpaper configuration completed."
exit 0
