#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    apt-utils \
    software-properties-common \
    gnupg \
    wget \
    curl \
    vim \
    sudo

apt-get install -y --no-install-recommends \
        xdotool \
        wmctrl \
        seahorse \
        pulseaudio \
        xfce4-terminal \
        adwaita-icon-theme-full && \

gtk-update-icon-cache

mkdir -p /etc/skel/Desktop
mkdir -p /etc/skil/Autostart

cp /usr/share/applications/xfce4-terminal.desktop /etc/skel/Desktop/

rm -rf /var/lib/apt/lists/*
        