#!/bin/sh -ex

# ----------------------------------------------------------------------------
# All in one
# ----------------------------------------------------------------------------
NUMBER_OF_CORES=`sysctl -n hw.ncpu`
FREEBSD_VERSION=11
USER=devops
PASSWORD=fabrik
ZPOOL=zroot

# ----------------------------------------------------------------------------
# no need to edit below this
# ----------------------------------------------------------------------------
START=$(date +%s)

# ----------------------------------------------------------------------------
# update sources
# ----------------------------------------------------------------------------
svnlite co svn://svn.freebsd.org/base/stable/${FREEBSD_VERSION} /usr/src

# ----------------------------------------------------------------------------
# fetch *.conf
# ----------------------------------------------------------------------------
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/src.conf -o /etc/fabrik-src.conf
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/src-jail.conf -o /etc/src-jail.conf
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/make.conf -o /etc/fabrik-make.conf
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/fabrik.kernel -o /usr/src/sys/amd64/conf/FABRIK

# ----------------------------------------------------------------------------
# create fabrik dir
# ----------------------------------------------------------------------------
mkdir -p /fabrik/host
mkdir /fabrik/jail

# ----------------------------------------------------------------------------
# build world, kernel and jail world
# ----------------------------------------------------------------------------
cd /usr/src
env MAKEOBJDIRPREFIX=/fabrik/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildworld
env MAKEOBJDIRPREFIX=/fabrik/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildkernel KERNCONF=FABRIK
env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/fabrik-make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildworld

# ----------------------------------------------------------------------------
# Create disk.raw FreeBSD ZFS root
# ----------------------------------------------------------------------------
cd /fabrik
RAW=disk.raw
VMSIZE=2g
WRKDIR=/tmp

# ----------------------------------------------------------------------------
zpool list
rm -f ${RAW}
truncate -s ${VMSIZE} ${RAW}
mddev=$(mdconfig -a -t vnode -f ${RAW})

gpart create -s gpt ${mddev}
gpart add -a 4k -s 512k -t freebsd-boot ${mddev}
gpart add -a 4k -t freebsd-swap -s 1G -l swap0 ${mddev}
gpart add -a 1m -t freebsd-zfs -l disk0 ${mddev}
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ${mddev}

sysctl vfs.zfs.min_auto_ashift=12

zpool create -o altroot=/mnt -o autoexpand=on -O compress=lz4 -O atime=off ${ZPOOL} /dev/gpt/disk0
zfs create -o mountpoint=none ${ZPOOL}/ROOT
zfs create -o mountpoint=/ ${ZPOOL}/ROOT/default
zfs create -o mountpoint=/tmp -o exec=off -o setuid=off ${ZPOOL}/tmp
zfs create -o mountpoint=/usr -o canmount=off ${ZPOOL}/usr
zfs create -o mountpoint=/usr/home ${ZPOOL}/usr/home
zfs create -o mountpoint=/usr/ports -o setuid=off ${ZPOOL}/usr/ports
zfs create ${ZPOOL}/usr/src
zfs create -o mountpoint=/var -o canmount=off ${ZPOOL}/var
zfs create -o exec=off -o setuid=off ${ZPOOL}/var/audit
zfs create -o exec=off -o setuid=off ${ZPOOL}/var/crash
zfs create -o exec=off -o setuid=off ${ZPOOL}/var/log
zfs create -o exec=off -o setuid=off -o readonly=on ${ZPOOL}/var/empty
zfs create -o atime=on ${ZPOOL}/var/mail
zfs create -o setuid=off ${ZPOOL}/var/tmp
zfs create ${ZPOOL}/var/ports
zfs create ${ZPOOL}/usr/obj
zfs create -o mountpoint=/jails ${ZPOOL}/jails
zfs create ${ZPOOL}/jails/base
zpool set bootfs=${ZPOOL}/ROOT/default ${ZPOOL}

cd /usr/src;
env MAKEOBJDIRPREFIX=/fabrik/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-make.conf make DESTDIR=/mnt installworld 2>&1 | tee ${WRKDIR}/host-installworld.log && \
env MAKEOBJDIRPREFIX=/fabrik/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-make.conf make DESTDIR=/mnt installkernel KERNCONF=FABRIK 2>&1 | tee ${WRKDIR}/host-installkernel.log && \
env MAKEOBJDIRPREFIX=/fabrik/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-make.conf make DESTDIR=/mnt distribution 2>&1 | tee ${WRKDIR}/host-distribution.log

env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/fabrik-make.conf make DESTDIR=/mnt/jails/base installworld 2>&1 | tee ${WRKDIR}/jail-installworld.log && \
env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/fabrik-make.conf make DESTDIR=/mnt/jails/base distribution 2>&1 | tee ${WRKDIR}/jail-distribution.log

