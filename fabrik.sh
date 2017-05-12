#!/bin/sh -ex

# ----------------------------------------------------------------------------
# All in one
# ----------------------------------------------------------------------------
NUMBER_OF_CORES=`sysctl -n hw.ncpu`
FREEBSD_VERSION=11
USER=devops # user to be created on firstboot
ZPOOL=zroot
SSHKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILOzFY7MEt3G4HwAtqtRkpdWYWI4PIGCPLG90L3VdtMM fabrik"

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
mkdir -p /fabrik/jail

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
chroot /mnt pw useradd devops -m -G wheel -s /bin/csh -h 0 <<EOP
fabrik
EOP
umount /mnt/dev

# /etc/resolv.conf
cat << EOF > /mnt/etc/resolv.conf
nameserver 4.2.2.2
nameserver 8.8.8.8
nameserver 2001:4860:4860::8888
nameserver 2001:1608:10:25::1c04:b12f
EOF

sed 's/^X//' >/mnt/usr/local/etc/rc.d/fetchkey << 'FETCHKEY'
X#!/bin/sh
X# PROVIDE: fetchkey
X# REQUIRE: NETWORKING
X# BEFORE: LOGIN
X
X# Define fetchkey_enable=YES in /etc/rc.conf to enable SSH key fetching
X# when the system first boots.
X: ${fetchkey_enable=NO}
X
X# Set fetchkey_user to change the user for which SSH keys are provided.
X: ${fetchkey_user=__user__}
X
X. /etc/rc.subr
X
Xname="fetchkey"
Xrcvar=fetchkey_enable
Xstart_cmd="fetchkey_run"
Xstop_cmd=":"
X
XSSHKEYURL_AWS="http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key"
XSSHKEYURL_ONLINE="https://ssh-keys.online/new.keys"
X
pw useradd ${fetchkey_user} -m -G wheel
X	fi
X
X	# Figure out where the SSH public key needs to go.
X	eval SSHKEYFILE="~${fetchkey_user}/.ssh/authorized_keys"
X
X	# Grab the provided SSH public key and add it to the
X	# right authorized_keys file to allow it to be used to
X	# log in as the specified user.
X	mkdir -p `dirname ${SSHKEYFILE}`
X	chmod 700 `dirname ${SSHKEYFILE}`
X	chown ${fetchkey_user} `dirname ${SSHKEYFILE}`
X	echo "Fetching SSH public key for ${fetchkey_user}"
X	fetch --no-verify-peer -o ${SSHKEYFILE}.aws.keys -a -T 5 ${SSHKEYURL_AWS} >/dev/null
X	fetch --no-verify-peer -o ${SSHKEYFILE}.online.keys -a ${SSHKEYURL_ONLINE} >/dev/null
X	if [ -f ${SSHKEYFILE}.aws.keys -o -f ${SSHKEYFILE}.online.keys ]; then
X		touch ${SSHKEYFILE}
X		sort -u ${SSHKEYFILE} ${SSHKEYFILE}.aws.keys ${SSHKEYFILE}.online.keys > ${SSHKEYFILE}.tmp
X		mv ${SSHKEYFILE}.tmp ${SSHKEYFILE}
X		chown ${fetchkey_user} ${SSHKEYFILE}
X		rm ${SSHKEYFILE}.aws.keys
X		rm ${SSHKEYFILE}.online.keys
X	else
X		echo "Fetching SSH public key failed!"
X	fi
X}
X
Xload_rc_config $name
Xrun_rc_command "$1"
FETCHKEY

sed -i '' -e "s:__user__:${USER}:g" /mnt/usr/local/etc/rc.d/fetchkey

chmod 0555 /mnt/usr/local/etc/rc.d/fetchkey
touch /mnt/firstboot

# /etc/fstab
cat << EOF > /mnt/etc/fstab
/dev/gpt/swap0   none    swap    sw      0       0
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
fetchkey_enable="YES"
zfs_enable="YES"
ifconfig_DEFAULT="SYNCDHCP"
clear_tmp_enable="YES"
dumpdev="NO"
ntpd_enable="YES"
ntpdate_enable="YES"
sendmail_enable="NONE"
sshd_enable="YES"
syslogd_flags="-ssC"
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
