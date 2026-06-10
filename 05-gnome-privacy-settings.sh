#!/usr/bin/env bash
set -euo pipefail

DISABLE_LOCATION_SERVICES="true"
DISABLE_RECENT_FILE_HISTORY="true"
CLEAR_EXISTING_RECENT_FILE_HISTORY="true"
DISABLE_LOCK_SCREEN_NOTIFICATIONS="true"
REMOVE_OLD_TEMP_FILES="true"
REMOVE_OLD_TRASH_FILES="true"
OLD_FILES_AGE_DAYS="30"
LOCK_PRIVACY_SETTINGS="false"
APPLY_TO_ACTIVE_USERS="true"
LOG_FILE="/var/log/intune-gnome-privacy-settings.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting GNOME privacy settings configuration..."

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

validate_boolean() {
    local name="$1"
    local value="$2"

    case "$value" in
        true|false)
            ;;
        *)
            echo "Invalid value for $name: $value"
            echo "Supported values: true, false"
            exit 1
            ;;
    esac
}

validate_boolean "DISABLE_LOCATION_SERVICES" "$DISABLE_LOCATION_SERVICES"
validate_boolean "DISABLE_RECENT_FILE_HISTORY" "$DISABLE_RECENT_FILE_HISTORY"
validate_boolean "CLEAR_EXISTING_RECENT_FILE_HISTORY" "$CLEAR_EXISTING_RECENT_FILE_HISTORY"
validate_boolean "DISABLE_LOCK_SCREEN_NOTIFICATIONS" "$DISABLE_LOCK_SCREEN_NOTIFICATIONS"
validate_boolean "REMOVE_OLD_TEMP_FILES" "$REMOVE_OLD_TEMP_FILES"
validate_boolean "REMOVE_OLD_TRASH_FILES" "$REMOVE_OLD_TRASH_FILES"
validate_boolean "LOCK_PRIVACY_SETTINGS" "$LOCK_PRIVACY_SETTINGS"
validate_boolean "APPLY_TO_ACTIVE_USERS" "$APPLY_TO_ACTIVE_USERS"

if ! [[ "$OLD_FILES_AGE_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Invalid value for OLD_FILES_AGE_DAYS: $OLD_FILES_AGE_DAYS"
    echo "The value must be a number."
    exit 1
fi

echo "Installing required packages if needed..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y dconf-cli libglib2.0-bin

if [[ "$DISABLE_LOCATION_SERVICES" == "true" ]]; then
    LOCATION_ENABLED="false"
else
    LOCATION_ENABLED="true"
fi

if [[ "$DISABLE_RECENT_FILE_HISTORY" == "true" ]]; then
    REMEMBER_RECENT_FILES="false"
else
    REMEMBER_RECENT_FILES="true"
fi

if [[ "$DISABLE_LOCK_SCREEN_NOTIFICATIONS" == "true" ]]; then
    SHOW_LOCK_SCREEN_NOTIFICATIONS="false"
else
    SHOW_LOCK_SCREEN_NOTIFICATIONS="true"
fi

mkdir -p /etc/dconf/profile
mkdir -p /etc/dconf/db/local.d
mkdir -p /etc/dconf/db/local.d/locks

if [[ ! -f /etc/dconf/profile/user ]]; then
    cat > /etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
fi

cat > /etc/dconf/db/local.d/00-intune-gnome-privacy <<EOF
[org/gnome/system/location]
enabled=$LOCATION_ENABLED

[org/gnome/desktop/privacy]
remember-recent-files=$REMEMBER_RECENT_FILES
remove-old-temp-files=$REMOVE_OLD_TEMP_FILES
remove-old-trash-files=$REMOVE_OLD_TRASH_FILES
old-files-age=uint32 $OLD_FILES_AGE_DAYS

[org/gnome/desktop/notifications]
show-in-lock-screen=$SHOW_LOCK_SCREEN_NOTIFICATIONS
EOF

if [[ "$LOCK_PRIVACY_SETTINGS" == "true" ]]; then
    cat > /etc/dconf/db/local.d/locks/00-intune-gnome-privacy-locks <<'EOF'
/org/gnome/system/location/enabled
/org/gnome/desktop/privacy/remember-recent-files
/org/gnome/desktop/privacy/remove-old-temp-files
/org/gnome/desktop/privacy/remove-old-trash-files
/org/gnome/desktop/privacy/old-files-age
/org/gnome/desktop/notifications/show-in-lock-screen
EOF
else
    rm -f /etc/dconf/db/local.d/locks/00-intune-gnome-privacy-locks
fi

dconf update

clear_recent_file_history_for_user() {
    local username="$1"
    local userhome="$2"

    if [[ -f "$userhome/.local/share/recently-used.xbel" ]]; then
        rm -f "$userhome/.local/share/recently-used.xbel"
        echo "Cleared recent file history for user: $username"
    fi
}

apply_settings_for_active_user() {
    local username="$1"
    local uid
    uid="$(id -u "$username")"

    local bus_path="/run/user/$uid/bus"
    local dbus_address="unix:path=$bus_path"

    if [[ ! -S "$bus_path" ]]; then
        echo "No active graphical session found for user: $username"
        return 0
    fi

    echo "Applying GNOME privacy settings for active user: $username"

    runuser -u "$username" -- env DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        gsettings set org.gnome.system.location enabled "$LOCATION_ENABLED" || true

    runuser -u "$username" -- env DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        gsettings set org.gnome.desktop.privacy remember-recent-files "$REMEMBER_RECENT_FILES" || true

    runuser -u "$username" -- env DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        gsettings set org.gnome.desktop.privacy remove-old-temp-files "$REMOVE_OLD_TEMP_FILES" || true

    runuser -u "$username" -- env DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        gsettings set org.gnome.desktop.privacy remove-old-trash-files "$REMOVE_OLD_TRASH_FILES" || true

    runuser -u "$username" -- env DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        gsettings set org.gnome.desktop.privacy old-files-age "uint32 $OLD_FILES_AGE_DAYS" || true

    runuser -u "$username" -- env DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        gsettings set org.gnome.desktop.notifications show-in-lock-screen "$SHOW_LOCK_SCREEN_NOTIFICATIONS" || true
}

for user_home in /home/*; do
    [[ -d "$user_home" ]] || continue

    username="$(basename "$user_home")"

    if ! id "$username" >/dev/null 2>&1; then
        continue
    fi

    if [[ "$CLEAR_EXISTING_RECENT_FILE_HISTORY" == "true" ]]; then
        clear_recent_file_history_for_user "$username" "$user_home"
    fi

    if [[ "$APPLY_TO_ACTIVE_USERS" == "true" ]]; then
        apply_settings_for_active_user "$username"
    fi
done

echo "GNOME privacy settings configuration completed."
echo "A logout/login may be required before all settings are visible."
exit 0
