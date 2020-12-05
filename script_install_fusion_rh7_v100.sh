# autor: Carlos Frederico Liberato Lopes
# versao: 1.0.0
# data: 3/dez/2020

#!/bin/bash

# Cleanup
#
# -------------------------------------------------------------------------------------------------------------

cleanup() {
    yum remove -y nginx*
    yum remove -y memcached*
    yum remove -y php*
    yum remove -y postgres*
    yum remove -y freeswitch*
    yum remove -y fail2ban*

    yum remove -y htop openssl ghostscript libtiff-devel libtiff-tools libuuid libuuid-devel at

    rm -fr /var/log/nginx /var/cache/nginx /etc/nginx /usr/share/nginx
    rm -fr /run/freeswitch /var/log/freeswitch /var/lib/freeswitch /etc/security/limits.d/freeswitch /etc/freeswitch /usr/lib64/freeswitch /usr/share/freeswitch
    rm -fr /etc/fail2ban

    for i in nginx memcached php postgres freeswitch fail2ban; do find / -name $i -print; done

    yum-complete-transaction --cleanup-only
    yum clean all
    rpm --rebuilddb
    rm /var/lib/rpm/.dbenv.lock
    rm -rf /var/cache/yum
    sync; sync
    yum makecache fast
    yum repolist

    systemctl list-unit-files
    systemctl list-unit-files --state=enabled
    systemctl list-unit-files --state=running
}

# Pre-Install
#
# -----------------------------------------------------------------------------------------------------------------

preinstall() {
    # EPEL
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    yum reinstall -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    yum-config-manager --enable epel
    yum-config-manager --disable epel-debuginfo epel-source epel-testing epel-testing-debuginfo epel-testing-source

    # Update packages
    yum update -y

    # Basic Packages
    yum install -y yum-utils net-tools htop vim openssl nano
    yum install -y sudo wget curl git

    # NTP
    ln -sf /usr/share/zoneinfo/$TZONE /etc/localtime
    gwip=$(ip route show | grep default | cut -d\  -f3)
    cat > /etc/ntp.conf <<EOF
server 127.127.1.0
fudge 127.127.1.0 stratum 10
driftfile /var/lib/ntp/ntp.drift
leapfile /usr/share/zoneinfo/leapseconds

statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

# ip route show | grep default | cut -d\  -f3
server $gwip

restrict -4 default kod notrap nomodify nopeer noquery limited
restrict -4 127.0.0.1
restrict source notrap nomodify noquery
EOF

    # Set timezone
    timedatectl set-timezone $TZONE
    timedatectl

    # Recarregando as confs do ntpd
    systemctl daemon-reload
    systemctl start ntpd
    systemctl status ntpd -l
    netstat -alnp | egrep ":123|ntpd"

    # Show peers
    sleep 3
    ntpq -p
}

# Fusionpbx
#
# -----------------------------------------------------------------------------------------------------------------

