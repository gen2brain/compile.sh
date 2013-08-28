#!/bin/bash
# Author: Milan Nikolic <gen2brain@gmail.com>

PROGVER=0.1.0
PROGNAME=${0##*/}
WORKDIR=${PWD}
PREFIX="/usr/local"
CPU_CORES=$(grep processor /proc/cpuinfo | wc -l)

usage() {
    cat << EOF
Usage:
 ${PROGNAME} [options]
 ${PROGNAME} --mysql --php --lighttpd
 ${PROGNAME} --mysql-version 5.5.33 --mysql
 ${PROGNAME} --php-version 5.4.18 --php-user daemon --php

Options:
EOF
    cat << EOF | column -s\& -t
 --mysql & compile and install mysql
 --mysql-version & specify mysql version, default is the latest
 --mysql-user & specify mysql user
 --mysql-fetch & perform fetch and unpack source
 --mysql-compile & compile source
 --mysql-install & install files
 --mysql-post-install & initialize mysql
EOF
    echo; cat << EOF | column -s\& -t
 --php & compile and install php
 --php-version & specify php version, default is the latest
 --php-user & specify php-fpm user
 --php-fetch & perform fetch and unpack source
 --php-compile & compile source
 --php-install & install files
 --php-post-install & configure php
EOF
    echo; cat << EOF | column -s\& -t
 --lighttpd & compile and install lighttpd
 --lighttpd-version & specify lighttpd version, default is the latest
 --lighttpd-user & specify lighttpd user
 --lighttpd-fetch & perform fetch and unpack source
 --lighttpd-compile & compile source
 --lighttpd-install & install files
 --lighttpd-post-install & configure lighttpd
EOF
    echo; cat << EOF | column -s\& -t
 --nginx & compile and install nginx
 --nginx-version & specify nginx version, default is the latest
 --nginx-user & specify nginx user
 --nginx-fetch & perform fetch and unpack source
 --nginx-compile & compile source
 --nginx-install & install files
 --nginx-post-install & configure nginx
EOF
    echo; cat << EOF | column -s\& -t
 -h, --help & show this output
 --version & show version information
EOF
}

user_add() {
    local USR=$1
    getent passwd | grep -q "^${USR}:"
    if [ $? -ne 0 ]; then
        groupadd -r ${USR}
        useradd -r -g -M ${USR} ${USR}
    fi
}

#################
##### MySQL #####
#################

mysql_prepare() {
    mysql_get_version $1

    if [ -z ${MYSQL_USER} ]; then
        MYSQL_USER="mysql"
    fi

    PASSWORD=`pwgen -y 10 1`
    DATADIR="/var/lib/mysql"
    SOCKET="/var/lib/mysql/mysql.sock"
    FILENAME="mysql-${VERSION}.tar.gz"

    MAJOR_VERSION=`echo ${VERSION} | awk -F \. {'print $1"."$2'}`
    if [ ${MAJOR_VERSION} = "5.6" ]; then
        DDIR="--ldata"
    else
        DDIR="--datadir"
    fi

    ps aux | grep -q [m]ysqld
    RUN=$?
    test -f ${DATADIR}/mysql/db.frm
    EXIST=$?

    ID=`hostname | sed 's/[^0-9]*\([0-9]*\).*/\1/g'`
    if [ -z "${ID}" ]; then
        ID=100
    fi

    read -r -d '' MY_CNF << EOF
[mysqld]
user=${MYSQL_USER}
datadir=${DATADIR}
socket=${SOCKET}

server-id=${ID}
log-bin=mysql-bin
report-host=$(hostname)
skip_name_resolve
innodb_file_per_table
max_connections=1024
performance_schema=off

[mysqld_safe]
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
EOF
}

mysql_get_version() {
    if [ -z "$1" ]; then
        if [ -z "${VERSION}" ]; then
            VERSION=`curl -s http://dev.mysql.com/downloads/mysql/ | \
                grep h1 | head -n -1 | tail -n -1 | \
                sed "s/<h1>MySQL Community Server \(.*\)<\/h1>/\\1/g"`
        fi
    else
        VERSION=$1
    fi
}

mysql_fetch() {
    mkdir -p ${WORKDIR} && cd ${WORKDIR}
    if [ ! -f ${WORKDIR}/${FILENAME} ]; then
        wget http://cdn.mysql.com/Downloads/MySQL-${MAJOR_VERSION}/${FILENAME} || \
        wget http://downloads.mysql.com/archives/mysql-${MAJOR_VERSION}/${FILENAME} || return 1
    fi
    if [ -d ${WORKDIR}/mysql-${VERSION} ]; then
        rm -rf ${WORKDIR}/mysql-${VERSION}
    fi
    tar -xvpf ${FILENAME}
    return 0
}

mysql_compile() {
    cd ${WORKDIR}/mysql-${VERSION} || return 1

    PACKAGES="cmake ncurses-devel openssl-devel pwgen"
    yum -y install ${PACKAGES}

    cmake . \
        -DWITH_READLINE=1 \
        -DWITH_UNIT_TESTS=0 \
        -DWITH_INNOBASE_STORAGE_ENGINE=1 \
        -DWITH_ARCHIVE_STORAGE_ENGINE=1 \
        -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \
        -DWITH_PERFSCHEMA_STORAGE_ENGINE=1 \
        -DWITH_PARTITION_STORAGE_ENGINE=1 \
        -DWITH_FEDERATED_STORAGE_ENGINE=1 \
        -DWITH_SSL=yes \
        -DSYSCONFDIR=/etc \
        -DINSTALL_LIBDIR=lib64 \
        -DMYSQL_DATADIR=${DATADIR} \
        -DMYSQL_UNIX_ADDR=${SOCKET} \
        -DCURSES_INCLUDE_PATH=/usr/include \
        -DCURSES_LIBRARY=/usr/lib64/libncurses.so \
        -DCMAKE_INSTALL_PREFIX=${PREFIX}/mysql-${VERSION}
    make -j ${CPU_CORES} || return 1
    return 0
}

mysql_install() {
    cd ${WORKDIR}/mysql-${VERSION} || return 1
    make install || return 1
    user_add ${MYSQL_USER}
    chown -R ${MYSQL_USER}: ${PREFIX}/mysql-${VERSION}
    return 0
}

mysql_set_password() {
    cd ${PREFIX}/mysql-${VERSION} || return 1
    ./bin/mysqladmin -u root password "${PASSWORD}" || return 1
    cat > /root/.my.cnf << EOF
[client]
user=root
password=${PASSWORD}
EOF
    ./bin/mysql -e "UPDATE mysql.user SET Password=PASSWORD('${PASSWORD}') WHERE User='root';" || return 1
    return 0
}

mysql_secure_installation() {
    cd ${PREFIX}/mysql-${VERSION} || return 1
    ./bin/mysql -e "DELETE FROM mysql.user WHERE User='';"
    ./bin/mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    ./bin/mysql -e "DROP DATABASE test;"
    ./bin/mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    ./bin/mysql -e "FLUSH PRIVILEGES;"
}

mysql_post_install() {
    cd ${PREFIX}/mysql-${VERSION} || return 1

    if [ ${RUN} != 0 ]; then
        if [ ${EXIST} != 0 ]; then
            cp -f ./support-files/mysql.server /etc/init.d/mysql.server

            chmod 755 /etc/init.d/mysql.server
            chkconfig --add /etc/init.d/mysql.server
            chkconfig mysql.server on

            mkdir -p ${DATADIR} && chown mysql: ${DATADIR} && chmod 755 ${DATADIR}
            ./scripts/mysql_install_db --user=${MYSQL_USER} ${DDIR}"="${DATADIR}

            rm -f /root/.my.cnf
            [ -L ${PREFIX}/mysql ] && rm -f ${PREFIX}/mysql
            ln -sf ${PREFIX}/mysql-${VERSION} ${PREFIX}/mysql
            echo "${MY_CNF}" > /etc/my.cnf

            printf "starting mysql\n"
            /etc/init.d/mysql.server start || return 1

            mv ${PREFIX}/mysql-${VERSION}/lib/plugin ${PREFIX}/mysql-${VERSION}/lib64/
            rmdir ${PREFIX}/mysql-${VERSION}/lib
            ln -sf ${PREFIX}/mysql-${VERSION}/lib64 ${PREFIX}/mysql-${VERSION}/lib

            mysql_set_password
            mysql_secure_installation
        else
            printf "\nmysql database already exists\n"
        fi
    else
        printf "\nmysql server is already running, skipping post-install\n"
    fi

    if [ ! -f "/etc/profile.d/mysql.sh" ]; then
        echo "pathmunge ${PREFIX}/mysql/bin after" > /etc/profile.d/mysql.sh && . /etc/profile
    fi

    if [ ! -f "/etc/ld.so.conf.d/mysql.conf" ]; then
        echo "${PREFIX}/mysql/lib64" > /etc/ld.so.conf.d/mysql.conf && ldconfig
    fi

    printf "\nsource /etc/profile if binaries are not in PATH\n\n"
    return 0
}

###############
##### PHP #####
###############

php_prepare() {
    php_get_version $1

    FILENAME="php-${VERSION}.tar.gz"
    if [ -z ${FPM_USER} ]; then
        FPM_USER="daemon"
    fi

    MAJOR_VERSION=`echo ${VERSION} | awk -F \. {'print $1"."$2'}`
    if [ ${MAJOR_VERSION} = "5.5" ]; then
        CONFIGURE="${CONFIGURE} --enable-opcache"
    else
        CONFIGURE="${CONFIGURE} --with-curlwrappers"
    fi

    ps aux | grep -q [p]hp-fpm
    RUN=$?
    which php >/dev/null 2>&1
    EXIST=$?

    if [ ${EXIST} -eq 0 ]; then
        PHP_INI=`php -i | grep "Loaded Configuration File" | awk -F'=>' '{print $2}'`
        EXTENSIONS=`cat ${PHP_INI} | grep -v "^;" | grep "^extension\|zend_extension" | awk -F'=' '{print $2}' | tr -d '"' | awk -F'.so' '{print $1}'`
    fi
}

php_get_version() {
    if [ -z "$1" ]; then
        if [ -z "${VERSION}" ]; then
            VERSION=`curl -s http://php.net/downloads.php | grep h1 | head -n 1 | \
                sed "s/<h1.*>PHP \(.*\) (Current stable)<\/h1>/\\1/g" | sed "s/\s//g"`
        fi
    else
        VERSION=$1
    fi
}

php_fetch() {
    mkdir -p ${WORKDIR} && cd ${WORKDIR}
    if [ ! -f ${WORKDIR}/${FILENAME} ]; then
        wget http://www.php.net/distributions/${FILENAME} || \
        wget http://us1.php.net/distributions/${FILENAME} || return 1
    fi
    if [ -d ${WORKDIR}/php-${VERSION} ]; then
        rm -rf ${WORKDIR}/php-${VERSION}
    fi
    tar -xvpf ${FILENAME}
    return 0
}

php_compile() {
    cd ${WORKDIR}/php-${VERSION} || return 1

    PACKAGES="openssl-devel libxml2-devel libcurl-devel libjpeg-devel libpng-devel freetype-devel \
            libc-client-devel aspell-devel libmcrypt-devel pcre-devel libevent-devel zeromq3-devel \
            libssh2-devel libmemcached-devel bzip2-devel openldap-devel readline-devel GeoIP-devel"
    yum -y install ${PACKAGES}

    CONFIGURE="
        --prefix=${PREFIX}/php-${VERSION} \
        --enable-fpm \
        --with-fpm-user=${FPM_USER} \
        --with-fpm-group=${FPM_USER} \
        --with-mysql=${PREFIX}/mysql \
        --with-mysqli \
        --with-pdo-mysql \
        --with-libdir=lib64 \
        --enable-ftp \
        --enable-mbstring \
        --with-openssl \
        --with-pspell=/usr \
        --with-jpeg-dir=/usr \
        --with-png-dir=/usr \
        --with-freetype-dir=/usr \
        --with-gd \
        --enable-gd-native-ttf \
        --enable-inline-optimization \
        --with-curl \
        --with-imap \
        --with-imap-ssl \
        --with-kerberos \
        --with-ldap \
        --with-ldap-sasl \
        --with-mcrypt \
        --with-gettext \
        --with-readline \
        --with-zlib \
        --with-zlib-dir=/usr \
        --with-bz2 \
        --enable-zip \
        --enable-pcntl \
        --enable-soap \
        --enable-sockets"

    ./configure ${CONFIGURE}
    make -j ${CPU_CORES} || return 1
    return 0
}

php_install() {
    cd ${WORKDIR}/php-${VERSION} || return 1
    make install || return 1
    user_add ${FPM_USER}
    return 0
}

php_default_config() {
    mkdir -p /var/log/php-fpm
    local INI_FILE="${PREFIX}/php-${VERSION}/lib/php.ini"
    local CONF_FILE="${PREFIX}/php-${VERSION}/etc/php-fpm.conf"

    if [ ${MAJOR_VERSION} = "5.5" ]; then
        echo "zend_extension=opcache.so" >> ${INI_FILE}
        echo "opcache.enable=1" >> ${INI_FILE}
        echo "opcache.enable_cli=1" >> ${INI_FILE}
        echo "opcache.memory_consumption=128" >> ${INI_FILE}
        echo "opcache.interned_strings_buffer=8" >> ${INI_FILE}
        echo "opcache.max_accelerated_files=4000" >> ${INI_FILE}
    fi

    sed -i '/^;date.timezone/c\date.timezone = America/New_York' ${INI_FILE}
    sed -i '/^;short_open_tag/c\short_open_tag = On' ${INI_FILE}
    sed -i '/^memory_limit/c\memory_limit = 1024M' ${INI_FILE}
    sed -i '/^;error_log = syslog/a\error_log = /var/log/php-fpm/php-fpm.log' ${INI_FILE}
    sed -i '/^default_socket_timeout/c\default_socket_timeout = 600' ${INI_FILE}
    sed -i '/^; max_input_vars/a\max_input_vars = 10000' ${INI_FILE}
    sed -i '/^post_max_size/c\post_max_size = 512M' ${INI_FILE}
    sed -i '/^upload_max_filesize/c\upload_max_filesize = 512M' ${INI_FILE}

    sed -i '/### END INIT INFO/a\\nulimit -HSn 200000' /etc/init.d/php-fpm
    sed -i '/^prefix=/c\prefix=/usr/local/php' /etc/init.d/php-fpm

    sed -i '/^;pid/c\pid = run\/php-fpm.pid' ${CONF_FILE}
    sed -i '/^;error_log/c\error_log = \/var\/log\/php-fpm\/php-fpm.log' ${CONF_FILE}
    sed -i '/^;log_level/c\log_level = warning' ${CONF_FILE}
    sed -i '/^listen =/c\listen = 127.0.0.1:8833' ${CONF_FILE}
    sed -i '/^pm.max_children/c\pm.max_children = 1000' ${CONF_FILE}
    sed -i '/^pm.start_servers/c\pm.start_servers = 100' ${CONF_FILE}
    sed -i '/^pm.min_spare_servers/c\pm.min_spare_servers = 50' ${CONF_FILE}
    sed -i '/^pm.max_spare_servers/c\pm.max_spare_servers = 200' ${CONF_FILE}
    sed -i '/^pm.max_requests/c\pm.max_requests = 500' ${CONF_FILE}
    sed -i '/^;pm.status_path/c\pm.status_path = \/fpm-x-status' ${CONF_FILE}
    sed -i '/^;ping.path/c\ping.path = \/fpm-x-ping' ${CONF_FILE}
    sed -i '/^;request_slowlog_timeout/c\request_slowlog_timeout = 30' ${CONF_FILE}
    sed -i '/^;slowlog/c\slowlog = \/var\/log\/php-fpm\/$pool.log.slow' ${CONF_FILE}
    sed -i '/^;rlimit_files/c\rlimit_files = 200000' ${CONF_FILE}
    sed -i '/^;chdir/c\chdir = /var/www' ${CONF_FILE}
    sed -i '/^;catch_workers_output/c\catch_workers_output = yes' ${CONF_FILE}
    sed -i '/^;php_admin_flag\[log_errors\]/c\php_admin_flag\[log_errors\] = on' ${CONF_FILE}
    sed -i '/^;php_admin_value\[memory_limit\]/a\\nphp_admin_value\[post_max_size\] = 512M\nphp_admin_value\[upload_max_filesize\] = 512M' ${CONF_FILE}
    sed -i 's/^;env/env/' ${CONF_FILE}
}

php_post_install() {
    cd ${PREFIX}/php-${VERSION} || return 1

    if [ ${EXIST} -ne 0 ]; then
        if [ ${RUN} -ne 0 ]; then
            cp -f ${WORKDIR}/php-${VERSION}/php.ini-production ${PREFIX}/php-${VERSION}/lib/php.ini
            cp -f ${WORKDIR}/php-${VERSION}/sapi/fpm/init.d.php-fpm /etc/init.d/php-fpm
            cp -f ${PREFIX}/php-${VERSION}/etc/php-fpm.conf.default ${PREFIX}/php-${VERSION}/etc/php-fpm.conf

            chmod 755 /etc/init.d/php-fpm
            chkconfig --add /etc/init.d/php-fpm
            chkconfig php-fpm on

            [ -L ${PREFIX}/php ] && rm -f ${PREFIX}/php
            ln -sf ${PREFIX}/php-${VERSION} ${PREFIX}/php

            mkdir -p /var/www
            php_default_config

            printf "starting php-fpm\n"
            /etc/init.d/php-fpm start || return 1
        else
            printf "php-fpm is already running, skipping post-install\n"
        fi
    else
        cp -f ${PHP_INI} ${PREFIX}/php-${VERSION}/lib/
        printf "php already exists, trying to recompile extensions\n"
        for ext in ${EXTENSIONS}; do
            ${PREFIX}/php-${VERSION}/bin/pecl install `basename ${ext}`
        done
    fi

    if [ ! -f "/etc/profile.d/php.sh" ]; then
        echo "pathmunge ${PREFIX}/php/bin after" > /etc/profile.d/php.sh && . /etc/profile
    fi

    printf "\nsource /etc/profile if binaries are not in PATH\n\n"
    return 0
}

####################
##### Lighttpd #####
####################

lighttpd_prepare() {
    lighttpd_get_version $1

    FILENAME="lighttpd-${VERSION}.tar.gz"
    if [ -z ${LIGHTTPD_USER} ]; then
        LIGHTTPD_USER="daemon"
    fi

    MAJOR_VERSION=`echo ${VERSION} | awk -F \. {'print $1"."$2'}`

    ps aux | grep -q "${PREFIX}/[l]ighttpd"
    RUN=$?
    test -f ${PREFIX}/lighttpd/etc/lighttpd.conf
    EXIST=$?
}

lighttpd_get_version() {
    if [ -z "$1" ]; then
        if [ -z "${VERSION}" ]; then
            VERSION=`curl -s http://www.lighttpd.net/download/ | grep h2 | head -n 1 | \
                sed "s/<h2><a.*>\(.*\)<\/a><\/h2>/\\1/g" | sed "s/\s//g"`
        fi
    else
        VERSION=$1
    fi
}

lighttpd_fetch() {
    mkdir -p ${WORKDIR} && cd ${WORKDIR}
    if [ ! -f ${WORKDIR}/${FILENAME} ]; then
        wget http://download.lighttpd.net/lighttpd/releases-${MAJOR_VERSION}.x/${FILENAME} || return 1
    fi
    if [ -d ${WORKDIR}/lighttpd-${VERSION} ]; then
        rm -rf ${WORKDIR}/lighttpd-${VERSION}
    fi
    tar -xvpf ${FILENAME}
    return 0
}

lighttpd_compile() {
    cd ${WORKDIR}/lighttpd-${VERSION} || return 1

    PACKAGES="openssl-devel pcre-devel bzip2-devel"
    yum -y install ${PACKAGES}

    CONFIGURE="
        --prefix=${PREFIX}/lighttpd-${VERSION} \
        --with-openssl"

    grep -q "^${PREFIX}" `which mysql 2>/dev/null`
    if [ $? -eq 0 ]; then
        CONFIGURE="${CONFIGURE} --with-mysql=${PREFIX}/mysql/bin/mysql_config"
    fi

    ./configure ${CONFIGURE}
    make -j ${CPU_CORES} || return 1
    return 0
}

lighttpd_install() {
    cd ${WORKDIR}/lighttpd-${VERSION} || return 1
    make install || return 1
    user_add ${LIGHTTPD_USER}
    return 0
}

lighttpd_default_config() {
    cat << EOF > ${PREFIX}/lighttpd-${VERSION}/etc/lighttpd.conf
server.modules = (
    "mod_redirect",
    "mod_rewrite",
    "mod_alias",
    "mod_access",
    "mod_auth",
    "mod_status",
    "mod_setenv",
    "mod_fastcgi",
    "mod_proxy",
    "mod_simple_vhost",
    "mod_compress",
    "mod_expire",
    "mod_accesslog"
)

server.port = 80
server.username = "${LIGHTTPD_USER}"
server.groupname = "${LIGHTTPD_USER}"
server.document-root = "/var/www/htdocs"
server.pid-file = "/var/run/lighttpd.pid"
compress.cache-dir = "/var/cache/lighttpd/compress"
compress.filetype = ("text/plain", "text/html")

server.max-fds = 4096
server.follow-symlink = "enable"
server.errorlog = "/var/log/lighttpd/error.log"
accesslog.filename = "/var/log/lighttpd/access.log"
index-file.names = ( "index.php" )

mimetype.assign = (
    ".pdf"          =>      "application/pdf",
    ".sig"          =>      "application/pgp-signature",
    ".spl"          =>      "application/futuresplash",
    ".class"        =>      "application/octet-stream",
    ".ps"           =>      "application/postscript",
    ".torrent"      =>      "application/x-bittorrent",
    ".dvi"          =>      "application/x-dvi",
    ".gz"           =>      "application/x-gzip",
    ".pac"          =>      "application/x-ns-proxy-autoconfig",
    ".swf"          =>      "application/x-shockwave-flash",
    ".tar.gz"       =>      "application/x-tgz",
    ".tgz"          =>      "application/x-tgz",
    ".tar"          =>      "application/x-tar",
    ".zip"          =>      "application/zip",
    ".mp3"          =>      "audio/mpeg",
    ".m3u"          =>      "audio/x-mpegurl",
    ".wma"          =>      "audio/x-ms-wma",
    ".wax"          =>      "audio/x-ms-wax",
    ".ogg"          =>      "application/ogg",
    ".wav"          =>      "audio/x-wav",
    ".gif"          =>      "image/gif",
    ".jar"          =>      "application/x-java-archive",
    ".jpg"          =>      "image/jpeg",
    ".jpeg"         =>      "image/jpeg",
    ".png"          =>      "image/png",
    ".xbm"          =>      "image/x-xbitmap",
    ".xpm"          =>      "image/x-xpixmap",
    ".xwd"          =>      "image/x-xwindowdump",
    ".css"          =>      "text/css",
    ".html"         =>      "text/html",
    ".htm"          =>      "text/html",
    ".js"           =>      "text/javascript",
    ".asc"          =>      "text/plain",
    ".c"            =>      "text/plain",
    ".cpp"          =>      "text/plain",
    ".log"          =>      "text/plain",
    ".conf"         =>      "text/plain",
    ".text"         =>      "text/plain",
    ".txt"          =>      "text/plain",
    ".dtd"          =>      "text/xml",
    ".xml"          =>      "text/xml",
    ".mpeg"         =>      "video/mpeg",
    ".mpg"          =>      "video/mpeg",
    ".mov"          =>      "video/quicktime",
    ".qt"           =>      "video/quicktime",
    ".avi"          =>      "video/x-msvideo",
    ".asf"          =>      "video/x-ms-asf",
    ".asx"          =>      "video/x-ms-asf",
    ".wmv"          =>      "video/x-ms-wmv",
    ".bz2"          =>      "application/x-bzip",
    ".tbz"          =>      "application/x-bzip-compressed-tar",
    ".tar.bz2"      =>      "application/x-bzip-compressed-tar",
    ".ico"          =>      "image/x-icon",
    ""              =>      "application/octet-stream"
)

\$HTTP["url"] =~ "\.svn|\.git|\.htaccess|\.htpasswd" {
    url.access-deny = ("")
}
static-file.exclude-extensions = ( ".php", ".pl", ".fcgi" )

status.status-url = "/server-status"
status.statistics-url = "/server-statistics"

auth.backend = "plain"
auth.backend.plain.userfile = "${PREFIX}/lighttpd/etc/lighttpd.user"
auth.require = (
    "/server-status" => ("method" => "basic", "realm" => "server-status", "require" => "user=nagioscacti"),
    "/server-statistics" => ("method" => "basic", "realm" => "server-statistics", "require" => "valid-user")
)

\$HTTP["host"] =~ "^$(hostname | sed 's/\./\\./g')(\:[0-9]*)?$" {
    index-file.names = ( "index.php" )
    include "${PREFIX}/lighttpd/etc/php.conf"
    server.document-root = "/var/www/htdocs"
    accesslog.filename = "/var/log/lighttpd/`hostname`-access.log"
}
EOF
    cat << EOF > ${PREFIX}/lighttpd-${VERSION}/etc/php.conf
fastcgi.server = ( ".php" =>
    (( "host" => "127.0.0.1",
       "port" => 8833,
       "allow-x-send-file" => "enable",
       "check-local" => "disable",
       "disable-time" => 1,
       "bin-copy-environment" => ( "PATH", "SHELL", "USER", "HTTPS" ),
       "broken-scriptfilename" => "enable"
    ))
)
EOF
    cat << EOF > ${PREFIX}/lighttpd-${VERSION}/etc/lighttpd.user
nagioscacti:hahanemasira
EOF
}

lighttpd_post_install() {
    cd ${PREFIX}/php-${VERSION} || return 1
    if [ ${RUN} -ne 0 ]; then
        cp -f ${WORKDIR}/lighttpd-${VERSION}/doc/initscripts/rc.lighttpd.redhat /etc/init.d/lighttpd
        echo "LIGHTTPD_CONF_PATH=${PREFIX}/lighttpd/etc/lighttpd.conf" > /etc/sysconfig/lighttpd
        sed -i '/^lighttpd=/c\lighttpd=/usr/local/lighttpd/sbin/lighttpd' /etc/init.d/lighttpd
        sed -i '/^lighttpd=/a\\nulimit -n 65535' /etc/init.d/lighttpd

        chmod 755 /etc/init.d/lighttpd
        chkconfig --add /etc/init.d/lighttpd
        chkconfig lighttpd on

        mkdir -p ${PREFIX}/lighttpd-${VERSION}/etc /var/log/lighttpd /var/www/htdocs /var/cache/lighttpd/compress
        chown ${LIGHTTPD_USER}: /var/log/lighttpd /var/cache/lighttpd/compress
        echo "<?php print gethostname(); ?>" > /var/www/htdocs/index.php

        if [ ${EXIST} -ne 0 ]; then
            lighttpd_default_config
        else
            cp -f ${PREFIX}/lighttpd/etc/lighttpd.conf ${PREFIX}/lighttpd-${VERSION}/etc/lighttpd.conf
        fi

        [ -L ${PREFIX}/lighttpd ] && rm -f ${PREFIX}/lighttpd
        ln -sf ${PREFIX}/lighttpd-${VERSION} ${PREFIX}/lighttpd

        printf "starting lighttpd\n"
        /etc/init.d/lighttpd start || return 1
    else
        printf "lighttpd is already running, skipping post-install\n"
    fi
    return 0
}

###################
#####  Nginx  #####
###################

nginx_prepare() {
    nginx_get_version $1

    FILENAME="nginx-${VERSION}.tar.gz"
    if [ -z ${NGINX_USER} ]; then
        NGINX_USER="daemon"
    fi

    MAJOR_VERSION=`echo ${VERSION} | awk -F \. {'print $1"."$2'}`

    ps aux | grep -q "${PREFIX}/[n]ginx"
    RUN=$?
    test -f ${PREFIX}/nginx/conf/nginx.conf
    EXIST=$?
}

nginx_get_version() {
    if [ -z "$1" ]; then
        if [ -z "${VERSION}" ]; then
            which tidy >/dev/null 2>&1 || yum -y install tidy
            VERSION=`curl -s http://nginx.org/en/download.html | tidy -q 2>/dev/null | \
                grep '^"/download' | head -n 3 | tail -n 1 | \
                awk -F'>' '{print $2}' | sed 's/nginx-\(.*\)<.*/\1/'`
        fi
    else
        VERSION=$1
    fi
}

nginx_fetch() {
    mkdir -p ${WORKDIR} && cd ${WORKDIR}
    if [ ! -f ${WORKDIR}/${FILENAME} ]; then
        wget http://nginx.org/download/${FILENAME} || return 1
    fi
    if [ -d ${WORKDIR}/nginx-${VERSION} ]; then
        rm -rf ${WORKDIR}/nginx-${VERSION}
    fi
    tar -xvpf ${FILENAME}
    return 0
}

nginx_compile() {
    cd ${WORKDIR}/nginx-${VERSION} || return 1

    PACKAGES="openssl-devel pcre-devel zlib-devel"
    yum -y install ${PACKAGES}

    CONFIGURE="
        --user=${NGINX_USER} \
        --group=${NGINX_USER} \
        --prefix=${PREFIX}/nginx-${VERSION} \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/lock/nginx.lock \
        --with-http_ssl_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_stub_status_module \
		--http-client-body-temp-path=/client \
		--http-proxy-temp-path=/var/tmp/nginx/proxy \
		--http-fastcgi-temp-path=/var/tmp/nginx/fastcgi \
		--http-scgi-temp-path=/var/tmp/nginx/scgi \
		--http-uwsgi-temp-path=/var/tmp/nginx/uwsgi"


    sed -i 's:.default::' ${WORKDIR}/nginx-${VERSION}/auto/install
    sed -i -e '/koi-/d' -e '/win-/d' ${WORKDIR}/nginx-${VERSION}/auto/install

    ./configure ${CONFIGURE}
    make -j ${CPU_CORES} || return 1
    return 0
}

nginx_install() {
    cd ${WORKDIR}/nginx-${VERSION} || return 1
    make install || return 1
    user_add ${NGINX_USER}
    return 0
}

nginx_default_config() {
    cat << EOF > ${PREFIX}/nginx-${VERSION}/conf/nginx.conf
user ${NGINX_USER} ${NGINX_USER};
worker_processes ${CPU_CORES};
error_log logs/error.log;

events {
    worker_connections 4096;
	use epoll;
}

http {
    include mime.types;
    default_type application/octet-stream;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 60;
    client_max_body_size 512M;

    gzip on;
    gzip_types text/plain;

    server {
        listen 80;
        server_name $(hostname);

        access_log logs/$(hostname)-access.log;
        error_log logs/$(hostname)-error.log;

        root /var/www/htdocs;
        index index.php index.html;

        include php.conf;
    }

}
EOF
    cat << EOF > ${PREFIX}/nginx-${VERSION}/conf/php.conf
location ~ \\.php$ {
    fastcgi_index   index.php;
    fastcgi_pass    127.0.0.1:8833;
    include         fastcgi_params;
    include         fastcgi.conf;
}
EOF
}

nginx_post_install() {
    if [ ${RUN} -ne 0 ]; then
        wget -O rc.nginx 'http://wiki.nginx.org/index.php?title=RedHatNginxInitScript&action=raw&anchor=nginx'
        cp -f ${WORKDIR}/nginx-${VERSION}/rc.nginx /etc/init.d/nginx
        sed -i '/^nginx=/c\nginx=/usr/local/nginx/sbin/nginx' /etc/init.d/nginx
        sed -i '/^NGINX_CONF_FILE=/c\NGINX_CONF_FILE=/usr/local/nginx/conf/nginx.conf' /etc/init.d/nginx

        chmod 755 /etc/init.d/nginx
        chkconfig --add /etc/init.d/nginx
        chkconfig nginx on

        mkdir -p /var/www/htdocs /var/tmp/nginx
        echo "<?php print gethostname(); ?>" > /var/www/htdocs/index.php

        if [ ${EXIST} -ne 0 ]; then
            nginx_default_config
        fi

        [ -L ${PREFIX}/nginx ] && rm -f ${PREFIX}/nginx
        ln -sf ${PREFIX}/nginx-${VERSION} ${PREFIX}/nginx

        printf "starting nginx\n"
        /etc/init.d/nginx start || return 1
    else
        printf "nginx is already running, skipping post-install\n"
    fi
    return 0
}

##################
#####  Main  #####
##################

OPTS="vh"
LONGOPTS="mysql-version:,php-version:,lighttpd-version:,nginx-version:,mysql-user:,php-user:,lighttpd-user:,nginx-user:,help,version,mysql,mysql-fetch,mysql-compile,mysql-install,mysql-post-install,php,php-fetch,php-compile,php-install,php-post-install,lighttpd,lighttpd-fetch,lighttpd-compile,lighttpd-install,lighttpd-post-install,nginx,nginx-fetch,nginx-compile,nginx-install,nginx-post-install"
ARGS=`getopt --name ${PROGNAME} -o ${OPTS} -l ${LONGOPTS} -- "$@"`
eval set -- "${ARGS}"

while true; do
  case $1 in

    --mysql)
        mysql_prepare
        mysql_fetch && mysql_compile && mysql_install && mysql_post_install && unset VERSION
        shift;;
    --mysql-version)
        mysql_prepare "$2"
        shift;;
    --mysql-user)
        MYSQL_USER="$2"
        shift;;
    --mysql-fetch)
        mysql_prepare
        mysql_fetch
        shift;;
    --mysql-compile)
        mysql_prepare
        mysql_compile
        shift;;
    --mysql-install)
        mysql_prepare
        mysql_install
        shift;;
    --mysql-post-install)
        mysql_prepare
        mysql_post_install
        shift;;

    --php)
        php_prepare
        php_fetch && php_compile && php_install && php_post_install && unset VERSION
        shift;;
    --php-version)
        php_prepare "$2"
        shift;;
    --php-user)
        FPM_USER="$2"
        shift;;
    --php-fetch)
        php_prepare
        php_fetch
        shift;;
    --php-compile)
        php_prepare
        php_compile
        shift;;
    --php-install)
        php_prepare
        php_install
        shift;;
    --php-post-install)
        php_prepare
        php_post_install
        shift;;

    --lighttpd)
        lighttpd_prepare
        lighttpd_fetch && lighttpd_compile && lighttpd_install && lighttpd_post_install && unset VERSION
        shift;;
    --lighttpd-version)
        lighttpd_prepare "$2"
        shift;;
    --lighttpd-user)
        LIGHTTPD_USER="$2"
        shift;;
    --lighttpd-fetch)
        lighttpd_prepare
        lighttpd_fetch
        shift;;
    --lighttpd-compile)
        lighttpd_prepare
        lighttpd_compile
        shift;;
    --lighttpd-install)
        lighttpd_prepare
        lighttpd_install
        shift;;
    --lighttpd-post-install)
        lighttpd_prepare
        lighttpd_post_install
        shift;;

    --nginx)
        nginx_prepare
        nginx_fetch && nginx_compile && nginx_install && nginx_post_install && unset VERSION
        shift;;
    --nginx-version)
        nginx_prepare "$2"
        shift;;
    --nginx-user)
        NGINX_USER="$2"
        shift;;
    --nginx-fetch)
        nginx_prepare
        nginx_fetch
        shift;;
    --nginx-compile)
        nginx_prepare
        nginx_compile
        shift;;
    --nginx-install)
        nginx_prepare
        nginx_install
        shift;;
    --nginx-post-install)
        nginx_prepare
        nginx_post_install
        shift;;

    -h|--help)
        usage
        shift;;
    -v|--version)
        echo ${PROGVER}
        shift;;

    --)
        shift;
        break;;
    *)
        shift;
        break;;
  esac
  shift
done

exit $?
