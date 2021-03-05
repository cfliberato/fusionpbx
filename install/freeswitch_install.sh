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

export TZONE=America/Sao_Paulo
#export LC_ALL=C.UTF-8
export PG_VER=9.4
export PATH=$PATH:/usr/lib/postgresql/${PG_VER}/bin
export PSQL=/usr/pgsql-${PG_VER}/bin/psql

unalias cp > /dev/null 2>&1
unalias mv > /dev/null 2>&1
unalias rm > /dev/null 2>&1

# Cleanup
#
# -----------------------------------------------------------------------------------------------------------------

cleanup() {
    yum remove -y postgres*
    yum remove -y freeswitch*
    yum list installed | grep freeswitch | cut -d\  -f1 | sed -e '/^$/d' | xargs yum remove -y
    yum list installed | egrep -v "@rhel|@epel|@anaconda|@rhn-tools|@/katello"

    rm -fr /run/freeswitch /var/log/freeswitch /var/lib/freeswitch /etc/security/limits.d/freeswitch /etc/freeswitch* /usr/lib64/freeswitch /usr/share/freeswitch
    rm -fr /var/lib/pgsql

    for i in postgres freeswitch; do find / -name $i -print; done

    yum-complete-transaction --cleanup-only
    yum clean all
    rpm --rebuilddb
    rm -f /var/lib/rpm/.dbenv.lock
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
    yum install -y mlocate bzip2 nc

    # FreeSWITCH Devel Packages
    yum install -y ilbc-devel
        
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

    # Support script
    cd /usr/src/
    rm -fr fusionpbx-install.sh
    git clone --progress --verbose https://github.com/fusionpbx/fusionpbx-install.sh.git
    #localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias eno_US.UTF-8

    # Freeswitch user: owner
    pkill -u freeswitch > /dev/null 2>&1
    userdel -r freeswitch > /dev/null 2>&1
    useradd -r -g daemon -s /sbin/nologin -c "The FreeSWITCH Open Source Voice Platform" -d /var/lib/freeswitch -m freeswitch
    passwd -l freeswitch

}

# PostgreSQL - equivalente ao snap2
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

# Freeswitch
#
# -----------------------------------------------------------------------------------------------------------------

