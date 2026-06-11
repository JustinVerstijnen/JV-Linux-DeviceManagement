#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Install PowerShell 7 on Ubuntu
# Description:
#   Installs PowerShell 7 on Ubuntu by registering the Microsoft
#   package repository and installing the powershell package.
#   Also creates a desktop launcher so PowerShell appears in Ubuntu apps.
#
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================

AUTO_DETECT_UBUNTU_VERSION="true"
UBUNTU_VERSION_OVERRIDE="24.04"

INSTALL_POWERSHELL="true"
RUN_VALIDATION="true"
CREATE_DESKTOP_LAUNCHER="true"

LOG_FILE="/var/log/intune-install-powershell-7.log"

APT_LOCK_WAIT_SECONDS=300
APT_LOCK_SLEEP_SECONDS=10

# =========================
# Logging
# =========================

exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================================"
echo "Starting PowerShell 7 installation..."
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "Running as user: $(whoami)"
echo "UID: $(id -u)"
echo "Log file: $LOG_FILE"
echo "============================================================"

# =========================
# Root check
# =========================

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must run as root."
    echo "In Intune, set the script execution context to Root."
    exit 1
fi

# =========================
# OS detection
# =========================

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
else
    echo "ERROR: Cannot read /etc/os-release."
    exit 1
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "ERROR: This script is intended for Ubuntu."
    echo "Detected ID: ${ID:-unknown}"
    exit 1
fi

if [[ "$AUTO_DETECT_UBUNTU_VERSION" == "true" ]]; then
    UBUNTU_VERSION="${VERSION_ID:-}"
else
    UBUNTU_VERSION="$UBUNTU_VERSION_OVERRIDE"
fi

if [[ -z "$UBUNTU_VERSION" ]]; then
    echo "ERROR: Ubuntu version could not be detected."
    exit 1
fi

echo "Detected OS: ${PRETTY_NAME:-Ubuntu}"
echo "Detected Ubuntu version: $UBUNTU_VERSION"

# =========================
# APT lock wait function
# =========================

wait_for_apt_locks() {
    echo "Checking for active apt/dpkg locks..."

    local start_time
    start_time=$(date +%s)

    while \
        fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        fuser /var/cache/apt/archives/lock >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1
    do
        local now
        local elapsed

        now=$(date +%s)
        elapsed=$((now - start_time))

        if [[ "$elapsed" -ge "$APT_LOCK_WAIT_SECONDS" ]]; then
            echo "ERROR: apt/dpkg lock is still active after $APT_LOCK_WAIT_SECONDS seconds."
            echo "Another package process may be running."
            exit 1
        fi

        echo "apt/dpkg is locked. Waiting $APT_LOCK_SLEEP_SECONDS seconds..."
        sleep "$APT_LOCK_SLEEP_SECONDS"
    done

    echo "No apt/dpkg locks detected."
}

# =========================
# Install prerequisites
# =========================

wait_for_apt_locks

echo "Updating apt package list..."
apt-get update

wait_for_apt_locks

echo "Installing prerequisites..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget \
    curl \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    desktop-file-utils

# =========================
# Register Microsoft repository
# =========================

PACKAGE_URL="https://packages.microsoft.com/config/ubuntu/${UBUNTU_VERSION}/packages-microsoft-prod.deb"
PACKAGE_FILE="/tmp/packages-microsoft-prod.deb"

echo "Downloading Microsoft package repository configuration:"
echo "$PACKAGE_URL"

rm -f "$PACKAGE_FILE"

if ! curl -fsSL "$PACKAGE_URL" -o "$PACKAGE_FILE"; then
    echo "ERROR: Could not download Microsoft package repository configuration for Ubuntu $UBUNTU_VERSION."
    echo "Check internet access, DNS, proxy/firewall and whether this Ubuntu version is supported by the Microsoft package repository."
    exit 1
fi

if [[ ! -s "$PACKAGE_FILE" ]]; then
    echo "ERROR: Downloaded repository package is empty."
    exit 1
fi

wait_for_apt_locks

echo "Registering Microsoft package repository..."
dpkg -i "$PACKAGE_FILE"

rm -f "$PACKAGE_FILE"

wait_for_apt_locks

echo "Updating apt package list after registering Microsoft repository..."
apt-get update

# =========================
# Install PowerShell
# =========================

if [[ "$INSTALL_POWERSHELL" == "true" ]]; then
    wait_for_apt_locks

    echo "Installing PowerShell..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y powershell
else
    echo "INSTALL_POWERSHELL is set to false. Repository was registered, but PowerShell was not installed."
    exit 0
fi

# =========================
# Validation
# =========================

if [[ "$RUN_VALIDATION" == "true" ]]; then
    echo "Validating PowerShell installation..."

    if ! command -v pwsh >/dev/null 2>&1; then
        echo "ERROR: pwsh command was not found after installation."
        exit 1
    fi

    PWSH_PATH="$(command -v pwsh)"
    PWSH_VERSION="$(pwsh --NoLogo --NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"

    echo "PowerShell path: $PWSH_PATH"
    echo "PowerShell version: $PWSH_VERSION"
fi

# =========================
# Create desktop launcher
# =========================

if [[ "$CREATE_DESKTOP_LAUNCHER" == "true" ]]; then
    echo "Creating desktop launcher for PowerShell 7..."

    cat > /usr/share/applications/powershell7.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=PowerShell 7
Comment=Start PowerShell 7
Exec=x-terminal-emulator -e pwsh
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
StartupNotify=true
EOF

    chmod 644 /usr/share/applications/powershell7.desktop

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database /usr/share/applications || true
    fi

    echo "Desktop launcher created:"
    echo "/usr/share/applications/powershell7.desktop"
fi

echo "============================================================"
echo "PowerShell 7 installation completed successfully."
echo "You can start PowerShell with:"
echo "pwsh"
echo ""
echo "If the desktop launcher was created, search Ubuntu apps for:"
echo "PowerShell 7"
echo "============================================================"

exit 0
