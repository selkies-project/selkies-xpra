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

ARG REMOTE_APPS_IMAGE=ghcr.io/selkies-project/selkies-xpra/remote-apps:latest
FROM ${REMOTE_APPS_IMAGE} as remote-apps

FROM ubuntu:bionic

# Install desktop environment
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        apt-transport-https \
        gnupg2 \
        libgtk-3-dev \
        libglu1-mesa-dev \
        libnss3-dev \
        libasound2-dev \
        libgconf2-dev \
        libxv1 \
        libgtk2.0-0 \
        libsdl2-2.0-0 \
        libxss-dev \
        libxcb-keysyms1 \
        libopenal1 \
        mesa-utils \
        x11-utils \
        x11-xserver-utils \
        xdotool \
        curl \
        ca-certificates \
        lsb-release \
        libvulkan1 \
        mesa-vulkan-drivers \
        vulkan-utils \
        vdpau-va-driver \
        vainfo \
        vdpauinfo \
        pulseaudio \
        pavucontrol \
        socat \
        jstest-gtk \
        dbus-x11 \
        sudo \
        procps \
        vim \
        xfwm4 \
        xfce4-terminal \
        gdebi-core \
        xserver-xephyr \
        git \
        uglifyjs && \
    rm -rf /var/lib/apt/lists/*

# Add Tini
ARG TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-amd64 /tini
RUN chmod +x /tini

# Printer support
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        cups-filters \
        cups-common \
        cups-pdf \
        python-cups && \
    rm -rf /var/lib/apt/lists/*

# Install ffmpeg-xpra
RUN curl -o ffmpeg-xpra.deb -L https://www.xpra.org/dists/bionic/main/binary-amd64/ffmpeg-xpra_4.0-1_amd64.deb && \
    apt-get update && \
    gdebi -n ffmpeg-xpra.deb && \
    rm -f ffmpeg-xpra.deb && \
    rm -rf /var/lib/apt/lists/*

# Install other python dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3-requests \
        python3-setproctitle \
        python3-netifaces && \
    rm -rf /var/lib/apt/lists/*

# Install GStreamer for sound support
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-pulseaudio \
        python-gst-1.0 \
        gstreamer1.0-tools && \
    rm -rf /var/lib/apt/lists/*

# Xpra runtime dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        xvfb \
        python3-pil \
        nginx \
        iso-flags-svg && \
    rm -rf /var/lib/apt/lists/*

# Install xpra from source
COPY xpra/ /opt/xpra/
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        cython3 \
        python3-cairo-dev \
        python-gi-dev \
        python3-pypandoc \
        libxres-dev \
        libxkbfile-dev && \
    rm -rf /var/lib/apt/lists/* && \
    cd /opt/xpra && \
    /usr/bin/python3.6 setup.py install \
        --prefix=/usr && \
    cd /tmp && rm -Rf /opt/xpra && \
    apt-get remove -y \
        cython3 \
        python3-cairo-dev \
        python-gi-dev \
        python3-pypandoc \
        libxres-dev \
        libxkbfile-dev

# Install remote-apps binary
COPY --from=remote-apps /opt/remote-apps /opt/remote-apps-launcher/

# Install Xpra HTML5 client from forked submodule
# NOTE: installer depends on working non-submodule get repo.

# Supported minifiers are uglifyjs and copy
ARG MINIFIER=uglifyjs
COPY xpra-html5 /opt/xpra-html5
RUN cd /opt/xpra-html5 && \
    git config --global user.email "selkies@docker" && \
    git config --global user.name "Selkies Builder" && \
    git init && git checkout -b selkies-build-patches && \
    git add . && git commit -m "selkies-build-patches" && \
    python3.6 ./setup.py install "/" "/usr/share/xpra/www/" "/etc/xpra/html5-client" ${MINIFIER} && \
    cd /tmp && rm -rf /opt/xpra-html5

# Install flags SVG for keyboard layout flag icons.
RUN mkdir -p /usr/share/xpra/www/flags && \
    ln -s /usr/share/iso-flags-svg/country-4x3 /usr/share/xpra/www/flags/4x3

# Install nginx proxy for Xpra
COPY config/nginx.conf /etc/nginx/conf.d/default.conf

ENV PYTHONPATH=/usr/lib/python3.6/site-packages

# Install Vulkan ICD
COPY config/nvidia_icd.json /usr/share/vulkan/icd.d/

# Install EGL config
RUN mkdir -p /usr/share/glvnd/egl_vendor.d
COPY config/10_nvidia.json /usr/share/glvnd/egl_vendor.d/

ENV DISPLAY :0
ENV SDL_AUDIODRIVER pulse

RUN groupadd --gid 1000 app && \
    adduser --uid 1000 --gid 1000 --disabled-password --gecos '' app

# Grant sudo to user for vulkan init workaround
RUN adduser app sudo
RUN echo "app ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd

# Add user to printer group
RUN usermod -a -G lpadmin app

# Create run directory for user
RUN sudo mkdir -p /run/user/1000 && sudo chown 1000:1000 /run/user/1000 && \
    sudo mkdir -p /run/xpra && sudo chown 1000:1000 /run/xpra

# Create empty .menu file for xdg menu.
RUN \
    mkdir -p /etc/xdg/menus && \
    echo "<Menu></Menu>" > /etc/xdg/menus/kde-debian-menu.menu

# Patch to fix Xpra webworker on Safari
COPY config/10_content_security_policy.txt /etc/xpra/http-headers/10_content_security_policy.txt

# Replace connect.html with redirect to Selkies App Launcher
COPY config/connect.html /usr/share/xpra/www/connect.html
RUN rm -f /usr/share/xpra/www/connect.html.*

# Copy PWA source files
COPY pwa/manifest.json /usr/share/xpra/www/manifest.json
COPY pwa/sw.js /usr/share/xpra/www/sw.js

# Patch the service worker with a new cache version so that it is refreshed.
RUN sudo sed -i -e "s|CACHE_VERSION|$(date +%s)|g" '/usr/share/xpra/www/sw.js'

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/tini", "--", "/entrypoint.sh"]

WORKDIR /usr/lib/python3.6/site-packages/xpra/