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

# export pass=XXXXXXXXXXXX
# export http_proxy="http://USUARIO:$pass@proxy.xyz.com:8080"
# export https_proxy="$http_proxy"
# export ftp_proxy="$http_proxy"
# export no_proxy="127.0.0.1,localhost,*.xyz.com,10.0.0.0/8"

MODULE=mod_av

# -------------------------------------------------------------------------------------

cd /usr/src/freeswitch
make ${MODULE}-install

fs_cli -x "load ${MODULE}"
fs_cli -x "module_exists ${MODULE}"
fs_cli -x "show modules" | grep ${MODULE}
