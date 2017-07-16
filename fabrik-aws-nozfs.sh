#!/bin/sh
set -e

# ----------------------------------------------------------------------------
# fabrik.sh - All in one script to create the disk.raw image
# ----------------------------------------------------------------------------
NUMBER_OF_CORES=`sysctl -n hw.ncpu`
FREEBSD_VERSION=11
USER=devops
PASSWORD=fabrik
ZPOOL=zroot
WRKDIR=/fabrik/aws-nozfs
KERNEL=FABRIKAWS

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

write "Fetching src.conf, src-jail.conf, make.conf, fabrik.kernel"
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/src.conf -o /etc/fabrik-src.conf
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/src-jail.conf -o /etc/src-jail.conf
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/make-aws.conf -o /etc/fabrik-aws-make.conf
fetch --no-verify-peer -a https://rawgit.com/fabrik-red/images/master/fabrik-aws.kernel -o /usr/src/sys/amd64/conf/${KERNEL}

write "Creating ${WRKDIR} dir"
mkdir -p ${WRKDIR}/host
mkdir -p ${WRKDIR}/jail

write "building world, kernel and jail world"
cd /usr/src
env MAKEOBJDIRPREFIX=${WRKDIR}/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-aws-make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildworld
env MAKEOBJDIRPREFIX=${WRKDIR}/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-aws-make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildkernel KERNCONF=${KERNEL}
# env MAKEOBJDIRPREFIX=${WRKDIR}/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/fabrik-aws-make.conf make -DNO_CLEAN -j${NUMBER_OF_CORES} buildworld

# ----------------------------------------------------------------------------
# Creating disk.raw
# ----------------------------------------------------------------------------
cd ${WRKDIR}
IMAGE=ec2
VMSIZE=1g
SWAPSIZE=1G
LOGDIR=${WRKDIR}/tmp
mkdir -p ${LOGDIR}

rm -f ${IMAGE}
rm -f ${IMAGE}.raw
rm -f ${IMAGE}.vmdk
truncate -s ${VMSIZE} ${IMAGE}
mddev=$(mdconfig -a -t vnode -f ${IMAGE})
newfs /dev/${mddev}
mount /dev/${mddev} /mnt

write "Installing world, kernel and jail world"
cd /usr/src;
env MAKEOBJDIRPREFIX=${WRKDIR}/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-aws-make.conf make DESTDIR=/mnt installworld 2>&1 | tee ${LOGDIR}/host-installworld.log && \
env MAKEOBJDIRPREFIX=${WRKDIR}/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-aws-make.conf make DESTDIR=/mnt installkernel KERNCONF=${KERNEL} 2>&1 | tee ${LOGDIR}/host-installkernel.log && \
env MAKEOBJDIRPREFIX=${WRKDIR}/host/obj SRCCONF=/etc/fabrik-src.conf __MAKE_CONF=/etc/fabrik-aws-make.conf make DESTDIR=/mnt distribution 2>&1 | tee ${LOGDIR}/host-distribution.log

# create jails dir
#mkdir -p /mnt/jails/base

# installworld & distribution for jail
#env MAKEOBJDIRPREFIX=${WRKDIR}/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/fabrik-aws-make.conf make DESTDIR=/mnt/jails/base installworld 2>&1 | tee ${LOGDIR}/jail-installworld.log && \
#env MAKEOBJDIRPREFIX=${WRKDIR}/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/fabrik-aws-make.conf make DESTDIR=/mnt/jails/base distribution 2>&1 | tee ${LOGDIR}/jail-distribution.log

mkdir -p /mnt/dev
mount -t devfs devfs /mnt/dev
chroot /mnt /etc/rc.d/ldconfig forcestart
umount /mnt/dev

write "Creating user ${USER} with password ${PASSWORD}"
chroot /mnt pw useradd ${USER} -m -G wheel -s /bin/csh -h 0 <<EOP
${PASSWORD}
EOP

cp /etc/resolv.conf /mnt/etc/resolv.conf

write "Installing curl"
yes | chroot /mnt /usr/bin/env ASSUME_ALWAYS_YES=yes pkg install -qy curl > /dev/null 2>&1
chroot /mnt /usr/bin/env ASSUME_ALWAYS_YES=yes pkg clean -qya > /dev/null 2>&1
rm -rf /mnt/var/db/pkg/repo*

