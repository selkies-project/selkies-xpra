#!/bin/bash

echo "INFO: starting xpra desktop entrypoint"

# Start dbus
sudo rm -rf /var/run/dbus
dbus-uuidgen | sudo tee /var/lib/dbus/machine-id
sudo mkdir -p /var/run/dbus
sudo dbus-daemon --system

# Start keyring
# NOTE: requires cap add IPC_LOCK on container.
DEFAULT_KEYRING="${HOME}/.local/share/keyrings/Default.keyring"
if [[ ! -e ${DEFAULT_KEYRING} ]]; then
    # Create default passwordless keyring.
    mkdir -p $(dirname ${DEFAULT_KEYRING})
    ctime=$(date "+%s")
    cat - > ${DEFAULT_KEYRING} <<EOF
[keyring]
display-name=Default
ctime=${ctime}
mtime=0
lock-on-idle=false
lock-after=false

[1]
item-type=0
display-name=Password for '${USER}' on 'Default'
mtime=${ctime}
ctime=${ctime}

[1:attribute0]
name=application
type=string
value=Python keyring library

[1:attribute1]
name=service
type=string
value=Default

[1:attribute2]
name=username
type=string
value=${USER}
EOF
    chmod 0600 ${DEFAULT_KEYRING}
    echo -n "Default" > ${HOME}/.local/share/keyrings/default
fi
#/usr/bin/gnome-keyring-daemon --start --daemonize --components=secrets || true

# Run first-time user startup scripts
[[ ${RUN_INIT_USER_SCRIPTS:-"true"} == "true" ]] && /usr/share/dev-scripts/init_user_scripts.sh

DESKTOP_ENABLED="${XPRA_ENABLE_XFDESKTOP:-true}"

# Run in background while we auto-start and maximize apps.
if [[ "${DESKTOP_ENABLED}" == "true" ]]; then
    xfdesktop --sm-client-disable --disable-wm-check --arrange &
    PID=$!
    sleep 2
fi

find /etc/skel/Autostart -name "*.desktop" -exec exo-open {} \; || true
ls /etc/skel/Autostart/*.maximize.desktop 2>/dev/null | xargs -P8 -I {} /usr/share/dev-scripts/maximize_window.sh {} &
ls /etc/skel/Autostart/*.fullscreen.desktop 2>/dev/null | xargs -P8 -I {} /usr/share/dev-scripts/fullscreen_window.sh {} &

if [[ "${DESKTOP_ENABLED}" == "true" ]]; then
    # Bring xfdesktop back to the foreground.
    wait $PID
else
    while true; do sleep 10000; done
fi