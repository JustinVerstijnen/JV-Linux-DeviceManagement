#!/usr/bin/env bash
set -euo pipefail

ACCENT_COLOR_NAME="blue" # Supported values: blue, teal, green, yellow, orange, red, pink, purple, slate
COLOR_SCHEME="prefer-light" # Set to "prefer-dark" or "prefer-light".

# Apply to active graphical GNOME sessions when possible.
APPLY_TO_ACTIVE_USERS="true"
LOG_FILE="/var/log/intune-ubuntu-accent-color.log"

# =========================
# Script
# =========================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Ubuntu accent color configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

SUPPORTED_COLORS=("blue" "teal" "green" "yellow" "orange" "red" "pink" "purple" "slate")

is_supported_color() {
    local color="$1"

    for supported in "${SUPPORTED_COLORS[@]}"; do
        if [[ "$color" == "$supported" ]]; then
            return 0
        fi
    done

    return 1
}

if [[ -z "$ACCENT_COLOR_NAME" ]]; then
    echo "ACCENT_COLOR_NAME cannot be empty."
    echo "Supported values: ${SUPPORTED_COLORS[*]}"
    exit 1
fi

if ! is_supported_color "$ACCENT_COLOR_NAME"; then
    echo "Unsupported accent color name: $ACCENT_COLOR_NAME"
    echo "Supported values: ${SUPPORTED_COLORS[*]}"
    exit 1
fi

SELECTED_COLOR="$ACCENT_COLOR_NAME"

echo "Selected accent color: $SELECTED_COLOR"

case "$COLOR_SCHEME" in
    prefer-dark|prefer-light)
        ;;
    *)
        echo "Invalid COLOR_SCHEME: $COLOR_SCHEME"
        echo "Supported values: prefer-dark, prefer-light"
        exit 1
        ;;
esac

if [[ "$SELECTED_COLOR" == "orange" ]]; then
    if [[ "$COLOR_SCHEME" == "prefer-dark" ]]; then
        GTK_THEME="Yaru-dark"
        ICON_THEME="Yaru"
    else
        GTK_THEME="Yaru"
        ICON_THEME="Yaru"
    fi
else
    if [[ "$COLOR_SCHEME" == "prefer-dark" ]]; then
        GTK_THEME="Yaru-${SELECTED_COLOR}-dark"
    else
        GTK_THEME="Yaru-${SELECTED_COLOR}"
    fi

    ICON_THEME="Yaru-${SELECTED_COLOR}"
fi

echo "Selected GTK theme: $GTK_THEME"
echo "Selected icon theme: $ICON_THEME"

if [[ ! -d "/usr/share/themes/$GTK_THEME" ]]; then
    echo "Theme directory not found: /usr/share/themes/$GTK_THEME"
    echo "The selected theme may not be installed on this Ubuntu version."
    echo "Continuing with gsettings/dconf where possible."
fi

echo "Creating system-wide dconf defaults for future GNOME sessions..."

mkdir -p /etc/dconf/profile
mkdir -p /etc/dconf/db/local.d

if [[ ! -f /etc/dconf/profile/user ]]; then
    cat > /etc/dconf/profile/user <<'EOF_PROFILE'
user-db:user
system-db:local
EOF_PROFILE
fi

cat > /etc/dconf/db/local.d/00-intune-appearance <<EOF_DCONF
[org/gnome/desktop/interface]
gtk-theme='$GTK_THEME'
icon-theme='$ICON_THEME'
color-scheme='$COLOR_SCHEME'
accent-color='$SELECTED_COLOR'
EOF_DCONF

dconf update || true

apply_for_user() {
    local username="$1"
    local uid
    local bus

    uid="$(id -u "$username")"
    bus="unix:path=/run/user/$uid/bus"

    if [[ ! -S "/run/user/$uid/bus" ]]; then
        echo "No active graphical session found for user: $username"
        return 0
    fi

    echo "Applying accent color settings for active user: $username"

    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME" || true
    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" || true
    sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" || true

    if sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings list-keys org.gnome.desktop.interface | grep -qx "accent-color"; then
        sudo -u "$username" DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set org.gnome.desktop.interface accent-color "$SELECTED_COLOR" || true
    else
        echo "gsettings key org.gnome.desktop.interface accent-color is not available for user: $username"
    fi
}

if [[ "$APPLY_TO_ACTIVE_USERS" == "true" ]]; then
    for userhome in /home/*; do
        [[ -d "$userhome" ]] || continue

        username="$(basename "$userhome")"

        id "$username" >/dev/null 2>&1 || continue

        apply_for_user "$username"
    done
fi

echo "Ubuntu accent color configuration completed."
echo "A logout/login may be required before all visual changes are visible."

exit 0
