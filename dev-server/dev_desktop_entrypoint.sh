#!/bin/bash

# Configure XDG_RUNTIME_DIR
export XDG_RUNTIME_DIR=/var/run/user
sudo chown -R $USER: ${XDG_RUNTIME_DIR}

if [[ "${VDI_enableXpra}" == false ]]; then
  # Revert back to original entrypoint if the patched entrypoint gets commited to the image.
  exec /tini -- /entrypoint.sh
  exit
fi

echo "Waiting for Xpra server"
until [[ -e /var/run/appconfig/xpra_ready ]]; do sleep 1; done
[[ -f /var/run/appconfig/.Xauthority ]] && cp /var/run/appconfig/.Xauthority ${HOME}/
echo "X server is ready"

[[ -c /dev/nvidiactl ]] && (cd /tmp && sudo LD_LIBRARY_PATH=${LD_LIBRARY_PATH} DISPLAY=${DISPLAY} vulkaninfo >/dev/null)

# Create default desktop shortcuts.
mkdir -p ${HOME}/Desktop
find /etc/skel/Desktop -name "*.desktop" -exec ln -sf {} ${HOME}/Desktop/ \; 2>/dev/null || true

# Copy autostart shortcuts
mkdir -p ${HOME}/.config/autostart
find /etc/skel/Autostart -name "*.desktop" -exec ln -sf {} ${HOME}/.config/autostart/ \; 2>/dev/null|| true

# Configure docker unix socket proxy
if [[ "${USE_DIND,,}" == "true" ]]; then
  echo "INFO: Waiting for docker sidecar"
  CERTFILE="/var/run/docker-certs/cert.pem"
  until [[ -f ${CERTFILE} ]]; do sleep 1; done
  echo "INFO: Docker sidecar is ready, starting unix socket proxy"
  sudo /usr/share/cloudshell/start-docker-unix-proxy.sh
fi

# Start remote-apps service
if [[ -e /var/run/appconfig/.remote-apps-launcher/remote-apps ]]; then
  echo "INFO: Starting remote apps service"
  /var/run/appconfig/.remote-apps-launcher/remote-apps &
fi

while true; do
  eval ${XPRA_ENTRYPOINT:-"/usr/share/dev-scripts/xpra_desktop_entrypoint.sh"}
  sleep 2
done