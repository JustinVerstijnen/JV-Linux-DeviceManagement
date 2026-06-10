#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Enable Automatic Security Updates
# Description:
#   Installs and configures unattended-upgrades for automatic
#   Ubuntu security updates.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
ENABLE_AUTOMATIC_REBOOT="false"
AUTOMATIC_REBOOT_TIME="03:30"
LOG_FILE="/var/log/intune-automatic-security-updates.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting automatic security updates configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

apt-get update
apt-get install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat > /etc/apt/apt.conf.d/51unattended-upgrades-intune <<EOF
Unattended-Upgrade::Automatic-Reboot "$ENABLE_AUTOMATIC_REBOOT";
Unattended-Upgrade::Automatic-Reboot-Time "$AUTOMATIC_REBOOT_TIME";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

echo "Automatic security updates configuration completed."
exit 0
