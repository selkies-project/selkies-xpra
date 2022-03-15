#!/bin/bash -e

# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [[ "${XPRA_ARGS}" =~ use-display=yes ]]; then
    echo "Waiting for host X server at ${DISPLAY}"
    until [[ -e /var/run/appconfig/xserver_ready ]]; do sleep 1; done
    echo "Host X server is ready"
fi

# Workaround for vulkan initialization
# https://bugs.launchpad.net/ubuntu/+source/nvidia-graphics-drivers-390/+bug/1769857
[[ -c /dev/nvidiactl ]] && (cd /tmp && sudo LD_LIBRARY_PATH=${LD_LIBRARY_PATH} DISPLAY=${DISPLAY} vulkaninfo >/dev/null || true)

# Write html5 client default settings
echo "INFO: writing HTML5 default-settings.txt"
sudo rm -f /usr/share/xpra/www/default-settings.txt.*
if [[ -n "${XPRA_HTML5_DEFAULT_SETTINGS}" ]]; then
  echo "${XPRA_HTML5_DEFAULT_SETTINGS}" | sudo tee /usr/share/xpra/www/default-settings.txt
fi

# Set default Selkies xpra-html5 settings.
[[ -z "${XPRA_HTML5_SETTING_clipboard_direction}" ]] && export XPRA_HTML5_SETTING_clipboard_direction=${XPRA_CLIPBOARD_DIRECTION:-"both"}
[[ -z "${XPRA_HTML5_SETTING_video}" ]] && export XPRA_HTML5_SETTING_video="false"
[[ -z "${XPRA_HTML5_SETTING_encoding}" ]] && export XPRA_HTML5_SETTING_encoding="jpeg"
[[ -z "${XPRA_HTML5_SETTING_keyboard}" ]] && export XPRA_HTML5_SETTING_keyboard="false"
[[ -z "${XPRA_HTML5_SETTING_autohide}" ]] && export XPRA_HTML5_SETTING_autohide="true"
[[ -z "${XPRA_HTML5_SETTING_floating_menu}" ]] && export XPRA_HTML5_SETTING_floating_menu="true"
[[ -z "${XPRA_HTML5_SETTING_window_tray}" ]] && export XPRA_HTML5_SETTING_window_tray="true"
[[ -z "${XPRA_HTML5_SETTING_toolbar_position}" ]] && export XPRA_HTML5_SETTING_toolbar_position="top"
[[ -z "${XPRA_HTML5_SETTING_device_dpi_scaling}" ]] && export XPRA_HTML5_SETTING_device_dpi_scaling="true"
[[ -z "${XPRA_HTML5_SETTING_browser_native_notifications}" ]] && export XPRA_HTML5_SETTING_browser_native_notifications="false"
[[ -z "${XPRA_HTML5_SETTING_remote_apps}" ]] && export XPRA_HTML5_SETTING_remote_apps="true"

# Path prefix for xpra when behind nginx proxy.
[[ -z "${XPRA_HTML5_SETTING_path}" && -n "${XPRA_WS_PATH}" ]] && export XPRA_HTML5_SETTING_path="${XPRA_WS_PATH}"

# Path prefix for selkies app.
[[ -z "${XPRA_HTML5_SETTING_apppath}" && -n "${XPRA_PWA_APP_PATH}" ]] && export XPRA_HTML5_SETTING_apppath="${XPRA_PWA_APP_PATH}"

# Write variables prefixed with XPRA_HTML5_SETTING_ to default-settings file
for v in "${!XPRA_HTML5_SETTING_@}"; do
  setting_name=${v/XPRA_HTML5_SETTING_/}
  setting_value=$(eval echo \$$v)
  echo "$setting_name = $setting_value" | sudo tee -a /usr/share/xpra/www/default-settings.txt
done

# Add TCP module to Xpra pulseaudio server command to share pulse server with sidecars.
if [[ "${XPRA_ENABLE_AUDIO:-false}" == "true" ]]; then
  sudo sed -i -e 's|^pulseaudio-command = pulseaudio|pulseaudio-command = pulseaudio "--load=module-native-protocol-tcp port=4713 auth-anonymous=1"|g' \
    /etc/xpra/conf.d/60_server.conf
  XPRA_ARGS="${XPRA_ARGS} --sound-source=pulsesrc --speaker-codec=opus+mka"

  echo "sound = true" | sudo tee -a /usr/share/xpra/www/default-settings.txt
  echo "audio_codec = opus" | sudo tee -a /usr/share/xpra/www/default-settings.txt
  export GST_DEBUG=${GST_DEBUG:-"*:2"}
else
  XPRA_ARGS="${XPRA_ARGS} --no-pulseaudio"
  echo "sound = false" | sudo tee -a /usr/share/xpra/www/default-settings.txt