mkdir -p /mnt/dev
mount -t devfs devfs /mnt/dev
chroot /mnt /etc/rc.d/ldconfig forcestart

# ----------------------------------------------------------------------------
# create user and set password
# ----------------------------------------------------------------------------
chroot /mnt pw useradd ${USER} -m -G wheel -s /bin/csh -h 0 <<EOP
${PASSWORD}
EOP

umount /mnt/dev

# ----------------------------------------------------------------------------
# resizezfs script to be run on firstboot
# ----------------------------------------------------------------------------
chroot /mnt mkdir -p /usr/local/etc/rc.d
sed 's/^X//' >/mnt/usr/local/etc/rc.d/resizezfs << 'RESIZEZFS'
X#!/bin/sh
X
X# KEYWORD: firstboot
X# PROVIDE: resizezfs
X# BEFORE: LOGIN
X
X. /etc/rc.subr
X
Xname="resizezfs"
Xrcvar=resizezfs_enable
Xstart_cmd="${name}_run"
Xstop_cmd=":"
X
Xresizezfs_run()
X{
X       DISK=$(gpart list | awk '/Geom name/{split($0,a,":"); print a[2]}')
X       GUID=$(zdb | awk '/children\[0\]/{flag=1; next} flag && /guid:/{split($0,arr,":"); print arr[2]; flag=0}')
X       gpart recover ${DISK}
X       gpart resize -i 3 ${DISK}
X       zpool online -e zroot ${GUID}
X       zfs set readonly=off zroot/ROOT/default
X}
X
Xload_rc_config $name
Xrun_rc_command "$1"
RESIZEZFS

chmod 0555 /mnt/usr/local/etc/rc.d/resizezfs
touch /mnt/firstboot

# /etc/fstab
cat << EOF > /mnt/etc/fstab
/dev/gpt/swap0   none    swap    sw      0       0
EOF

# /etc/resolv.conf
cat << EOF > /mnt/etc/resolv.conf
nameserver 4.2.2.2
nameserver 8.8.8.8
nameserver 2001:4860:4860::8888
nameserver 2001:1608:10:25::1c04:b12f
EOF

# /boot/loader.conf
cat << EOF > /mnt/boot/loader.conf
autoboot_delay="-1"
beastie_disable="YES"
console="comconsole,vidconsole"
hw.broken_txfifo="1"
hw.memtest.test="0"
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
zfs_load="YES"
EOF

# /etc/rc.conf
cat << EOF > /mnt/etc/rc.conf
resizezfs_enable="YES"
zfs_enable="YES"
ifconfig_DEFAULT="SYNCDHCP"
clear_tmp_enable="YES"
dumpdev="NO"
ntpd_enable="YES"
ntpdate_enable="YES"
sendmail_enable="NONE"
sshd_enable="YES"
syslogd_flags="-ssC"
jail_enable="NO"
jail_list="base"
EOF

# /etc/sysctl.conf
cat << EOF > /mnt/etc/sysctl.conf
debug.trace_on_panic=1
debug.debugger_on_panic=0
kern.panic_reboot_wait_time=0
security.bsd.see_other_uids=0
security.bsd.see_other_gids=0
security.bsd.unprivileged_read_msgbuf=0
security.bsd.unprivileged_proc_debug=0
security.bsd.stack_guard_page=1
EOF

# /etc/jail.conf
cat << EOF > /mnt/etc/jail.conf
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
allow.raw_sockets;
securelevel=3;
host.hostname="\$name.hostname";
path="/jails/\$name";

base {
    jid = 10;
    ip6.addr = vtnet0|2001:2ba0:fffd::2;
}
EOF

# jail rc.conf
cat << EOF > /mnt/jails/base/etc/rc.conf
sshd_enable="YES"
sshd_flags="-4"
syslogd_flags="-ssC"
clear_tmp_enable="YES"
sendmail_enable="NONE"
cron_flags="\$cron_flags -J 60"
EOF

# jail /etc/resolv.conf
cat << EOF > /mnt/jails/base/etc/resolv.conf
nameserver 4.2.2.2
nameserver 8.8.4.4
nameserver 2001:4860:4860::8888
nameserver 2001:1608:10:25::1c04:b12f
EOF

zpool export ${ZPOOL}
mdconfig -d -u ${mddev}
chflags -R noschg /mnt
rm -rf /mnt/*

END=$(date +%s)
DIFF=$(echo "$END - $START" | bc)

echo ------------------------------
echo "Started: $START"
echo "Ended: $END"
echo "build in $DIFF seconds."
echo ------------------------------
