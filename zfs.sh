#!/bin/sh
# ----------------------------------------------------------------------------
# Create disk.raw FreeBSD ZFS root
# ----------------------------------------------------------------------------
START=$(date +%s)
RAW=disk.raw
VMSIZE=2g
GH_USER=nbari # fetch keys from http://github.com/__user__.keys"

# ----------------------------------------------------------------------------
zpool list
truncate -s ${VMSIZE} ${RAW}
mddev=$(mdconfig -a -t vnode -f ${RAW})

gpart create -s gpt ${mddev}
gpart add -a 4k -s 512k -t freebsd-boot ${mddev}
gpart add -a 4k -t freebsd-swap -s 1G -l swap0 ${mddev}
gpart add -a 1m -t freebsd-zfs -l disk0 ${mddev}
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ${mddev}

sysctl vfs.zfs.min_auto_ashift=12

zpool create -o altroot=/mnt -o autoexpand=on -O compress=lz4 -O atime=off zroot /dev/gpt/disk0
zfs create -o mountpoint=none zroot/ROOT
zfs create -o mountpoint=/ zroot/ROOT/default
zfs create -o mountpoint=/tmp -o exec=off -o setuid=off zroot/tmp
zfs create -o mountpoint=/usr -o canmount=off zroot/usr
zfs create -o mountpoint=/usr/home zroot/usr/home
zfs create -o mountpoint=/usr/ports -o setuid=off zroot/usr/ports
zfs create zroot/usr/src
zfs create -o mountpoint=/var -o canmount=off zroot/var
zfs create -o exec=off -o setuid=off zroot/var/audit
zfs create -o exec=off -o setuid=off zroot/var/crash
zfs create -o exec=off -o setuid=off zroot/var/log
zfs create -o exec=off -o setuid=off -o readonly=on zroot/var/empty
zfs create -o atime=on zroot/var/mail
zfs create -o setuid=off zroot/var/tmp
zfs create zroot/var/ports
zfs create zroot/usr/obj
zpool set bootfs=zroot/ROOT/default zroot

cd /usr/src; make DESTDIR=/mnt installworld && \
    make DESTDIR=/mnt installkernel && \
    make DESTDIR=/mnt distribution

mkdir -p /mnt/dev
mount -t devfs devfs /mnt/dev
chroot /mnt /usr/bin/newaliases
chroot /mnt /etc/rc.d/ldconfig forcestart
umount /mnt/dev

# /etc/resolv.conf
cat << EOF > /mnt/etc/resolv.conf
nameserver 4.2.2.2
nameserver 8.8.8.8
nameserver 2001:4860:4860::8888
nameserver 2001:1608:10:25::1c04:b12f
EOF

# user fetch keys from github
chroot /mnt mkdir -p /usr/local/etc/rc.d
sed 's/^X//' >/mnt/usr/local/etc/rc.d/fetchkey << 'FETCHKEY'
X#!/bin/sh
X
X# KEYWORD: firstboot
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
XSSHKEYURL="https://github.com/${fetchkey_user}.keys"
X
Xfetchkey_run()
X{
X	# If the user does not exist, create it.
X	if ! grep -q "^${fetchkey_user}:" /etc/passwd; then
X		echo "Creating user ${fetchkey_user}"
X		pw useradd ${fetchkey_user} -m -G wheel
X	fi
X
X	# Figure out where the SSH public key needs to go.
X	eval SSHKEYFILE="~${fetchkey_user}/.ssh/authorized_keys"
X
X	# Grab the provided SSH public key and add it to the
X	# right authorized_keys file to allow it to be used to
X	# log in as the specified user.
X	echo "Fetching SSH public key for ${fetchkey_user}"
X	mkdir -p `dirname ${SSHKEYFILE}`
X	chmod 700 `dirname ${SSHKEYFILE}`
X	chown ${fetchkey_user} `dirname ${SSHKEYFILE}`
X	fetch --no-verify-peer -o ${SSHKEYFILE}.keys -a ${SSHKEYURL} >/dev/null
X	if [ -f ${SSHKEYFILE}.keys ]; then
X		touch ${SSHKEYFILE}
X		sort -u ${SSHKEYFILE} ${SSHKEYFILE}.keys > ${SSHKEYFILE}.tmp
X		mv ${SSHKEYFILE}.tmp ${SSHKEYFILE}
X		chown ${fetchkey_user} ${SSHKEYFILE}
X		rm ${SSHKEYFILE}.keys
X	else
X		echo "Fetching SSH public key failed!"
X	fi
X}
X
Xload_rc_config $name
Xrun_rc_command "$1"
FETCHKEY

sed -i '' -e "s:__user__:${GH_USER}:g" /mnt/usr/local/etc/rc.d/fetchkey

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

zpool export zroot
mdconfig -d -u ${mddev}
chflags -R noschg /mnt
rm -rf /mnt/*

END=$(date +%s)
DIFF=$(echo "$END - $START" | bc)

echo ----------------------------------------------------------------------------
echo "build in $DIFF seconds."
echo ----------------------------------------------------------------------------
