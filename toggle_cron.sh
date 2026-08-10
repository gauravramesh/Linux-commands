#!/bin/bash

# ==============================================================================
# Description: Toggles user crontab active state on or off.
# Usage      : ./script_name.sh [on|off]
# Details    : 'off' removes all current crontab entries.
#              'on'  restores crontab entries from a predefined template file.
# ==============================================================================

CRON_BACKUP_FILE="/home/<user_dir>/crontab_template.txt"

ACTION=$1

# --- 1. Validation ---
if [[ "$ACTION" != "on" && "$ACTION" != "off" ]]; then
    echo "ERROR: Invalid argument."
    echo "Usage: $0 [on|off]"
    exit 1
fi

if [ "$ACTION" == "off" ]; then
    echo "--- WARNING: Removing ALL crontab entries ---"

    # Check if there is even a crontab to remove
    if crontab -l >/dev/null 2>&1; then
        crontab -r
        echo "Crontab cleared successfully."
    else
        echo "Crontab is already empty."
    fi

elif [ "$ACTION" == "on" ]; then
    echo "--- Reinstating ALL crontab entries from $CRON_BACKUP_FILE ---"

    if [ -f "$CRON_BACKUP_FILE" ]; then
        crontab "$CRON_BACKUP_FILE"
        echo "Crontab restored successfully."
    else
        echo "ERROR: Backup file $CRON_BACKUP_FILE not found! Cannot reinstate."
        exit 1
    fi
fi
echo "--- Current Crontab Count ---"
crontab -l 2>/dev/null | wc -l | xargs echo "Total Lines:"
