#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Check Device Encryption
# Description:
#   Checks whether the Ubuntu device appears to use LUKS disk encryption.
#   This script does not enable encryption. Full disk encryption should
#   normally be configured during Ubuntu installation.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
REQUIRE_ENCRYPTED_DISK="true"
LOG_FILE="/var/log/intune-disk-encryption-check.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting disk encryption check..."

if ! command -v lsblk >/dev/null 2>&1; then
    echo "lsblk is not available. Cannot verify disk encryption."
    exit 1
fi

if lsblk -rno FSTYPE | grep -q "^crypto_LUKS$"; then
    echo "Disk encryption check passed. A LUKS encrypted volume was detected."
    exit 0
fi

echo "No LUKS encrypted volume was detected."

if [[ "$REQUIRE_ENCRYPTED_DISK" == "true" ]]; then
    echo "Disk encryption is required, but this device does not appear to be encrypted."
    echo "Full disk encryption should normally be configured during Ubuntu installation."
    exit 1
fi

echo "Disk encryption is not required by this script. Exiting successfully."
exit 0
