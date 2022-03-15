#!/bin/bash
set -ex

# Install VS Code
wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | apt-key add - && \
add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" && \
apt update && apt install -y code
rm -rf /var/lib/apt/lists/*

# Fix icon url in shortcut
sed -i 's|Icon=.*|Icon=/usr/share/code/resources/app/resources/linux/code.png|g' /usr/share/applications/code.desktop

# Desktop shortcut
cp /usr/share/applications/code.desktop /etc/skel/Desktop/
