#!/bin/sh
# ----------------------------------------------------------------------------
# fabrik.sh - create base jail
# ----------------------------------------------------------------------------
if [ $# -eq 0 ]
  then
    echo "enter name of the jail"
fi

FREEBSD_VERSION=11
JAILNAME=${1:-base}
NUMBER_OF_CORES=`sysctl -n hw.ncpu`
PASSWORD=fabrik
USER=devops
ZPOOL=tank

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
zfs create ${ZPOOL}/fabrik/jail/${JAILNAME}
zfs create ${ZPOOL}/fabrik/jail/obj
zfs set exec=on ${ZPOOL}/tmp
set -e

write "building jail"
cd /usr/src
env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildworld

write "Installing world, kernel and jail world"
env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make DESTDIR=/fabrik/jail/${JAILNAME} installworld 2>&1 | tee /tmp/jail-installworld.log && \
env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make DESTDIR=/fabrik/jail/${JAILNAME} distribution 2>&1 | tee /tmp/jail-distribution.log

write "Creating user ${USER} with password ${PASSWORD}"
chroot /fabrik/jail/${JAILNAME} pw useradd ${USER} -m -G wheel -s /bin/csh -h 0 <<EOP
${PASSWORD}
EOP

# jail rc.conf
cat << EOF > /fabrik/jail/${JAILNAME}/etc/rc.conf
clear_tmp_enable="YES"
cron_flags="\$cron_flags -J 60"
sendmail_enable="NONE"
syslogd_flags="-ssC8"
EOF

# jail /etc/resolv.conf
cat << EOF > /fabrik/jail/${JAILNAME}/etc/resolv.conf
nameserver 84.200.70.40
nameserver 208.67.222.222
nameserver 4.2.2.2
nameserver 2001:4860:4860::8888
nameserver 2001:1608:10:25::1c04:b12f
EOF

zfs set exec=off ${ZPOOL}/tmp

END=$(date +%s)
DIFF=$(echo "$END - $START" | bc)

write "Done! build in $DIFF seconds."