write "Creating firstboot scripts"
chroot /mnt mkdir -p /usr/local/etc/rc.d
touch /mnt/firstboot
touch /mnt/firstboot-reboot

# ----------------------------------------------------------------------------
# AWS - firstboot
# ----------------------------------------------------------------------------
sed 's/^X//' >/mnt/usr/local/etc/rc.d/aws_firstboot << 'AWS_FIRSTBOOT'
X#!/bin/sh
X
X# KEYWORD: firstboot
X# PROVIDE: aws_firstboot
X# REQUIRE: NETWORKING
X# BEFORE: LOGIN
X
X: ${user=__user__}
X
X. /etc/rc.subr
X
Xname=aws_firstboot
Xrcvar=aws_firstboot_enable
Xstart_cmd="${name}_run"
X
XSSHKEYURL="http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key"
X
Xaws_firstboot_run()
X{
X	eval SSHKEYFILE="~${user}/.ssh/authorized_keys"
X
X	echo "Fetching SSH public key AWS"
X	mkdir -p `dirname ${SSHKEYFILE}`
X	chmod 700 `dirname ${SSHKEYFILE}`
X	chown ${user} `dirname ${SSHKEYFILE}`
X	ftp -q 5 -o ${SSHKEYFILE}.ec2 -a ${SSHKEYURL} >/dev/null
X	if [ -f ${SSHKEYFILE}.ec2 ]; then
X		touch ${SSHKEYFILE}
X		sort -u ${SSHKEYFILE} ${SSHKEYFILE}.ec2		\
X		    > ${SSHKEYFILE}.tmp
X		mv ${SSHKEYFILE}.tmp ${SSHKEYFILE}
X		chown ${user} ${SSHKEYFILE}
X		rm ${SSHKEYFILE}.ec2
X	else
X		echo "Fetching SSH public key failed!"
X	fi
X}
X
Xload_rc_config $name
Xrun_rc_command "$1"
AWS_FIRSTBOOT
sed -i '' -e "s:__user__:${USER}:g" /mnt/usr/local/etc/rc.d/aws_firstboot
chmod 0555 /mnt/usr/local/etc/rc.d/aws_firstboot

# ----------------------------------------------------------------------------
# .cshrc
# ----------------------------------------------------------------------------
sed 's/^X//' >/mnt/root/.cshrc << 'CSHRC'
Xalias h  history 25
Xalias j  jobs -l
Xalias la ls -aF
Xalias lf ls -FA
Xalias ll ls -lAF
Xalias rm rm -i
Xalias mv mv -i
Xalias cp cp -i
X
X# A righteous umask
Xumask 22
X
Xset path = (/sbin /bin /usr/sbin /usr/bin /usr/local/sbin /usr/local/bin $HOME/bin)
X
Xsetenv EDITOR vi
Xsetenv PAGER less
Xsetenv BLOCKSIZE  K
Xsetenv CLICOLOR
Xsetenv LSCOLORS gxfxcxdxbxegedabagacad
X
Xset COLOR1="%{\e[0;32m%}"
Xset COLOR2="%{\e[0;33m%}"
Xset COLOR3="%{\e[0;36m%}"
Xset COLOR4="%{\e[0;0m%}"
Xset COLOR5="%{\e[0;33m%}"
X
Xif ($?prompt) then
X  if ($uid == 0) then
X    set COLOR3="%{\e[1;31m%}"
X    set user = root
X  endif
X  set prompt="$COLOR2\[$COLOR3%n@%M$COLOR2\:$COLOR1%~$COLOR2\] [%p %d]\n$COLOR5>$COLOR4 "
X  set promptchars = "%#"
X
X  set filec
X  set history = 1000
X  set savehist = (1000 merge)
X  set autolist = ambiguous
X  set autoexpand
X  set autorehash
X  set mail = (/var/mail/$USER)
X  if ( $?tcsh ) then
X    bindkey "^W" backward-delete-word
X    bindkey -k up history-search-backward
X    bindkey -k down history-search-forward
X  endif
X
Xendif
CSHRC
cp -f /mnt/root/.cshrc /mnt/usr/home/devops/.cshrc

