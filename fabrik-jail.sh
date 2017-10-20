#!/bin/sh
set -e

# ----------------------------------------------------------------------------
# fabrik.sh - create base jail
# ----------------------------------------------------------------------------
NUMBER_OF_CORES=`sysctl -n hw.ncpu`
FREEBSD_VERSION=11
ZPOOL=tank
WRKDIR=/tmp

# ----------------------------------------------------------------------------
# no need to edit below this
# ----------------------------------------------------------------------------
START=$(date +%s)

write() {
    echo -e '\e[0;32m'
    echo \#----------------------------------------------------------------------------
    echo \# $1
    echo -e \#----------------------------------------------------------------------------'\e[0m'
}

write "Checking out and updating sources FreeBSD: ${FREEBSD_VERSION}"
svnlite co svn://svn.freebsd.org/base/stable/${FREEBSD_VERSION} /usr/src

write "Fetching src-jail.conf"
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/src-jail.conf -o /etc/src-jail.conf

write "Creating /fabrik dir"
set +e
zfs create -o mountpoint=/fabrik ${ZPOOL}/fabrik
zfs create ${ZPOOL}/fabrik/jail
zfs create ${ZPOOL}/fabrik/jail/base
zfs create ${ZPOOL}/fabrik/jail/obj
zfs create ${ZPOOL}/fabrik/tmp
set -e

write "building jail"
cd /usr/src
env WORLDTMP=/fabrik/tmp MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildworld

write "Installing world, kernel and jail world"
env WORLDTMP=/fabrik/tmp MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make DESTDIR=/fabrik/jail/base installworld 2>&1 | tee ${WRKDIR}/jail-installworld.log && \
env WORLDTMP=/fabrik/tmp MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make DESTDIR=/fabrik/jail/base distribution 2>&1 | tee ${WRKDIR}/jail-distribution.log

# jail rc.conf
cat << EOF > /fabrik/jail/base/etc/rc.conf
syslogd_flags="-ssC8"
clear_tmp_enable="YES"
sendmail_enable="NONE"
cron_flags="\$cron_flags -J 60"
EOF

# jail /etc/resolv.conf
cat << EOF > /fabrik/jail/base/etc/resolv.conf
nameserver 84.200.70.40
nameserver 208.67.222.222
nameserver 4.2.2.2
nameserver 2001:4860:4860::8888
nameserver 2001:1608:10:25::1c04:b12f
EOF

END=$(date +%s)
DIFF=$(echo "$END - $START" | bc)

write "Done! build in $DIFF seconds."
