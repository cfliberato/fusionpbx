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

# PostgreSQL HA
#
database_host=127.0.0.1
database_port=5432
database_username=fusionpbx
database_password=fusionpbx
node1=<ip-server-primary>
node2=<ip-server-others>
this=$(hostname -I | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')

# Configure Linux locale
#
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
#localectl set-locale en_US.UTF-8

# Configure PostgreSQL
#
export PG_VER=9.4
export PATH=$PATH:/usr/lib/postgresql/${PG_VER}/bin
export PSQL=/usr/pgsql-${PG_VER}/bin/psql
export PGPASSWORD=$database_password

# Database backup
#
mkdir -p /var/backups/fusionpbx/postgresql
chown -R postgres:postgres /var/backups/fusionpbx/postgresql
PGPASSWORD=$database_password pg_dump --verbose -Fc \
        --host=$database_host \
        --port=$database_port \
        --user=$database_username \
        --schema=public \
		--dbname=fusionpbx \
        -f /var/backups/fusionpbx/postgresql/fusionpbx_backup.sql

# Empty fusionpbx database
#
# DROP SCHEMA bdr CASCADE;
su - postgres -c "$PSQL --dbname=fusionpbx --echo-all" <<EOF
\dn
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
\dn
EOF

## SSL Self-Signed
##
cd /var/lib/pgsql/9.4-bdr/data
SUBJ="
C=BR
ST=RJ
L=Rio de Janeiro
O=XYZ
CN=xyz.com
emailAddress=root@xyz.com
"
cd /var/lib/pgsql/9.4-bdr/data
openssl genrsa -des3 -out server.key 1024
openssl rsa -in server.key -out server.key
openssl req -new -key server.key -days 3650 -out server.crt -x509 -subj '/C=BR/ST=RiodeJaneiro/L=RiodeJaneiro/O=XYZ/CN=xyz.com/emailAddress=root@xyz.com'
chmod 400 server.key
chown postgres.postgres server.key
cp server.crt root.crt

#openssl req -x509 -nodes -subj "$(echo -n "$SUBJ" | tr "\n" "/")" \
#        -days 3650 -newkey rsa:2048 -keyout server.key -out root.crt
#chmod 400 server.key root.crt
#chown postgres:postgres server.key root.crt

# Backup configuration files
#
cd /var/lib/pgsql/9.4-bdr/data
cp {pg_hba,pg_hba-backup}.conf
cp {postgresql,postgresql-backup}.conf

# Update postgresql.conf
#
# #ssl = off                              # (change requires restart)
# #ssl_ca_file = ''                       # (change requires restart)
#
# #listen_addresses = 'localhost'         # what IP address(es) to listen on;
# #shared_preload_libraries = ''          # (change requires restart)
# #wal_level = minimal                    # minimal, archive, hot_standby, or logical
# #track_commit_timestamp = off           # collect timestamp of transaction commit
# max_connections = 100                   # (change requires restart)
# #max_wal_senders = 0                    # max number of walsender processes
# #max_replication_slots = 0              # max number of replication slots
# #max_worker_processes = 8
#
cd /var/lib/pgsql/9.4-bdr/data
sed -i postgresql.conf -e "s/^#ssl = .*/ssl = on/"
sed -i postgresql.conf -e "s/^#ssl_ca_file = .*/ssl_ca_file = 'root.crt'/"
#
sed -i postgresql.conf -e "s/^#listen_addresses = .*/listen_addresses = '*'/"
sed -i postgresql.conf -e "s/^#shared_preload_libraries = .*/shared_preload_libraries = 'bdr'/"
sed -i postgresql.conf -e "s/^#wal_level = .*/wal_level = 'logical'/"
sed -i postgresql.conf -e "s/^#track_commit_timestamp = .*/track_commit_timestamp = on/"
sed -i postgresql.conf -e  "s/^max_connections = .*/max_connections = 100/"
sed -i postgresql.conf -e  "s/^#max_wal_senders = .*/max_wal_senders = 10/"
sed -i postgresql.conf -e  "s/^#max_replication_slots = .*/max_replication_slots = 48/"
sed -i postgresql.conf -e  "s/^#max_worker_processes = .*/max_worker_processes = 48/"

# Update hba.conf
#
chown -R postgres:postgres /var/lib/pgsql/9.4-bdr/data
cd /var/lib/pgsql/9.4-bdr/data
chmod 640 pg_hba.conf
cat > pg_hba.conf <<EOF
#
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             postgres                                trust
local   all             all                                     md5

# IPv4 local connections
host    all             postgres        127.0.0.1/32            trust
host    all             all             127.0.0.1/32            md5
#
hostssl all             postgres        127.0.0.1/32            trust
hostssl all             all             127.0.0.1/32            md5

# Allow replication connections from node1 and node2
# with the replication privilege
#
# bgworker: bdr supervisor
# bgworker: bdr db: fusionpbx
#
host    replication     postgres        127.0.0.1/32            trust
host    replication     all             $node1/32         trust
host    replication     all             $node2/32         trust
hostssl replication     postgres        127.0.0.1/32            trust
hostssl replication     all             $node1/32         trust
hostssl replication     all             $node2/32         trust
EOF

# Restart postgres
#
systemctl daemon-reload
systemctl restart postgresql-9.4
systemctl status postgresql-9.4 -l

# Configure PostgreSQL Synchronization at master node
#
# DROP USER bdrsync;
# CREATE USER bdrsync superuser;
# ALTER USER bdrsync WITH PASSWORD '12345#';
#
# SELECT bdr.bdr_node_join_wait_for_ready();
#
if [ "$this" == "$node1" ]; then
        local_node_name="node1_fusionpbx"
        that=$node2
		su - postgres -c "$PSQL --dbname=fusionpbx --echo-all" <<EOF
CREATE EXTENSION btree_gist;
CREATE EXTENSION bdr;
\dn
SELECT bdr.bdr_group_create(
        local_node_name := '$local_node_name',
        node_external_dsn := 'host=$this port=5432 dbname=fusionpbx'
);
EOF
else
        local_node_name="node2_fusionpbx"
        that=$node1
		su - postgres -c "$PSQL --dbname=fusionpbx --echo-all" <<EOF
CREATE EXTENSION btree_gist;
CREATE EXTENSION bdr;
\dn
SELECT bdr.bdr_group_join(
        local_node_name := '$local_node_name',
        node_external_dsn := 'host=$this port=5432 dbname=fusionpbx',
		join_using_dsn := 'host=$that port=5432 dbname=fusionpbx'
);
EOF
fi

# Check Synchronization
#
# looking for a result like this
# postgres@fusionpbx LOG: logical decoding found consistent point at 0/1FDDED8
# postgres@fusionpbx DETAIL: There are no running transactions.
#
egrep "consistent|transactions" /var/lib/pgsql/9.4-bdr/data/pg_log/postgresql-$(date +%a).log

# Verify BDR is installed
#
# Node Status
# The node status in bdr_nodes shows the status of the nodes. R = ready, I = initialize
#
su - postgres -c "$PSQL --dbname=fusionpbx --echo-all" <<EOF
SELECT bdr.bdr_variant();
SELECT bdr.bdr_version();

SELECT * from bdr.bdr_connections;
SELECT * FROM bdr.bdr_nodes;
EOF

# End of File
#
exit 0
