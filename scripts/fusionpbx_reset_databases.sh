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

export PG_VER=9.4
export PATH=$PATH:/usr/lib/postgresql/${PG_VER}/bin
export PSQL=/usr/pgsql-${PG_VER}/bin/psql

systemctl status postgresql-9.4 -l
netstat -atlnup | grep postgres

su - postgres -c "$PSQL --echo-all" <<EOF
SELECT version();
SHOW data_directory;
SELECT * FROM pg_available_extensions WHERE name ='bdr';
SELECT current_schema();
SHOW search_path;

\list

DROP DATABASE IF EXISTS fusionpbx;
DROP DATABASE IF EXISTS freeswitch;
CREATE DATABASE fusionpbx;
CREATE DATABASE freeswitch;

\connect fusionpbx
DROP SCHEMA public cascade;
CREATE SCHEMA public;
\connect postgres

DROP ROLE fusionpbx;
DROP ROLE freeswitch;
CREATE ROLE fusionpbx WITH SUPERUSER LOGIN PASSWORD 'Admin@2021';
CREATE ROLE freeswitch WITH SUPERUSER LOGIN PASSWORD 'Admin@2021';

GRANT ALL PRIVILEGES ON DATABASE fusionpbx to fusionpbx;
GRANT ALL PRIVILEGES ON DATABASE freeswitch to fusionpbx;
GRANT ALL PRIVILEGES ON DATABASE freeswitch to freeswitch;

\list
EOF

#
# Set fusionpbx auth
#
user_name='admin'
user_password='Admin@2021'

#
database_host=127.0.0.1
database_port=5432
database_username='fusionpbx'
database_password='Admin@2021'
#
PSQL="PGPASSWORD=$database_password $PSQL --host=$database_host --port=$database_port --username=$database_username"

#
# Update fusionpbx auth in PostgreSQL
#
su - postgres -c "$PSQL --echo-all" <<EOF
ALTER USER fusionpbx WITH PASSWORD '$database_password';
ALTER USER freeswitch WITH PASSWORD '$database_password';
EOF

#
# Update fusionpbx auth in PHP
#
cp /usr/src/fusionpbx-install.sh/ubuntu/resources/fusionpbx/config.php /etc/fusionpbx

sed -i /etc/fusionpbx/config.php -e "s#{database_host}#$database_host#"
sed -i /etc/fusionpbx/config.php -e "s#{database_port}#$database_port#"
sed -i /etc/fusionpbx/config.php -e "s#{database_username}#$database_username#"
sed -i /etc/fusionpbx/config.php -e "s#{database_password}#$database_password#"

#
# Update database schema (after database created and before create domain)
#
cd /var/www/fusionpbx
php /var/www/fusionpbx/core/upgrade/upgrade_schema.php > /dev/null 2>&1

#
# Create domain using IPADDR
#
domain_name=$(hostname -f)
domain_uuid=$(php /var/www/fusionpbx/resources/uuid.php);
#
sudo -u postgres $PSQL fusionpbx --echo-all -t -c "INSERT INTO v_domains (domain_uuid, domain_name, domain_enabled) VALUES ('$domain_uuid', '$domain_name', 'true');"

#
# Update domain (after create domain and before create group superadmin)
#
cd /var/www/fusionpbx
php /var/www/fusionpbx/core/upgrade/upgrade_domains.php

#
# Create user 'admin' with password
#
user_uuid=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
#user_salt=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
#password_hash=$(php -r "echo md5('$user_salt$user_password');");
user_salt=""
password_hash=$(php -r "echo password_hash('$user_password', PASSWORD_BCRYPT, array('cost' => 10));")
#
sudo -u postgres $PSQL fusionpbx --echo-all -t -c "INSERT INTO v_users (user_uuid, domain_uuid, username, password, salt, user_enabled) VALUES ('$user_uuid', '$domain_uuid', '$user_name', '$password_hash', '$user_salt', 'true');"

#
# Create group 'superadmin'
#
group_name=superadmin
group_uuid=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT group_uuid FROM v_groups WHERE group_name = '$group_name';");
group_uuid=$(echo $group_uuid | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
user_group_uuid=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
#
sudo -u postgres $PSQL fusionpbx --echo-all -t -c "INSERT INTO v_user_groups (user_group_uuid, domain_uuid, group_name, group_uuid, user_uuid) VALUES ('$user_group_uuid', '$domain_uuid', '$group_name', '$group_uuid', '$user_uuid');"

#
# Set CDR vars
#        
xml_cdr_username=$(dd if=/dev/urandom bs=1 count=12 2>/dev/null | base64 | sed 's/[=\+//]//g')
xml_cdr_password=$(dd if=/dev/urandom bs=1 count=12 2>/dev/null | base64 | sed 's/[=\+//]//g')
       
sed -i /etc/freeswitch/autoload_configs/xml_cdr.conf.xml -e "s#{v_http_protocol}#http#"
sed -i /etc/freeswitch/autoload_configs/xml_cdr.conf.xml -e "s#{domain_name}#127.0.0.1#"
sed -i /etc/freeswitch/autoload_configs/xml_cdr.conf.xml -e "s#{v_project_path}##"
sed -i /etc/freeswitch/autoload_configs/xml_cdr.conf.xml -e "s#{v_user}#$xml_cdr_username#"
sed -i /etc/freeswitch/autoload_configs/xml_cdr.conf.xml -e "s#{v_pass}#$xml_cdr_password#"

#
# Update domain (after create group superadmin --> create /usr/share/freeswitch/scripts/*)
#
cd /var/www/fusionpbx
php /var/www/fusionpbx/core/upgrade/upgrade_domains.php
