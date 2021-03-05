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

# [root@localhost ~]# sngrep --version
# sngrep - 1.4.8
# Copyright (C) 2013-2018 Irontec S.L.
# License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
# This is free software: you are free to change and redistribute it.
# There is NO WARRANTY, to the extent permitted by law.
#  * Compiled with OpenSSL support.
#  * Compiled with Wide-character support.
#  * Compiled with Perl Compatible regular expressions support.
#  * Compiled with IPv6 support.
#  * Compiled with EEP/HEP support.

# Build pre-requisites
yum install -y ncurses ncurses-base ncurses-libs ncurses-devel
yum install -y libpcap libpcap-devel
yum install -y openssl openssl-libs openssl-devel
#yum install -y gnutls gnutls-c++ gnutls-devel
yum install -y pcre pcre-tools pcre-devel
yum install -y libgcrypt libgcrypt-devel

# Optional
yum install -y tcpdump screen

# Build
cd /usr/src
rm -fr sngrep
git clone --progress --verbose https://github.com/irontec/sngrep/
cd sngrep

./bootstrap.sh
./configure --with-openssl --without-gnutls --with-pcre --enable-unicode --enable-ipv6 --enable-eep
make
make install
