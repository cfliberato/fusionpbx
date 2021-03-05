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

# Monitoring node join/removal
SELECT * FROM bdr.bdr_nodes;

# Connection strings used for each node to connect to each other node
SELECT * FROM bdr.bdr_connections;

# Monitoring connected peers using pg_stat_replication
SELECT * FROM pg_stat_replication;

# Monitoring replication slots
SELECT * FROM pg_replication_slots;

# Monitoring global DDL locks
SELECT * FROM bdr.bdr_global_locks;

# Statistics
SELECT * FROM bdr.pg_stat_bdr;

# End of file
exit 0