fi

# Make default-settings.txt entries unique
sort /usr/share/xpra/www/default-settings.txt | uniq > /tmp/default-settings.txt && \
  sudo mv /tmp/default-settings.txt /usr/share/xpra/www/default-settings.txt
sudo rm -f /usr/share/xpra/www/default-settings.txt.gz

if [[ -n "${XPRA_CONF}" ]]; then
  echo "INFO: echo writing xpra conf to /etc/xpra/conf.d/99_appconfig.conf"
  echo "${XPRA_CONF}" | sudo tee /etc/xpra/conf.d/99_appconfig.conf
fi

# Update PWA manifest.json with app info and route.
sudo sed -i \
  -e "s|XPRA_PWA_APP_NAME|${XPRA_PWA_APP_NAME:-Xpra Desktop}|g" \
  -e "s|XPRA_PWA_APP_PATH|${XPRA_PWA_APP_PATH:-xpra-desktop}|g" \
  '/usr/share/xpra/www/manifest.json'
sudo sed -i \
  -e "s|XPRA_PWA_DISPLAY|${XPRA_PWA_DISPLAY:-minimal-ui}|g" \
  '/usr/share/xpra/www/manifest.json'
sudo sed -i \
  -e "s|XPRA_PWA_CACHE|${XPRA_PWA_APP_PATH:-xpra-desktop}-xpra-pwa|g" \
  '/usr/share/xpra/www/sw.js'

if [[ -n "${XPRA_PWA_ICON_URL}" ]]; then
  echo "INFO: Converting icon to PWA standard"
  DEST_FILE=/tmp/icon.png
  if [[ "${XPRA_PWA_ICON_URL}" =~ "data:image/png;base64" ]]; then
    echo "${XPRA_PWA_ICON_URL}" | cut -d ',' -f2 | base64 -d > ${DEST_FILE}
  elif [[ "${XPRA_PWA_ICON_URL}" =~ "data:image/svg+xml;base64" ]]; then
    DEST_FILE=/tmp/icon.svg
    echo "${XPRA_PWA_ICON_URL}" | cut -d ',' -f2 | base64 -d > /tmp/icon.svg
  else
    curl -o /tmp/icon.dat -s -f -L "${XPRA_PWA_ICON_URL}" || true
    format=""
    ftype=$(file /tmp/icon.dat || true)
    if echo "$ftype" | grep -i -q "svg"; then
      format="svg"
    elif echo "$ftype" | grep -i -q "jpeg"; then
      format="jpg"
    elif echo "$ftype" | grep -i -q "png"; then
      format="png"
    else
      echo "WARN: unsupported icon image format: ${ftype}, PWA features may not be available."
    fi
    if [[ -n "$format" ]]; then
      mv /tmp/icon.dat /tmp/icon.${format}
      convert /tmp/icon.${format} /tmp/icon.png || true
    fi
  fi
  if [[ -e ${DEST_FILE} ]]; then
    echo "INFO: Creating PWA icon sizes"
    sudo convert -background none ${DEST_FILE} /usr/share/xpra/www/icon.png || true
    rm -f ${DEST_FILE}
    for size in 180x180 192x192 512x512; do
      sudo convert -resize ${size} -background none -gravity center -extent ${size} /usr/share/xpra/www/icon.png /usr/share/xpra/www/icon-${size}.png || true
    done
    sudo ln -s /usr/share/xpra/www/icon-180x180.png /usr/share/xpra/www/apple-touch-icon.png || true
  else
    echo "WARN: failed to download PWA icon, PWA features may not be available: ${XPRA_PWA_ICON_URL}"
  fi
fi

if [[ -n "${XPRA_BACKGROUND_URL}" ]]; then
  echo "INFO: Processing Xpra background image"
  DEST_FILE=/tmp/background.png
  if [[ "${XPRA_BACKGROUND_URL}" =~ "data:image/png;base64" ]]; then
    echo "${XPRA_BACKGROUND_URL}" | cut -d ',' -f2 | base64 -d > ${DEST_FILE}
  else
    curl -o /tmp/background.dat -s -f -L "${XPRA_BACKGROUND_URL}" || true
    format=""
    ftype=$(file /tmp/background.dat || true)
    if echo "$ftype" | grep -i -q "svg"; then
      format="svg"
    elif echo "$ftype" | grep -i -q "jpeg"; then
      format="jpg"
    elif echo "$ftype" | grep -i -q "png"; then
      format="png"
    else
      echo "WARN: unsupported background image format: ${ftype}, background will not be available."
    fi
    if [[ -n "$format" ]]; then
      mv /tmp/background.dat /tmp/icon.${format}
      convert /tmp/background.${format} ${DEST_FILE} || true
    fi
  fi
  if [[ -e ${DEST_FILE} ]]; then
    echo "INFO: Creating background image"
    sudo convert -background none ${DEST_FILE} /usr/share/xpra/www/background.png || true
  else
    echo "WARN: no background file found."
  fi
