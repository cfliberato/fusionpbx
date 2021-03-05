#!/bin/bash

###############################################################################
#
# Copyright (C) 2021 All Rights Reserved.
# Written by Carlos Frederico (cfliberato@gmail.com)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version
# 2 of the License, or (at your option) any later version.
#
###############################################################################

# HA FusionPBX - Replicacao de Arquivos

USER=syncuser

# Install SyncThing
#
# curl:
#	-s, --silent        Silent mode. Don't output anything
#	-v, --verbose       Make the operation more talkative
#
# wget:
#	-q,  --quiet               quiet (no output)
#	-i,  --input-file=FILE     download URLs found in local or external FILE
#
rm -fr /tmp/syncthing
mkdir -p /tmp/syncthing
cd /tmp/syncthing
#curl -v https://api.github.com/repos/syncthing/syncthing/releases/latest | grep browser_download_url | grep linux-amd64 | cut -d '"' -f 4 | wget -i -
curl -s https://api.github.com/repos/syncthing/syncthing/releases/latest | grep browser_download_url | grep linux-amd64 | cut -d '"' -f 4 | wget -qi -
tar xvpfz syncthing-linux-amd64*.tar.gz
cp syncthing-linux-amd64-*/syncthing  /usr/local/bin/
type syncthing
syncthing --version

# Create service
#
cat > /etc/systemd/system/syncthing@.service <<EOF
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization for %I
Documentation=man:syncthing(1)
After=network.target

[Service]
User=%i
ExecStart=/usr/local/bin/syncthing
Restart=on-failure
SuccessExitStatus=3 4
RestartForceExitStatus=3 4

# Hardening
ProtectSystem=full
PrivateTmp=true
SystemCallArchitectures=native
MemoryDenyWriteExecute=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Create user
#
userdel -r $USER
useradd -r -g daemon -s /sbin/nologin -d /var/lib/$USER -m $USER

sudo systemctl daemon-reload
sudo systemctl start syncthing@$USER
sudo systemctl enable syncthing@$USER

# Verify sync ports
#
#	8384/tcp	Web User Interface (Web UI)
#	22000/tcp	Communications
#	22000/udp	Communications
#
netstat -alnp | egrep "8384|22000"
