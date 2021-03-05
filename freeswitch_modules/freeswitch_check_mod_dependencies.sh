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

if [ -d /usr/lib64/freeswitch/mod ]; then
	cp /dev/null /tmp/libs
	cd /usr/lib64/freeswitch/mod/
	for module in $(ls *.so); do
		echo -e "Module: $module"
		echo -e "RPMs: \c"
		for libname in $(ldd $module 2>&1 | sed -e '/=>/!d' -e 's|^[[:blank:]]*\(.*\) =>.*$|\1|'); do
			library=$(locate $libname | tail -1)
			[ ! -z "$library" ] && rpm -qf $library
		done | sort -u | sed -e 's/\-[0-9].*//g' | tee -a /tmp/libs | tr '\n' ' '
		echo -e "\n"
	done
	echo 
	echo "All modules"
	cat /tmp/libs | sort -u | tr '\n' ' '
	echo
else
	echo "FreeSWITCH not installed!"
fi
exit 0
