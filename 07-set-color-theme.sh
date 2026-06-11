#!/usr/bin/env bash
set -euo pipefail

# Optional direct accent color name.
# Supported values: blue, teal, green, yellow, orange, red, pink, purple, slate
# Leave empty to map ACCENT_HEX to the closest supported color.
ACCENT_COLOR_NAME=""

# HTML hex color that will be mapped to the closest supported Ubuntu accent color.
ACCENT_HEX="#77B0DE"

# Set to "prefer-dark" or "prefer-light".
COLOR_SCHEME="prefer-light"

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
        [[ "$color" == "$supported" ]] && return 0
    done
    return 1
}

hex_to_rgb() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    echo "$r $g $b"
}

distance_squared() {
    local r1="$1" g1="$2" b1="$3" r2="$4" g2="$5" b2="$6"
    echo $(( (r1-r2)*(r1-r2) + (g1-g2)*(g1-g2) + (b1-b2)*(b1-b2) ))
}

map_hex_to_color_name() {
    local hex="$1"

    if ! [[ "$hex" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        echo "Invalid HTML hex color: $hex" >&2
        exit 1
    fi

    read -r target_r target_g target_b < <(hex_to_rgb "$hex")

    # Approximate Ubuntu/GNOME accent palette values.
    declare -A color_hex=(
        ["blue"]="#3584E4"
        ["teal"]="#2190A4"
        ["green"]="#3A944A"
        ["yellow"]="#C88800"
        ["orange"]="#E95420"
        ["red"]="#C01C28"
        ["pink"]="#D56199"
        ["purple"]="#9141AC"
        ["slate"]="#6F8396"
    )

    local best_color=""
    local best_distance=""

    for color in "${SUPPORTED_COLORS[@]}"; do
        read -r r g b < <(hex_to_rgb "${color_hex[$color]}")
        dist="$(distance_squared "$target_r" "$target_g" "$target_b" "$r" "$g" "$b")"

        if [[ -z "$best_distance" || "$dist" -lt "$best_distance" ]]; then
            best_distance="$dist"
            best_color="$color"
        fi
    done

    echo "$best_color"
}

if [[ -n "$ACCENT_COLOR_NAME" ]]; then
    if ! is_supported_color "$ACCENT_COLOR_NAME"; then
        echo "Unsupported accent color name: $ACCENT_COLOR_NAME"
        echo "Supported values: ${SUPPORTED_COLORS[*]}"
        exit 1
    fi
    SELECTED_COLOR="$ACCENT_COLOR_NAME"
else
    SELECTED_COLOR="$(map_hex_to_color_name "$ACCENT_HEX")"
fi

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
    uid="$(id -u "$username")"
    local bus="unix:path=/run/user/$uid/bus"

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