# /etc/fstab
cat << EOF > /mnt/etc/fstab
/dev/gpt/rootfs   /       ufs     rw      1       1
/dev/gpt/swapfs   none    swap    sw      0       0
EOF

# /boot/loader.conf
cat << EOF > /mnt/boot/loader.conf
autoboot_delay="-1"
beastie_disable="YES"
boot_multicons="YES"
console="comconsole,vidconsole"
hw.broken_txfifo="1"
hw.memtest.test="0"
hw.vtnet.mq_disable="1"
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
kern.timecounter.hardware=ACPI-safe
EOF

# /etc/rc.conf
cat << EOF > /mnt/etc/rc.conf
aws_firstboot_enable="YES"
growfs_enable="YES"
hostname="fabrik" # change to your desired hostname
ifconfig_DEFAULT="SYNCDHCP -tso"
clear_tmp_enable="YES"
dumpdev="NO"
ntpd_enable="YES"
ntpdate_enable="YES"
sendmail_enable="NONE"
sshd_enable="YES"
syslogd_flags="-ssC"
#-----------------------------------------------------------------------
# jails
#-----------------------------------------------------------------------
jail_enable="NO"
jail_list="base"
EOF

# /etc/pf.conf
cat << EOF > /mnt/etc/pf.conf
ext_if = "xn0"
set skip on lo
scrub in all
nat on \$ext_if from lo1:network to any -> (\$ext_if)
pass all
EOF

# /etc/sysctl.conf
cat << EOF > /mnt/etc/sysctl.conf
debug.debugger_on_panic=0
debug.trace_on_panic=1
kern.panic_reboot_wait_time=0
net.inet.tcp.tso=0
security.bsd.see_other_gids=0
security.bsd.see_other_uids=0
security.bsd.stack_guard_page=1
security.bsd.unprivileged_proc_debug=0
security.bsd.unprivileged_read_msgbuf=0
EOF

# /etc/jail.conf
cat << EOF > /mnt/etc/jail.conf
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
allow.raw_sockets;
securelevel=3;
host.hostname="\$name.fabrik"; # change to your desired hostname
path="/jails/\$name";

base {
    jid = 10;
    # http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/MultipleIP.html
    # ip4.addr = 172.16.13.2;
}
EOF

# jail rc.conf
#cat << EOF > /mnt/jails/base/etc/rc.conf
#sshd_enable="YES"
#sshd_flags="-4"
#syslogd_flags="-ssC"
#clear_tmp_enable="YES"
#sendmail_enable="NONE"
#cron_flags="\$cron_flags -J 60"
#EOF

# jail /etc/resolv.conf
#cat << EOF > /mnt/jails/base/etc/resolv.conf
#nameserver 84.200.70.40
#nameserver 208.67.222.222
#nameserver 4.2.2.2
#nameserver 2001:4860:4860::8888
#nameserver 2001:1608:10:25::1c04:b12f
#EOF

umount /dev/${mddev}
tunefs -j enable /dev/${mddev}
mdconfig -d -u ${mddev}
chflags -R noschg /mnt
rm -rf /mnt/*


# create raw
BOOTFILES=${WRKDIR}/host/obj/usr/src/sys/boot
mkimg -s gpt -f raw \
    -b ${BOOTFILES}/i386/pmbr/pmbr \
    -p freebsd-boot/bootfs:=${BOOTFILES}/i386/gptboot/gptboot \
    -p freebsd-swap/swapfs::${SWAPSIZE} \
    -p freebsd-ufs/rootfs:=${WRKDIR}/${IMAGE} \
    -o ${WRKDIR}/${IMAGE}.raw

mkimg -s gpt -f vmdk \
    -b ${BOOTFILES}/i386/pmbr/pmbr \
    -p freebsd-boot/bootfs:=${BOOTFILES}/i386/gptboot/gptboot \
    -p freebsd-swap/swapfs::${SWAPSIZE} \
    -p freebsd-ufs/rootfs:=${WRKDIR}/${IMAGE} \
    -o ${WRKDIR}/${IMAGE}.vmdk

END=$(date +%s)
DIFF=$(echo "$END - $START" | bc)

write "Done! build in $DIFF seconds."
