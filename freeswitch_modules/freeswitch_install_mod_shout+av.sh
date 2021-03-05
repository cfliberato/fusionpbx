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

# mod_shout: MP3
yum install -y freeswitch-format-mod-shout

# mod_av: x264
yum install -y freeswitch-application-av
