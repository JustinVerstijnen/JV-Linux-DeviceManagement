#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Add OneDrive Access
# Description:
#   Adds a OneDrive launcher that opens OneDrive in the default browser.
#   Optionally installs the community OneDrive sync client from Ubuntu
#   repositories. User authentication is still required.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
ONEDRIVE_WEB_URL="https://onedrive.live.com/"
INSTALL_COMMUNITY_SYNC_CLIENT="false"
DESKTOP_FILE="/usr/share/applications/onedrive-web.desktop"
ICON_NAME="folder-cloud"
LOG_FILE="/var/log/intune-onedrive-access.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting OneDrive access configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

apt-get update
apt-get install -y xdg-utils

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=OneDrive
Comment=Open OneDrive in the default browser
Exec=xdg-open $ONEDRIVE_WEB_URL
Icon=$ICON_NAME
Terminal=false
Type=Application
Categories=Network;Office;
EOF

chmod 644 "$DESKTOP_FILE"

if [[ "$INSTALL_COMMUNITY_SYNC_CLIENT" == "true" ]]; then
    echo "Installing community OneDrive sync client from Ubuntu repositories..."
    apt-get install -y onedrive

    mkdir -p /etc/skel/.config/onedrive

    cat > /etc/skel/.config/onedrive/config <<'EOF'
sync_dir = "~/OneDrive"
skip_file = "~*|.~*|*.tmp|*.swp"
EOF

    echo "Community OneDrive client installed."
    echo "Each user still needs to run 'onedrive' once to authenticate."
fi

echo "OneDrive access configuration completed."
exit 0
