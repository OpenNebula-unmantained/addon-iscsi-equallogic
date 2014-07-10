#!/bin/sh

# Echoes volume name from ID_PATH received as param 1
# /etc/udev/scripts/eqliscsi_get_volume.sh

ID_PATH=$1
TARGET_NAME=${ID_PATH##*iscsi-}

# Check if EQL drive
CHECK_EQL_TARGET_NAME=${TARGET_NAME%%:*}
if [ $CHECK_EQL_TARGET_NAME = "iqn.2001-05.com.equallogic" ]; then
    # Get volume UUID
    VOLUME="${TARGET_NAME##*:}"
    # Remove lun
    VOLUME="${VOLUME%%-lun*}"
    # Echo volume name
    echo "${VOLUME:36}"
else
    exit 1
fi
exit 0