freeswitch() {
    yum install -y https://files.freeswitch.org/repo/yum/centos-release/freeswitch-release-repo-0-1.noarch.rpm
    yum reinstall -y https://files.freeswitch.org/repo/yum/centos-release/freeswitch-release-repo-0-1.noarch.rpm
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
	# [root@vrt1954 ~]# rpm -qa | egrep "(8000|16000|32000|48000)" | sort
	# freeswitch-sounds-en-us-allison-16000-1.0.1-1.el7.centos.noarch
	# freeswitch-sounds-en-us-allison-32000-1.0.1-1.el7.centos.noarch
	# freeswitch-sounds-en-us-allison-48000-1.0.1-1.el7.centos.noarch
	# freeswitch-sounds-en-us-allison-8000-1.0.1-1.el7.centos.noarch
	# freeswitch-sounds-en-us-callie-16000-1.0.52-1.el7.centos.noarch
	# freeswitch-sounds-en-us-callie-32000-1.0.52-1.el7.centos.noarch
	# freeswitch-sounds-en-us-callie-48000-1.0.52-1.el7.centos.noarch
	# freeswitch-sounds-en-us-callie-8000-1.0.52-1.el7.centos.noarch
	# freeswitch-sounds-pt-BR-karina-16000-1.0.51-1.el7.centos.noarch
	# freeswitch-sounds-pt-BR-karina-32000-1.0.51-1.el7.centos.noarch
	# freeswitch-sounds-pt-BR-karina-48000-1.0.51-1.el7.centos.noarch
	# freeswitch-sounds-pt-BR-karina-8000-1.0.51-1.el7.centos.noarch
        mkdir -p /usr/share/freeswitch/sounds/music/default
        # mv /usr/share/freeswitch/sounds/music/{8000,16000,32000,48000} /usr/share/freeswitch/sounds/music/default
    fi

    [ ! -d /etc/freeswitch.orig ] && cp -av /etc/freeswitch /etc/freeswitch.orig

    mkdir -p /var/lib/freeswitch
    chown -R freeswitch:daemon /etc/freeswitch
    chown -R freeswitch:daemon /var/lib/freeswitch
    chown -R freeswitch:daemon /usr/share/freeswitch
    chown -R freeswitch:daemon /var/log/freeswitch
    chown -R freeswitch:daemon /var/run/freeswitch

    sed -i /lib/systemd/system/freeswitch.service -e 's|^[[:blank:]]*\(IOSchedulingClass\)[[:blank:]]*=|#IOSchedulingClass=|g'
    sed -i /lib/systemd/system/freeswitch.service -e 's|^[[:blank:]]*\(IOSchedulingPriority\)[[:blank:]]*=|#IOSchedulingPriority=|g'
    sed -i /lib/systemd/system/freeswitch.service -e 's|^[[:blank:]]*\(CPUSchedulingPolicy\)[[:blank:]]*=|#CPUSchedulingPolicy=|g'
    sed -i /lib/systemd/system/freeswitch.service -e 's|^[[:blank:]]*\(CPUSchedulingPriority\)[[:blank:]]*=|#CPUSchedulingPriority=|g'

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

    systemctl daemon-reload
    systemctl start freeswitch
    systemctl status freeswitch -l
    netstat -alnp | egrep ":8021|freeswitch" | egrep -v "ESTABLISHED|_WAIT|SYN_"
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
    ls -la `fs_cli -x 'global_getvar mod_dir'`/mod_bcg729.so
    strip `fs_cli -x 'global_getvar mod_dir'`/mod_bcg729.so
    ls -la `fs_cli -x 'global_getvar mod_dir'`/mod_bcg729.so
    sed -i /etc/freeswitch/autoload_configs/modules.conf.xml -e 's|mod_g729\+|mod_bcg729|g'

    fs_cli -x 'unload mod_g729'
    fs_cli -x 'module_exists mod_g729'
    fs_cli -x 'load mod_bcg729'
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
    rm -fr .git
    cargo build
    ls -l target/debug/libmod_prometheus.so
    strip target/debug/libmod_prometheus.so
    ls -l target/debug/libmod_prometheus.so
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

    fs_cli -x 'load mod_prometheus'
    fs_cli -x 'module_exists mod_prometheus'
    netstat -alnp | egrep ":9282" | egrep -v "ESTABLISHED|_WAIT|SYN_"
    curl -v http://127.0.0.1:9282/metrics
}

# postinstall
#
# -----------------------------------------------------------------------------------------------------------------

postinstall() {
    systemctl daemon-reload
    systemctl mask wpa_supplicant.service
    systemctl stop wpa_supplicant.service

    systemctl enable ntpd
    systemctl enable postgresql-${PG_VER}
    systemctl enable freeswitch
    systemctl enable sshd

    systemctl restart ntpd
    systemctl restart postgresql-${PG_VER}
    systemctl restart freeswitch
    systemctl restart sshd

    systemctl status ntpd -l
    systemctl status postgresql-${PG_VER} -l
    systemctl status freeswitch -l
    systemctl status sshd -l
}

# Versions
#
# -----------------------------------------------------------------------------------------------------------------

versions() {
    hostname -f
    echo Kernel $(uname -r)
    echo

    echo PostgreSQL $(/usr/pgsql-9.4/bin/postgres --version | head -1 | cut -d' ' -f3-)
    echo FreeSWITCH $(/usr/bin/freeswitch -version | head -1 | cut -d' ' -f3)
    echo
    netstat -atulnp | egrep -v "ESTABLISHED|_WAIT|SYN_"


    ps -o uid,uname:10,gid,group:10,pid,ppid,args -afx | egrep "(USER|freeswitch)" | grep -v grep
	fs_cli -x 'show modules' | egrep "_shout|_bcg729|_prometheus|_av"
}

# main
#
# -----------------------------------------------------------------------------------------------------------------

#set -x
cleanup
preinstall
    freeswitch
    mod_g729
    mod_prometheus
postinstall
versions
exit 0
