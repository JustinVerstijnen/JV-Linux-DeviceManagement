#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Install PowerShell 7
# Description:
#   Installs PowerShell 7 on Ubuntu by registering the Microsoft
#   package repository and installing the powershell package.
#
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================

# Auto-detect the Ubuntu version from /etc/os-release.
# Set to "false" and fill UBUNTU_VERSION_OVERRIDE if you want to force a version.
AUTO_DETECT_UBUNTU_VERSION="true"
UBUNTU_VERSION_OVERRIDE="24.04"

# Install PowerShell after registering the Microsoft repository.
INSTALL_POWERSHELL="true"

# Run a simple validation command after installation.
RUN_VALIDATION="true"

LOG_FILE="/var/log/intune-install-powershell-7.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting PowerShell 7 installation..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
else
    echo "Cannot read /etc/os-release."
    exit 1
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "This script is intended for Ubuntu. Detected ID: ${ID:-unknown}"
    exit 1
fi

if [[ "$AUTO_DETECT_UBUNTU_VERSION" == "true" ]]; then
    UBUNTU_VERSION="${VERSION_ID:-}"
else
    UBUNTU_VERSION="$UBUNTU_VERSION_OVERRIDE"
fi

if [[ -z "$UBUNTU_VERSION" ]]; then
    echo "Ubuntu version could not be detected."
    exit 1
fi

echo "Detected Ubuntu version: $UBUNTU_VERSION"

echo "Installing prerequisites..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget \
    curl \
    ca-certificates \
    apt-transport-https \
    software-properties-common

PACKAGE_URL="https://packages.microsoft.com/config/ubuntu/${UBUNTU_VERSION}/packages-microsoft-prod.deb"
PACKAGE_FILE="/tmp/packages-microsoft-prod.deb"

echo "Downloading Microsoft package repository configuration:"
echo "$PACKAGE_URL"

if ! curl -fsSL "$PACKAGE_URL" -o "$PACKAGE_FILE"; then
    echo "Could not download Microsoft package repository configuration for Ubuntu $UBUNTU_VERSION."
    echo "Check whether this Ubuntu version is supported by Microsoft packages."
    exit 1
fi

echo "Registering Microsoft package repository..."
dpkg -i "$PACKAGE_FILE"
rm -f "$PACKAGE_FILE"

apt-get update

if [[ "$INSTALL_POWERSHELL" == "true" ]]; then
    echo "Installing PowerShell..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y powershell
else
    echo "INSTALL_POWERSHELL is set to false. Repository was registered, but PowerShell was not installed."
    exit 0
fi

if [[ "$RUN_VALIDATION" == "true" ]]; then
    echo "Validating PowerShell installation..."

    if ! command -v pwsh >/dev/null 2>&1; then
        echo "pwsh command was not found after installation."
        exit 1
    fi

    pwsh --NoLogo --NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
fi

echo "PowerShell 7 installation completed."
exit 0