fusionpbx() {
    # Dependencies
    yum install -y ghostscript libtiff-devel libtiff-tools libuuid libuuid-devel at lame

    # Support script
    cd /usr/src/
    rm -fr fusionpbx-install.sh
    git clone --progress --verbose https://github.com/fusionpbx/fusionpbx-install.sh.git
    #localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias eno_US.UTF-8

    # Freeswitch user: owner
    pkill -u freeswitch
    userdel -r freeswitch
    useradd -r -g daemon -s /sbin/nologin -c "The FreeSWITCH Open Source Voice Platform" -d /var/lib/freeswitch -m freeswitch
    passwd -l freeswitch

    # Fusionpbx
    FUSION_MAJOR=$(git ls-remote --heads https://github.com/fusionpbx/fusionpbx.git | cut -d/ -f 3 | grep -P '^\d+\.\d+' | sort | tail -n 1 | cut -d. -f1)
    FUSION_MINOR=$(git ls-remote --tags https://github.com/fusionpbx/fusionpbx.git $FUSION_MAJOR.* | cut -d/ -f3 |  grep -P '^\d+\.\d+' | sort | tail -n 1 | cut -d. -f2)
    FUSION_VERSION=$FUSION_MAJOR.$FUSION_MINOR
    BRANCH=""
    #BRANCH="-b $FUSION_VERSION"
    #
    rm -fr /var/www/fusionpbx
    git clone --progress --verbose $BRANCH https://github.com/fusionpbx/fusionpbx.git /var/www/fusionpbx
    chown -R freeswitch:daemon /var/www/fusionpbx

    # Cache directory
    mkdir -p /var/cache/fusionpbx
    chown -R freeswitch:daemon /var/cache/fusionpbx
}

# PostgreSQL - equivalentge ao snap2
#
# -----------------------------------------------------------------------------------------------------------------

postgresql() {
export PG_CLUSTER=main

    rpm --import https://dl.2ndquadrant.com/gpg-key.asc

    curl https://dl.2ndquadrant.com/default/release/get/bdr${PG_VER}/rpm | sudo bash
    yum-config-manager --enable 2ndquadrant-dl-default-release-pgbdr${PG_VER}/7Server/x86_64
    yum-config-manager --disable 2ndquadrant-dl-default-release-pgbdr${PG_VER}-debug/7Server/x86_64 2ndquadrant-dl-default-release-pgbdr${PG_VER}-source/7Server/x86_64

    rm -fr /var/lib/pgsql/${PG_VER}-bdr/data/
    yum install -y postgresql-bdr94 postgresql-bdr94-server postgresql-bdr94-contrib postgresql-bdr94-libs postgresql-bdr94-bdr
    /usr/pgsql-${PG_VER}/bin/postgresql94-setup initdb
    sed -i /var/lib/pgsql/${PG_VER}-bdr/data/pg_hba.conf -e 's/\(host  *all  *all  *127.0.0.1\/32  *\)ident/\1md5/'
    sed -i /var/lib/pgsql/${PG_VER}-bdr/data/pg_hba.conf -e 's/\(host  *all  *all  *::1\/128  *\)ident/\1md5/'

    systemctl daemon-reload
    systemctl start postgresql-${PG_VER}
    systemctl status postgresql-${PG_VER} -l
    netstat -alnp | egrep ":5432|postgres"

    superuser="superuser"
    #su - postgres -c "$PSQL --echo-queries" <<EOF
    su - postgres -c "$PSQL --echo-all" <<EOF
SELECT version();
show data_directory;
SELECT * FROM pg_available_extensions WHERE name ='bdr';
SELECT current_schema();
show search_path;

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
CREATE ROLE fusionpbx WITH SUPERUSER LOGIN PASSWORD '$superuser';
CREATE ROLE freeswitch WITH SUPERUSER LOGIN PASSWORD '$superuser';

GRANT ALL PRIVILEGES ON DATABASE fusionpbx to fusionpbx;
GRANT ALL PRIVILEGES ON DATABASE freeswitch to fusionpbx;
GRANT ALL PRIVILEGES ON DATABASE freeswitch to freeswitch;

\list
EOF
}

# NGINX
#
# -----------------------------------------------------------------------------------------------------------------

nginx() {
    rpm --import http://nginx.org/keys/nginx_signing.key
    cat > /etc/yum.repos.d/nginx.repo <<'EOF'
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/$releasever/$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
    yum-config-manager --enable nginx-stable
    yum-config-manager --disable nginx-mainline

    SUBJ="
C=BR
ST=RJ
O=empresa
localityName=Rio de Janeiro
commonName=sigla_empresa
organizationalUnitName=area_empresa
emailAddress=root@localhost
"
    mkdir -p -m 700 /etc/ssl/private
    mkdir -p -m 755 /etc/ssl/certs
    sed -i /etc/pki/tls/openssl.cnf -e 's/^RANDFILE/#RANDFILE/'
    openssl req -x509 -nodes -subj "$(echo -n "$SUBJ" | tr "\n" "/")" \
            -days 365 -newkey rsa:2048 -keyout "/etc/ssl/private/nginx.key" -out "/etc/ssl/certs/nginx.crt"

    yum --disablerepo=* --enablerepo=nginx-stable install -y nginx-1.16.1

    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    cp /usr/src/fusionpbx-install.sh/centos/resources/nginx/fusionpbx /etc/nginx/sites-available/fusionpbx.conf
    ln -sf /etc/nginx/sites-available/fusionpbx.conf /etc/nginx/sites-enabled/fusionpbx.conf

    sed -i /etc/nginx/sites-enabled/fusionpbx.conf -e '/ssl.*on/d'
    sed -i /etc/nginx/sites-enabled/fusionpbx.conf -e '/listen.*443/s/listen.*/listen 443 ssl;/'
    sed -i /etc/nginx/sites-enabled/fusionpbx.conf -e 's/server_name fusionpbx/server_name fusion/'
    if [ -z "$(grep fusion /etc/hosts)" ]; then
        sed -e '/^127/s/$/ fusion/' /etc/hosts > /etc/hosts.new

        # You cannot copy over /etc/hosts.
        # Docker provides the container with a custom /etc/hosts file.
        # You can overwrite this by using -v /some/file:/etc/hosts when creating the container.
        # You can also write to the file from inside the container.
        # You can also use the --add-host option when creating the container to add your own custom entries.
        mv /etc/hosts.new /etc/hosts

        cat /etc/hosts
    fi

    awk '/server *{/ {c=1 ; next} c && /{/{c++} c && /}/{c--;next} !c' /etc/nginx/nginx.conf > /etc/nginx/nginx.tmp && \
    mv -f /etc/nginx/nginx.tmp /etc/nginx/nginx.conf && rm -f /etc/nginx/nginx.tmp
    sed -i /etc/nginx/nginx.conf -e '/include \/etc\/nginx\/conf\.d\/\*\.conf\;/a \    include \/etc\/nginx\/sites-enabled\/\*\.conf\;'
    sed -i /etc/nginx/nginx.conf -e 's/user nginx/user freeswitch daemon/g'
    sed -i /etc/nginx/nginx.conf -e 's/pid \/run/pid \/var\/run/g'

    chmod -R 664 /var/log/nginx/

    systemctl daemon-reload
    systemctl start nginx
    systemctl status nginx -l
    netstat -alnp | egrep ":80|:443|nginx" | egrep -v "ESTABLISHED|_WAIT|SYN_"
}

# PHP
#
# -----------------------------------------------------------------------------------------------------------------

phpini() {
    yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum reinstall -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum-config-manager --enable remi remi-php72
    yum-config-manager --disable remi-debuginfo/x86_64 remi-glpi91 remi-glpi92 remi-glpi93 remi-glpi94 remi-modular remi-modular-test remi-php54 remi-php55 remi-php55-debuginfo/x86_64 remi-php56 remi-php56-debuginfo/x86_64 remi-php70 remi-php70-debuginfo/x86_64 remi-php70-test remi-php70-test-debuginfo/x86_64 remi-php71 remi-php71-debuginfo/x86_64 remi-php71-test remi-php71-test-debuginfo/x86_64 remi-php72-debuginfo/x86_64 remi-php72-test remi-php72-test-debuginfo/x86_64 remi-php73 remi-php73-debuginfo/x86_64 remi-php73-test remi-php73-test-debuginfo/x86_64 remi-php74 remi-php74-debuginfo/x86_64 remi-php74-test remi-php74-test-debuginfo/x86_64 remi-php80 remi-php80-debuginfo/x86_64 remi-php80-test remi-php80-test-debuginfo/x86_64 remi-safe remi-safe-debuginfo/x86_64 remi-test remi-test-debuginfo/x86_64
    yum --enablerepo=remi,remi-php72 install -y php-fpm php-pgsql php-curl php-opcache php-common php-pdo php-soap libargon2 php-odbc php-imap php-xml php-xmlrpc php-cli php-gd php-snmp

    if [ ! -d /etc/php-fpm.d.bkp ]; then
        cp -av /etc/php-fpm.d /etc/php-fpm.d.bkp
        cp /etc/php.ini /etc/php.ini.bkp
    fi

    sed -i /etc/php.ini -e "s#^.*date.timezone.*=.*#date.timezone = $TZONE#g"
    sed -i /etc/php.ini -e "s#^.*cgi.fix_pathinfo.*=.*#cgi.fix_pathinfo = 0#g"
    sed -i /etc/php.ini -e "s#^.*post_max_size.*=.*#post_max_size = 80M#g"
    sed -i /etc/php.ini -e "s#^.*upload_max_filesize.*=.*#upload_max_filesize = 80M#g"
    sed -i /etc/php.ini -e "s#^.*max_input_vars.*=.*#max_input_vars = 8000#g"

    sed -i /etc/php-fpm.d/www.conf -e "s#users.*=.*apache,nginx#users = nginx,nginx#g"
    sed -i /etc/php-fpm.d/www.conf -e "s#^.*user.*=.*apache#user = nginx#g"
    sed -i /etc/php-fpm.d/www.conf -e "s#^.*group.*=.*apache#group = nginx#g"
    sed -i /etc/php-fpm.d/www.conf -e "s#^.*listen.*=.*127.0.0.1:9000#listen = /var/run/php-fpm/php-fpm.sock#g"
    sed -i /etc/php-fpm.d/www.conf -e "s#^.*listen.*=.*/run/php/php7.2-fpm.sock#listen = /var/run/php-fpm/php-fpm.sock#g"
    sed -i /etc/php-fpm.d/www.conf -e "s#^.*listen\.owner.*=.*nobody#listen\.owner = nginx#g"
    sed -i /etc/php-fpm.d/www.conf -e "s#^.*listen\.group.*=.*nobody#listen\.group = nginx#g"

    sed -i /etc/php-fpm.conf -e "s#^.*pid.*#pid = /var/run/php-fpm/php-fpm.pid#g"

    mkdir -p /var/run/php-fpm/
    mkdir -p /var/lib/php/session
    rm -f /var/lib/php/session/*
    chmod -Rf 770 /var/lib/php/session

    find /var/www/fusionpbx -type d -exec chmod 775 {} \;
    find /var/www/fusionpbx -type f -exec chmod 664 {} \;

    systemctl daemon-reload
    systemctl start php-fpm
    systemctl status php-fpm -l
    netstat -alnp | egrep "fpm" | egrep -v "ESTABLISHED|_WAIT|SYN_"

    service nginx restart
    service nginx status -l
    netstat -alnp | egrep ":80|:443|nginx" | egrep -v "ESTABLISHED|_WAIT|SYN_"

    yum install -y memcached
    systemctl daemon-reload
    systemctl start memcached
    systemctl status memcached -l
    netstat -alnp | egrep ":11211|memcached" | egrep -v "ESTABLISHED|_WAIT|SYN_"
}

# Freeswitch
#
# -----------------------------------------------------------------------------------------------------------------

freeswitch() {
    yum install -y https://files.freeswitch.org/repo/yum/centos-release/freeswitch-release-repo-0-1.noarch.rpm
    yum reinstall -y https://files.freeswitch.org/repo/yum/centos-release/freeswitch-release-repo-0-1.noarch.rpm
    sed -ie 's#$releasever#7#g' /etc/yum.repos.d/freeswitch*.repo
    yum-config-manager --enable freeswitch
    yum-config-manager --disable freeswitch-debuginfo freeswitch-source

    yum install -y curl gdb spandsp
    #
    # freeswitch-freetdm
    #
    yum install -y --nogpgcheck freeswitch-config-vanilla
    yum install -y freeswitch-application-* freeswitch-codec-*
    yum install -y freeswitch-event-* freeswitch-format-*
    yum install -y freeswitch-lua freeswitch-xml-*
    yum install -y freeswitch-database-mariadb freeswitch-kazoo freeswitch-timer-posix
    yum install -y freeswitch-devel freeswitch-perl freeswitch-python
    yum install -y freeswitch-asrtts-* freeswitch-logger-* freeswitch-endpoint-*

    # Not installed: de, fr, he, ru, sv
    #
    # freeswitch-lang-de.x86_64 0:1.10.5.release.8-1.el7
    # freeswitch-lang-fr.x86_64 0:1.10.5.release.8-1.el7
    # freeswitch-lang-he.x86_64 0:1.10.5.release.8-1.el7
    # freeswitch-lang-ru.x86_64 0:1.10.5.release.8-1.el7
    # freeswitch-lang-sv.x86_64 0:1.10.5.release.8-1.el7
    #
    # Installed: en, es, pt
    #
    # freeswitch-lang-en-1.10.5.release.8-1.el7.x86_64
    # freeswitch-lang-es.x86_64 0:1.10.5.release.8-1.el7
    # freeswitch-lang-pt.x86_64 0:1.10.5.release.8-1.el7
    #
    yum install -y freeswitch-lang-{en,es,pt}*

    # Not installed: elena, june, jakob
    #
    # freeswitch-sounds-ru-RU-elena-8000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-ru-RU-elena-all-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-ru-RU-elena-48000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-ru-RU-elena-32000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-ru-RU-elena-16000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-ru-RU-elena-1.0.51-1.el7.centos.noarch
    #
    # freeswitch-sounds-en-ca-june-16000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-en-ca-june-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-en-ca-june-32000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-fr-ca-june-8000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-en-ca-june-48000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-fr-ca-june-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-en-ca-june-8000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-fr-ca-june-all-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-fr-ca-june-32000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-fr-ca-june-16000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-en-ca-june-all-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-fr-ca-june-48000-1.0.51-1.el7.centos.noarch
    #
    # freeswitch-sounds-sv-se-jakob-16000-1.0.50-1.el7.centos.noarch
    # freeswitch-sounds-sv-se-jakob-1.0.50-1.el7.centos.noarch
    # freeswitch-sounds-sv-se-jakob-32000-1.0.50-1.el7.centos.noarch
    # freeswitch-sounds-sv-se-jakob-8000-1.0.50-1.el7.centos.noarch
    # freeswitch-sounds-sv-se-jakob-all-1.0.50-1.el7.centos.noarch
    # freeswitch-sounds-sv-se-jakob-48000-1.0.50-1.el7.centos.noarch
    #
    # Installed: callie, allison, karina
    #
    # freeswitch-sounds-en-us-callie-all-1.0.52-1.el7.centos.noarch
    # freeswitch-sounds-en-us-callie-16000-1.0.52-1.el7.centos.noarch
    # freeswitch-sounds-en-us-callie-1.0.52-1.el7.centos.noarch
    # freeswitch-sounds-en-us-callie-8000-1.0.52-1.el7.centos.noarch
    # freeswitch-sounds-en-us-callie-48000-1.0.52-1.el7.centos.noarch
    # freeswitch-sounds-en-us-callie-32000-1.0.52-1.el7.centos.noarch
    #
    # freeswitch-sounds-en-us-allison-1.0.1-1.el7.centos.noarch
    # freeswitch-sounds-en-us-allison-16000-1.0.1-1.el7.centos.noarch
    # freeswitch-sounds-en-us-allison-48000-1.0.1-1.el7.centos.noarch
    # freeswitch-sounds-en-us-allison-all-1.0.1-1.el7.centos.noarch
    # freeswitch-sounds-en-us-allison-32000-1.0.1-1.el7.centos.noarch
    # freeswitch-sounds-en-us-allison-8000-1.0.1-1.el7.centos.noarch
    #
    # freeswitch-sounds-pt-BR-karina-48000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-pt-BR-karina-8000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-pt-BR-karina-16000-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-pt-BR-karina-all-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-pt-BR-karina-1.0.51-1.el7.centos.noarch
    # freeswitch-sounds-pt-BR-karina-32000-1.0.51-1.el7.centos.noarch
    #
    yum install -y freeswitch-sounds-*-callie-*
    yum install -y freeswitch-sounds-*-allison-*
    yum install -y freeswitch-sounds-*-karina-*

    yum install -y freeswitch-sounds-music*
    if [ ! -d /usr/share/freeswitch/sounds/music/default ]; then
        # Installed: 8000, 16000, 32000, 48000
        #
        # freeswitch-sounds-music-8000    /usr/share/freeswitch/sounds/music/8000
        # freeswitch-sounds-music-16000    /usr/share/freeswitch/sounds/music/16000
        # freeswitch-sounds-music-32000    /usr/share/freeswitch/sounds/music/32000
        # freeswitch-sounds-music-48000    /usr/share/freeswitch/sounds/music/48000

        mkdir -p /usr/share/freeswitch/sounds/music/default
        mv /usr/share/freeswitch/sounds/music/{8000,16000,32000,48000} /usr/share/freeswitch/sounds/music/default
    fi

    [ ! -d /etc/freeswitch.orig ] && mv /etc/freeswitch /etc/freeswitch.orig
    rm -fr /etc/freeswitch
    mkdir /etc/freeswitch
    cp -av /var/www/fusionpbx/resources/templates/conf/* /etc/freeswitch

    mkdir -p /var/lib/freeswitch
    chown -R freeswitch:daemon /etc/freeswitch
    chown -R freeswitch:daemon /var/lib/freeswitch
    chown -R freeswitch:daemon /usr/share/freeswitch
    chown -R freeswitch:daemon /var/log/freeswitch
    chown -R freeswitch:daemon /var/run/freeswitch

    rm -f /lib/systemd/system/freeswitch.service
    cp /usr/src/fusionpbx-install.sh/centos/resources/switch/source/freeswitch.service.package /lib/systemd/system/freeswitch.service
    cp /usr/src/fusionpbx-install.sh/centos/resources/switch/source/etc.default.freeswitch /etc/sysconfig/freeswitch

    sed -i /lib/systemd/system/freeswitch.service -e "s:^IOSchedulingClass=:#IOSchedulingClass=:g"
    sed -i /lib/systemd/system/freeswitch.service -e "s:^IOSchedulingPriority=:#IOSchedulingPriority=:g"
    sed -i /lib/systemd/system/freeswitch.service -e "s:^CPUSchedulingPolicy=:#CPUSchedulingPolicy=:g"
    sed -i /lib/systemd/system/freeswitch.service -e "s:^CPUSchedulingPriority=:#CPUSchedulingPriority=:g"

    cat > /etc/security/limits.d/freeswitch <<EOF
freeswitch       soft    core            unlimited
freeswitch       soft    data            unlimited
freeswitch       soft    fsize           unlimited
freeswitch       soft    memlock         unlimited
freeswitch       soft    nofile          999999
freeswitch       soft    rss             unlimited
freeswitch       hard    stack           240
freeswitch       soft    cpu             unlimited
freeswitch       soft    nproc           unlimited
freeswitch       soft    as              unlimited
freeswitch       soft    priority        -11
freeswitch       soft    locks           unlimited
freeswitch       soft    sigpending      unlimited
freeswitch       soft    msgqueue        unlimited
freeswitch       soft    nice            -11
EOF

    chown -Rf freeswitch.daemon /var/www/fusionpbx
    chown -Rf freeswitch:daemon /var/lib/nginx
    chown -Rf freeswitch:daemon /var/lib/php/session

    chown -Rf freeswitch.daemon /var/lib/freeswitch
    chown -Rf freeswitch.daemon /var/log/freeswitch
    chown -Rf freeswitch.daemon /usr/share/freeswitch
    chown -Rf freeswitch.daemon /etc/freeswitch

    find /var/lib/freeswitch -type d -exec chmod 770 {} \;
    find /var/log/freeswitch -type d -exec chmod 770 {} \;
    find /usr/share/freeswitch -type d -exec chmod 770 {} \;
    find /etc/freeswitch -type d -exec chmod 770 {} \;

    find /var/lib/freeswitch -type f -exec chmod 664 {} \;
    find /var/log/freeswitch -type f -exec chmod 664 {} \;
    find /usr/share/freeswitch -type f -exec chmod 664 {} \;
    find /etc/freeswitch -type f -exec chmod 664 {} \;

    usermod -a -G daemon nginx
    usermod -a -G nginx freeswitch

    systemctl daemon-reload
    systemctl start freeswitch
    systemctl status freeswitch -l
    netstat -alnp | egrep ":8021|freeswitch" | egrep -v "ESTABLISHED|_WAIT|SYN_"
}

# Failban
#
# -----------------------------------------------------------------------------------------------------------------

failban() {
export FLAVOR=ubuntu

    yum install -y fail2ban
    cd /usr/src/fusionpbx-install.sh/${FLAVOR}/resources/fail2ban/

    cp auth-challenge-ip.conf /etc/fail2ban/filter.d/
    #cp freeswitch-dos.conf /etc/fail2ban/filter.d/
    cp freeswitch.conf /etc/fail2ban/filter.d/
    cp freeswitch-ip.conf /etc/fail2ban/filter.d/
    cp fusionpbx-404.conf /etc/fail2ban/filter.d/
    cp fusionpbx.conf /etc/fail2ban/filter.d/
    cp fusionpbx-mac.conf /etc/fail2ban/filter.d/
    #cp jail.local /etc/fail2ban/
    cp nginx-404.conf /etc/fail2ban/filter.d/
    cp nginx-dos.conf /etc/fail2ban/filter.d/
    cp sip-auth-challenge.conf /etc/fail2ban/filter.d/
    cp sip-auth-failure.conf /etc/fail2ban/filter.d/

    mkdir -p /var/run/fail2ban
    chown freeswitch:daemon /var/run/fail2ban

    systemctl daemon-reload
    systemctl restart fail2ban
    systemctl status fail2ban -l
    netstat -alnp | egrep "fail2ban" | egrep -v "ESTABLISHED|_WAIT|SYN_"
}

# Auth
#
# -----------------------------------------------------------------------------------------------------------------

auth() {
    #
    # Set fusionpbx auth
    #
    user_name='admin'
    user_password='XpTo@2020'
    #
    # Set fusionpbx database auth
    #
    database_host=127.0.0.1
    database_port=5432
    database_username='fusionpbx'
    database_password='fusionpbx'
    #
    PSQL_PBX="PGPASSWORD=$database_password $PSQL --host=$database_host --port=$database_port --username=$database_username --echo-all"

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
    mkdir -m 775 -p /etc/fusionpbx
    chown -R freeswitch:daemon /etc/fusionpbx
    cp /usr/src/fusionpbx-install.sh/ubuntu/resources/fusionpbx/config.php /etc/fusionpbx

    sed -i /etc/fusionpbx/config.php -e "s#{database_host}#$database_host#"
    sed -i /etc/fusionpbx/config.php -e "s#{database_port}#$database_port#"
    sed -i /etc/fusionpbx/config.php -e "s#{database_username}#$database_username#"
    sed -i /etc/fusionpbx/config.php -e "s#{database_password}#$database_password#"

    #
    # Update database schema
    #
    cd /var/www/fusionpbx
    php /var/www/fusionpbx/core/upgrade/upgrade_schema.php > /dev/null 2>&1

    #
    # Create domain using IPADDR
    #
    domain_name=$(hostname -I | cut -d ' ' -f1)
    domain_uuid=$(php /var/www/fusionpbx/resources/uuid.php);
    #
    sudo -u postgres $PSQL fusionpbx --echo-all -t -c "INSERT INTO v_domains (domain_uuid, domain_name, domain_enabled) VALUES ('$domain_uuid', '$domain_name', 'true');"

    #
    # Update domain
    #
    cd /var/www/fusionpbx
    php /var/www/fusionpbx/core/upgrade/upgrade_domains.php

    #
    # Create user 'admin' with password
    #
    user_uuid=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
    user_salt=$(/usr/bin/php /var/www/fusionpbx/resources/uuid.php);
    password_hash=$(php -r "echo md5('$user_salt$user_password');");
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
}

# freeswitch-mod_g729
#
# -----------------------------------------------------------------------------------------------------------------

mod_g729() {
    # https://groups.google.com/g/astpp/c/JL35Gl9fR-g

    yum install -y freeswitch-devel autoconf automake libtool

    cd /usr/src/
    rm -fr mod_bcg729
    git clone https://github.com/xadhoom/mod_bcg729.git
    cd mod_bcg729
    sed -i Makefile -e 's\^FS_INCLUDES.*\FS_INCLUDES=/usr/include/\'
    sed -i Makefile -e 's\^FS_MODULES.*\FS_MODULES=/usr/lib64/freeswitch/mod/\'
    make
    make install
    strip `fs_cli -x 'global_getvar mod_dir'`/mod_bcg729.o
    sed -i /etc/freeswitch/autoload_configs/modules.conf.xml -e 's|mod_g729\+|mod_bcg729|g'

    fs_cli -x "unload mod_g729"
    fs_cli -x 'module_exists mod_g729'
    fs_cli -x "load mod_bcg729"
    fs_cli -x 'module_exists mod_bcg729'
}

# freeswitch-mod_prometheus
#
# -----------------------------------------------------------------------------------------------------------------

mod_prometheus() {
    # https://pt.slideshare.net/MoisesSilva6/freeswitch-monitoring

    yum install -y rustc cargo
    rustc -V || curl -sSf https://static.rust-lang.org/rustup.sh | sh

    cd /usr/src
    rm -fr mod_prometheus
    git clone --progress --verbose https://github.com/moises-silva/mod_prometheus

    cd mod_prometheus
    cargo build
    strip target/debug/libmod_prometheus.so
    cp target/debug/libmod_prometheus.so `fs_cli -x 'global_getvar mod_dir'`/mod_prometheus.so

    if [ ! -f /etc/freeswitch/autoload_configs/modules.conf.xml.orig ]; then
        cp /etc/freeswitch/autoload_configs/modules.conf.xml /etc/freeswitch/autoload_configs/modules.conf.xml.orig
    fi
    sed /etc/freeswitch/autoload_configs/modules.conf.xml -e '/\/modules/,$d' > /tmp/modules.conf.xml
    cat >> /tmp/modules.conf.xml <<EOF
                <load module="mod_prometheus"/>

        </modules>
</configuration>
EOF
    mv /tmp/modules.conf.xml /etc/freeswitch/autoload_configs/modules.conf.xml

    fs_cli -x "load mod_prometheus"
    fs_cli -x 'module_exists mod_prometheus'
    netstat -alnp | egrep ":9282" | egrep -v "ESTABLISHED|_WAIT|SYN_"
    curl -v http://127.0.0.1:9282/metrics
}

# tftpd
#
# -----------------------------------------------------------------------------------------------------------------

tftpd() {
    # https://freeswitch.org/confluence/display/FREESWITCH/Cisco+7960+SIP
    # http://pnijjar.freeshell.org/2015/fusionpbx-tftp/

    yum install -y tftp tftp-server

    mkdir -p /var/lib/tftpboot
    chown -R nginx /var/lib/tftpboot

    cd /var/lib/tftpboot
    mkdir -p cisco-7941
    cp /tmp/cisco-firmware/* /var/lib/tftpboot/cisco-7941
    ln -s cisco-7941/* .

    systemctl start tftp.service
    systemctl status tftp.service -l
    netstat -alnp | egrep ":69|tftp" | egrep -v "ESTABLISHED|_WAIT|SYN_"
}

# sshd
#
# -----------------------------------------------------------------------------------------------------------------

sshd() {
    # http://pnijjar.freeshell.org/2015/fusionpbx-tftp/

    yum install -y openssh-server

    sed -i /etc/ssh/sshd_config -e "s/^#Port.*/Port 22/g"
    sed -i /etc/ssh/sshd_config -e "s/^#ListenAddress.*0.0.0.0/ListenAddress 0.0.0.0/g"
    sed -i /etc/ssh/sshd_config -e "s/^#ListenAddress.*::/ListenAddress ::/g"
    sed -i /etc/ssh/sshd_config -e "s/^#PermitRootLogin.*no/PermitRootLogin yes/g"

    systemctl start sshd
    systemctl status sshd -l
    netstat -alnp | egrep ":22|ssh" | egrep -v "ESTABLISHED|_WAIT|SYN_"
}

# postinstall
#
# -----------------------------------------------------------------------------------------------------------------

postinstall() {
    systemctl daemon-reload
    systemctl mask wpa_supplicant.service
    systemctl stop wpa_supplicant.service

    systemctl enable ntpd
    systemctl enable nginx
    systemctl enable memcached
    systemctl enable php-fpm
    systemctl enable postgresql-${PG_VER}
    systemctl enable freeswitch
    systemctl disable fail2ban
    systemctl enable sshd

    systemctl restart ntpd
    systemctl restart nginx
    systemctl restart memcached
    systemctl restart php-fpm
    systemctl restart postgresql-${PG_VER}
    systemctl restart freeswitch
    systemctl stop fail2ban
    systemctl restart sshd

    systemctl status ntpd -l
    systemctl status nginx -l
    systemctl status memcached -l
    systemctl status php-fpm -l
    systemctl status postgresql-${PG_VER} -l
    systemctl status freeswitch -l
    systemctl status fail2ban -l
    systemctl status sshd -l
}

# Versions
#
# -----------------------------------------------------------------------------------------------------------------

versions() {
    hostname -f
    echo Kernel $(uname -r)
    echo

    echo FusionPBX $(cd /var/www/fusionpbx; find . -type f -name '*.php' -exec grep "return .4\." {} ";" | cut -d\' -f2)
    echo Nginx $(/usr/sbin/nginx -v 2>&1 | head -1 | cut -d/ -f2-)
    echo Memcached $(/usr/bin/memcached -h | head -1 | cut -d' ' -f2)
    echo PHP $(/usr/bin/php --version | head -1 | cut -d' ' -f2)
    echo PostgreSQL $(/usr/pgsql-9.4/bin/postgres --version | head -1 | cut -d' ' -f3-)
    echo FreeSWITCH $(/usr/bin/freeswitch -version | head -1 | cut -d' ' -f3)
    echo Fail2ban $(/usr/bin/fail2ban-server --version | head -1 | cut -d' ' -f2)
    echo
    netstat -atulnp | egrep -v "ESTABLISHED|_WAIT|SYN_"
}

# main
#
# -----------------------------------------------------------------------------------------------------------------

#set -x
cleanup
preinstall
    fusionpbx
    postgresql
    nginx
    phpini
    freeswitch
    failban
    auth
    mod_g729
    mod_prometheus
    #tftpd
    #sshd
postinstall
versions
exit 0
