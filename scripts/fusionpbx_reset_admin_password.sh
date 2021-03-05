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

#
# Set fusionpbx auth
#
user_name='fred'
user_password='flintstone'
group_name='superadmin'

#
# Get domain
#
domain_name=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT domain_name FROM v_domains" | grep `hostname`)
domain_name=$(echo $domain_name | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
domain_uuid=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT domain_uuid FROM v_domains")
domain_uuid=$(echo $domain_uuid | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
echo "$domain_name|$domain_uuid|"

#
# Create user with password
#
user_uuid=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT user_uuid FROM v_users WHERE username = '$user_name';")
user_uuid=$(echo $user_uuid | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
if [ -z "$user_uuid" ]; then
	user_uuid=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
	user_salt=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
else
	user_salt=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT salt FROM v_users WHERE user_uuid = '$user_uuid';")
	user_salt=$(echo $user_salt | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
fi
#password_hash=$(php -r "echo md5('$user_salt' . '$user_password');")
user_salt=""
password_hash=$(php -r "echo password_hash('$user_password', PASSWORD_BCRYPT, array('cost' => 10));")

#
sudo -u postgres $PSQL fusionpbx --echo-all -t -c "DELETE FROM v_users WHERE user_uuid = '$user_uuid';"
sudo -u postgres $PSQL fusionpbx --echo-all -t -c "INSERT INTO v_users (user_uuid, domain_uuid, username, password, salt, user_enabled) VALUES ('$user_uuid', '$domain_uuid', '$user_name', '$password_hash', '$user_salt', 'true');"
sudo -u postgres $PSQL fusionpbx --echo-all -c "SELECT * FROM v_users;"

#
# Associate user to group 'superadmin'
#
group_uuid=$(sudo -u postgres $PSQL fusionpbx -t -c "SELECT group_uuid FROM v_groups WHERE group_name = '$group_name';");
group_uuid=$(echo $group_uuid | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
user_group_uuid=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
#
sudo -u postgres $PSQL fusionpbx --echo-all -c "DELETE FROM v_user_groups WHERE user_uuid = '$user_uuid';"
sudo -u postgres $PSQL fusionpbx --echo-all -t -c "INSERT INTO v_user_groups (user_group_uuid, domain_uuid, group_name, group_uuid, user_uuid) VALUES ('$user_group_uuid', '$domain_uuid', '$group_name', '$group_uuid', '$user_uuid');"
sudo -u postgres $PSQL fusionpbx --echo-all -c "SELECT * FROM v_user_groups;"
