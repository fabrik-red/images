#!/bin/sh
# ----------------------------------------------------------------------------
# create jail
# ----------------------------------------------------------------------------

set_defaults() {
    ZPOOL="tank"
    JAILNAME="base"
    FREEBSD_VERSION=11
    NUMBER_OF_CORES=`sysctl -n hw.ncpu`
    PASSWORD=fabrik
    USER=devops
}

write() {
    echo -e '\e[0;32m'
    cat <<-EOF
#----------------------------------------------------------------------------
# $1
#----------------------------------------------------------------------------
EOF
echo -e '\e[0m'
}

usage() {
    set_defaults
    cat <<-EOF
Example: $(basename "$0") -p=/tank/fabrik/jails/test
         $(basename "$0") -n=xxx (jail path will be /fabrik/jail/xxx)
         $(basename "$0") -z=tank -n=test (jail path will be <tank>/fabrik/jail/test)

Available pools:
$(zpool list)

Parameters:
    -h | --help)
        Show this help.
    -p | --path)
        Jail path
        Default: ${JAILPATH}
    -n | --name)
        jail name
        Default: ${JAILNAME}
    -z | --zpool)
        ZFS pool to use
        Default: ${ZPOOL}
EOF
}

parse_args() {
    set_defaults
    SAFE_DELIMITER="$(printf "\a")"
    while [ "$1" != "" ]
    do
        PARAM=$(echo $1 | cut -f1 -d=)
        VALUE=$(echo $1 | sed "s/=/${SAFE_DELIMITER}/" | cut -f2 "-d${SAFE_DELIMITER}")
        case $PARAM in
            -h | --help)
                usage
                exit
                ;;
            -p | --path)
                JAILPATH="${VALUE}"
                ;;
            -n | --name)
                JAILNAME="${VALUE}"
                ;;
            -z | --zpool)
                ZPOOL="${VALUE}"
                ;;
            *)
                echo "ERROR: Unknown parameter ${PARAM}"
                usage
                exit 1
        esac
        shift
    done
}

main() {
    if [ $# -eq 0 ]
    then
        usage
        exit
    fi
    parse_args $@
}

main $@

[ -z "${JAILPATH}" ] && JAILPATH="/fabrik/jail/${JAILNAME}"

# ----------------------------------------------------------------------------
# no need to edit below this
# ----------------------------------------------------------------------------
START=$(date +%s)

set -e
[ ! -d "${JAILPATH}" ] && write "Creating ${JAILPATH#*/}" && zfs create -p ${JAILPATH#*/}
set +e

write "Checking out and updating sources FreeBSD: ${FREEBSD_VERSION}"
svnlite co svn://svn.freebsd.org/base/stable/${FREEBSD_VERSION} /usr/src

write "Fetching src-jail.conf"
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/src-jail.conf -o /etc/src-jail.conf

write "Creating /fabrik dir"
set +e
zfs create -o mountpoint=/fabrik ${ZPOOL}/fabrik
zfs create ${ZPOOL}/fabrik/jail
zfs create ${JAILPATH#*/}
zfs create ${ZPOOL}/fabrik/jail/obj
zfs set exec=on ${ZPOOL}/tmp
set -e


write "building jail"
cd /usr/src
env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildworld

write "Installing world, kernel and jail world"
env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make DESTDIR=${JAILPATH} installworld 2>&1 | tee /tmp/jail-installworld.log && \
    env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make DESTDIR=${JAILPATH} distribution 2>&1 | tee /tmp/jail-distribution.log

write "Creating user ${USER} with password ${PASSWORD}"
chroot ${JAILPATH} pw useradd ${USER} -m -G wheel -s /bin/csh -h 0 <<EOP
${PASSWORD}
EOP

# jail rc.conf
cat << EOF > ${JAILPATH}/etc/rc.conf
clear_tmp_enable="YES"
cron_flags="\$cron_flags -J 60"
sendmail_enable="NONE"
sshd_enable="YES"
syslogd_flags="-ssC8"
EOF

# jail /etc/resolv.conf
cat << EOF > ${JAILPATH}/etc/resolv.conf
nameserver 172.16.8.1
EOF

zfs set exec=off ${ZPOOL}/tmp

END=$(date +%s)
DIFF=$(echo "$END - $START" | bc)

write "Done! build in $DIFF seconds."
