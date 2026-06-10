#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Install Microsoft Defender for Endpoint
# Description:
#   Installs the Microsoft Defender for Endpoint Linux package.
#   Onboarding requires an official onboarding package from the
#   Microsoft Defender portal.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
MDE_CHANNEL="prod"
ONBOARDING_PACKAGE_URL=""
ONBOARDING_PACKAGE_ZIP="/tmp/mde-onboarding.zip"
ONBOARDING_DIR="/tmp/mde-onboarding"
LOG_FILE="/var/log/intune-mde-install.log"

# Set to true only if you host the official onboarding ZIP on an internal secure URL.
DOWNLOAD_ONBOARDING_PACKAGE="false"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Microsoft Defender for Endpoint installation..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

if ! command -v lsb_release >/dev/null 2>&1; then
    apt-get update
    apt-get install -y lsb-release
fi

UBUNTU_VERSION="$(lsb_release -rs)"

echo "Detected Ubuntu version: $UBUNTU_VERSION"

apt-get update
apt-get install -y curl gnupg apt-transport-https ca-certificates python3 unzip

echo "Adding Microsoft package repository..."
curl -fsSL "https://packages.microsoft.com/config/ubuntu/${UBUNTU_VERSION}/packages-microsoft-prod.deb" -o /tmp/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb
apt-get update

echo "Installing mdatp..."
apt-get install -y mdatp

if [[ "$DOWNLOAD_ONBOARDING_PACKAGE" == "true" ]]; then
    if [[ -z "$ONBOARDING_PACKAGE_URL" ]]; then
        echo "ONBOARDING_PACKAGE_URL is empty. Cannot download onboarding package."
        exit 1
    fi

    echo "Downloading onboarding package..."
    rm -rf "$ONBOARDING_DIR"
    mkdir -p "$ONBOARDING_DIR"

    curl -L --fail --silent --show-error "$ONBOARDING_PACKAGE_URL" -o "$ONBOARDING_PACKAGE_ZIP"
    unzip -o "$ONBOARDING_PACKAGE_ZIP" -d "$ONBOARDING_DIR"

    ONBOARDING_SCRIPT="$(find "$ONBOARDING_DIR" -type f -name 'MicrosoftDefenderATPOnboardingLinux*.py' | head -n 1 || true)"

    if [[ -z "$ONBOARDING_SCRIPT" ]]; then
        echo "Onboarding script not found in ZIP file."
        exit 1
    fi

    echo "Running onboarding script..."
    python3 "$ONBOARDING_SCRIPT"
else
    echo "Skipping onboarding package download."
    echo "Install completed, but onboarding still needs to be performed."
fi

echo "Checking Defender health..."
mdatp health || true

echo "Microsoft Defender for Endpoint installation script completed."
exit 0
