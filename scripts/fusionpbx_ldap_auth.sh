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

### Install mod_ldap if necessary ###########################################################

if [ $(php -m | grep ldap) != "ldap" ]; then
	yum --enablerepo=remi,remi-php72 install -y php-ldap
fi

### Update Default Settings #################################################################

#
# postgres=# \c fusionpbx
# You are now connected to database "fusionpbx" as user "postgres".
# fusionpbx=# \d+ v_default_settings
#                              Table "public.v_default_settings"
#            Column            |  Type   | Modifiers | Storage  | Stats target | Description
# -----------------------------+---------+-----------+----------+--------------+-------------
#  default_setting_uuid        | uuid    | not null  | plain    |              |
#  app_uuid                    | uuid    |           | plain    |              |
#  default_setting_category    | text    |           | extended |              |
#  default_setting_subcategory | text    |           | extended |              |
#  default_setting_name        | text    |           | extended |              |
#  default_setting_value       | text    |           | extended |              |
#  default_setting_order       | numeric |           | main     |              |
#  default_setting_enabled     | boolean |           | plain    |              |
#  default_setting_description | text    |           | extended |              |
# Indexes:
#     "v_default_settings_pkey" PRIMARY KEY, btree (default_setting_uuid)
#

# Create new uuids to Authentication and LDAP categories
auth_uuid=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
ldap_uuid=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);

# Start SQL Commands File
rm -f /tmp/sqlcmds
echo -e "DELETE FROM v_default_settings WHERE default_setting_category = 'authentication';\n" >> /tmp/sqlcmds
echo -e "DELETE FROM v_default_settings WHERE default_setting_category = 'ldap';\n" >> /tmp/sqlcmds

# Create each subcategory
echo "authentication|methods|array|database|000|true
authentication|methods|array|ldap|000|true
ldap|base_dn|text|cn=Users,dc=xyz,dc=com|000|true
ldap|bind_password|text|senha#0|000|true
ldap|bind_username|text|XYZ\\\\user|000|true
ldap|enabled|boolean|true|000|true
ldap|filter|text|(sAMAccountName=*)|000|true
ldap|server_host|text|ldap.xyz.com|000|true
ldap|server_port|numeric|389|000|true
ldap|user_attribute|text|cn|000|true
ldap|user_dn|array|cn=Users,dc=xyz,dc=com|000|true" | \
while read line; do
        set xx `echo $line | tr '|' ' '`; shift

        default_setting_uuid=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
        default_setting_category=$1; shift

	if [ "default_setting_category" == "ldap" ]; then
		app_uuid=$ldap_uuid
	else
		app_uuid=$auth_uuid
	fi

        default_setting_subcategory=$1; shift
        default_setting_name=$1; shift
        default_setting_value=$1; shift
        default_setting_order=$1; shift
        default_setting_enabled=$1; shift
        default_setting_description=""

echo -e "INSERT INTO v_default_settings (
        default_setting_uuid,
	app_uuid,
        default_setting_category,
        default_setting_subcategory,
        default_setting_name,
        default_setting_value,
        default_setting_order,
        default_setting_enabled,
        default_setting_description
) VALUES (
        '$default_setting_uuid',
        '$app_uuid',
        '$default_setting_category',
        '$default_setting_subcategory',
        '$default_setting_name',
        '$default_setting_value',
        '$default_setting_order',
        '$default_setting_enabled',
        null
);\n"
done >> /tmp/sqlcmds
echo -e "SELECT * FROM v_default_settings WHERE default_setting_category = 'authentication';\n" >> /tmp/sqlcmds
echo -e "SELECT * FROM v_default_settings WHERE default_setting_category = 'ldap';\n" >> /tmp/sqlcmds
echo -e "SELECT * FROM v_groups;\n" >> /tmp/sqlcmds

# Execute SQL Commands
su - postgres -c "$PSQL --echo-all fusionpbx < /tmp/sqlcmds"
rm -f sqlcmds

### Update ldap.php #########################################################################

# 
# fusionpbx=# \d+ v_groups
#                              Table "public.v_groups"
#       Column       |  Type   | Modifiers | Storage  | Stats target | Description
# -------------------+---------+-----------+----------+--------------+-------------
#  group_uuid        | uuid    | not null  | plain    |              |
#  domain_uuid       | uuid    |           | plain    |              |
#  group_name        | text    |           | extended |              |
#  group_protected   | text    |           | extended |              |
#  group_level       | numeric |           | main     |              |
#  group_description | text    |           | extended |              |
# Indexes:
#     "v_groups_pkey" PRIMARY KEY, btree (group_uuid)
# 
# fusionpbx=# SELECT * FROM v_groups;
#               group_uuid              | domain_uuid | group_name | group_protected | group_level |     group_description
# --------------------------------------+-------------+------------+-----------------+-------------+---------------------------
#  554829fa-9c84-4d64-bf86-8278a6e152dc |             | superadmin | false           |          80 | Super Administrator Group
#  3ba4f338-0e3c-4c76-a0a6-1d8db487658d |             | admin      | false           |          50 | Administrator Group
#  d8edf7d0-a8d7-4a85-b017-384b35509b89 |             | user       | false           |          30 | User Group
#  70cba8db-9cd9-4e91-bd25-d98145e61670 |             | agent      | false           |          20 | Call Center Agent Group
#  b75abed0-b485-4c94-a181-1bd07c6d24ce |             | public     | false           |          10 | Public Group
# (5 rows)
# 

# Get current group uuids
group_superadmin_uuid=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT group_uuid FROM v_groups WHERE group_name = 'superadmin';");
group_admin_uuid=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT group_uuid FROM v_groups WHERE group_name = 'admin';");
group_user_uuid=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT group_uuid FROM v_groups WHERE group_name = 'user';");
#
group_superadmin_uuid=$(echo $group_superadmin_uuid | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
group_admin_uuid=$(echo $group_admin_uuid | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
group_user_uuid=$(echo $group_user_uuid | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')

# Update ldap.php
cp ldap.php.auth /tmp/ldap.php
cd /var/www/fusionpbx/core/authentication/resources/classes/plugins
[ ! -f ldap.php.orig ] && cp ldap.php ldap.php.orig
cp /tmp/ldap.php .

# Update group uuid into ldap.php
sed -i ldap.php -e "s/0aa2be95-5d52-4bf7-8130-3dbd9794e132/$group_superadmin_uuid/g"
sed -i ldap.php -e "s/d917ba57-bfbe-4c65-94ee-e33a1703f8a7/$group_admin_uuid/g"
sed -i ldap.php -e "s/068a3e27-cbf3-4c50-aa14-58074c29c769/$group_user_uuid/g"

### Cleanup old sessions ####################################################################

rm -f /var/lib/php/session/*

exit 0
