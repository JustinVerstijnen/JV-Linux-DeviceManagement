#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Configure Firefox Homepage
# Description:
#   Creates a system-wide Firefox enterprise policy to configure
#   the browser homepage.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
HOMEPAGE_URL="https://www.microsoft365.com/"
LOCK_HOMEPAGE="false"
START_PAGE="homepage"
POLICY_DIR="/etc/firefox/policies"
POLICY_FILE="/etc/firefox/policies/policies.json"
LOG_FILE="/var/log/intune-firefox-homepage.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Firefox homepage configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

mkdir -p "$POLICY_DIR"

cat > "$POLICY_FILE" <<EOF
{
  "policies": {
    "Homepage": {
      "URL": "$HOMEPAGE_URL",
      "Locked": $LOCK_HOMEPAGE,
      "StartPage": "$START_PAGE"
    }
  }
}
EOF

chmod 644 "$POLICY_FILE"

echo "Firefox homepage policy created at: $POLICY_FILE"
echo "Firefox must be restarted before the policy is applied."
exit 0
