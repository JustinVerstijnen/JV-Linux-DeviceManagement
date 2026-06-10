#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script: Set Simple Color Theme
# Description:
#   Applies a simple GTK accent color using an HTML hex color.
#   Not every application will fully respect this setting.
# Intune run context:
#   Root
# ============================================================

# =========================
# Variables
# =========================
ACCENT_HEX="#0078D4"
PREFER_DARK_MODE="false"
LOG_FILE="/var/log/intune-color-theme.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting color theme configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

if ! [[ "$ACCENT_HEX" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
    echo "Invalid HTML hex color: $ACCENT_HEX"
    echo "Expected format: #RRGGBB"
    exit 1
fi

apply_theme_for_user() {
    local username="$1"
    local userhome="$2"
    local uid
    uid="$(id -u "$username")"
    local bus="unix:path=/run/user/$uid/bus"

    echo "Applying color theme for user: $username"

    mkdir -p "$userhome/.config/gtk-3.0"
    mkdir -p "$userhome/.config/gtk-4.0"

    cat > "$userhome/.config/gtk-3.0/gtk.css" <<EOF
@define-color accent_color $ACCENT_HEX;
@define-color theme_selected_bg_color $ACCENT_HEX;
@define-color theme_selected_fg_color #ffffff;
EOF

    cat > "$userhome/.config/gtk-4.0/gtk.css" <<EOF
@define-color accent_color $ACCENT_HEX;
@define-color theme_selected_bg_color $ACCENT_HEX;
@define-color theme_selected_fg_color #ffffff;
EOF

    chown -R "$username:$username" "$userhome/.config/gtk-3.0" "$userhome/.config/gtk-4.0"

    if [[ -S "/run/user/$uid/bus" ]]; then
        if [[ "$PREFER_DARK_MODE" == "true" ]]; then
            sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" || true
        else
            sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.interface color-scheme "prefer-light" || true
        fi
    fi
}

for userhome in /home/*; do
    [[ -d "$userhome" ]] || continue
    username="$(basename "$userhome")"
    id "$username" >/dev/null 2>&1 || continue
    apply_theme_for_user "$username" "$userhome"
done

echo "Color theme configuration completed."
exit 0