fi

# Start dbus
sudo rm -rf /var/run/dbus
dbus-uuidgen | sudo tee /var/lib/dbus/machine-id
sudo mkdir -p /var/run/dbus
sudo dbus-daemon --system

echo "Starting CUPS"
sudo cupsd
sudo sed -i 's/^add-printer-options = -u .*/add-printer-options = -u allow:all/g' /etc/xpra/conf.d/16_printing.conf
until lpinfo -v | grep -q xpraforwarder; do sleep 1; done
echo "CUPS is ready"

echo "Starting Xpra"

sudo mkdir -p /var/log/xpra
sudo chmod 777 /var/log/xpra

function watchLogs() {
  touch /var/log/xpra/xpra.log
  tail -n+1 -F /var/log/xpra/xpra.log | while read line; do
    ts=$(date)
    echo "$line"
    if [[ "${line}" =~ "startup complete" ]]; then
      echo "INFO: Saw Xpra startup complete: ${line}"
      echo "$ts" > /var/run/appconfig/.xpra-startup-complete
    fi
    if [[ "${line}" =~ "connection-established" ]]; then
      echo "INFO: Saw Xpra client connected: ${line}"
      echo "$ts" > /var/run/appconfig/.xpra-client-connected
    fi
    if [[ "${line}" =~ "client display size is" ]]; then
      echo "INFO: Saw Xpra client display size change: ${line}"
      echo ${line/*client display size is /} | cut -d' ' -f1 > /var/run/appconfig/xpra_display_size
    fi
    if [[ "${line}" =~ "client root window size is" ]]; then
      echo "INFO: Saw Xpra client display size change: ${line}"
      echo ${line/*client root window size is /} | cut -d' ' -f1 > /var/run/appconfig/xpra_display_size
    fi
  done
}

# Watch the xpra logs for key events and client resolution changes
watchLogs &

# Start nginx proxy
if [[ "${XPRA_DISABLE_PROXY:-false}" == "false" ]]; then
  if [[ "${XPRA_PORT:-8882}" != "8882" ]]; then
    echo "INFO: Updating nginx upstream xpra port to ${XPRA_PORT}"
    sudo sed -i "s|proxy_pass .*;|proxy_pass http://127.0.0.1:${XPRA_PORT};|g" /etc/nginx/conf.d/default.conf
  fi
  sudo nginx
  sudo tail -F /var/log/nginx/{access,error}.log &
fi

# Copy remote apps binary to shared dir.
mkdir -p /var/run/appconfig/.remote-apps-launcher/
cp /opt/remote-apps-launcher/remote-apps /var/run/appconfig/.remote-apps-launcher/

set -o pipefail
while true; do
  echo "" > /var/log/xpra/xpra.log
  rm -f /var/run/appconfig/xserver_ready
  rm -f /var/run/appconfig/xpra_ready
  rm -f /var/run/appconfig/.xpra-client-connected

  xpra ${XPRA_START:-"start"} ${DISPLAY} \
    --resize-display=${XPRA_RESIZE_DISPLAY:-"yes"} \
    --user=app \
    --bind-tcp=0.0.0.0:${XPRA_PORT:-8882} \
    --html=on \
    --daemon=yes \
    --log-dir=/var/log/xpra \
    --log-file=xpra.log \
    --pidfile=/var/run/xpra/xpra.pid \
    --bell=${XPRA_ENABLE_BELL:-"no"} \
    --clipboard=${XPRA_ENABLE_CLIPBOARD:-"yes"} \
    --clipboard-direction=${XPRA_CLIPBOARD_DIRECTION:-"both"} \
    --file-transfer=${XPRA_FILE_TRANSFER:-"on"} \
    --open-files=${XPRA_OPEN_FILES:-"on"} \
    --start-new-commands=${XPRA_START_COMMANDS:-"no"} \
    --printing=${XPRA_ENABLE_PRINTING:-"yes"} \
    ${XPRA_ARGS}

  # Wait for Xpra client
  echo "Waiting for Xpra client"
  until [[ -f /var/run/appconfig/.xpra-startup-complete ]]; do sleep 1; done
  until [[ -f /var/run/appconfig/.xpra-client-connected ]]; do sleep 1; done
  echo "Xpra is ready"

  xhost +
  touch /var/run/appconfig/xserver_ready
  touch /var/run/appconfig/xpra_ready

  PID=$(cat /var/run/xpra/xpra.pid)
  echo "Waiting for Xpra to exit, pid: $PID"
  tail --pid=$PID -f /dev/null

  sleep 1
done
