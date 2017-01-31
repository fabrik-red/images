# Setup

Fabrik images need a custom word/kernel for the host and a custom world for the jails.

RAW image:

Router, IPSEC, PF support: https://fabrik.yotta.cloud/file/yotta-cloud/fabrik-freebsd-zfs.tar.gz


no PF: https://fabrik.yotta.cloud/file/yotta-cloud/disk.tar.gz

## Setting up Build Environment

Update sources:

    $ svnlite co svn://svn.freebsd.org/base/stable/11 /usr/src

Configure your `/etc/src.conf` and `/etc/make.conf` based on your needs.

Create a working directory, in this case `/fabrik`:

    $ mkdir -p /fabrik/host/obj
    $ mkdir -p /fabrik/jail/obj

## Build World

    env MAKEOBJDIRPREFIX=/fabrik/host/obj make -j4 buildworld

## Build kernel

    env MAKEOBJDIRPREFIX=/fabrik/host/obj make -j4 buildkernel

## Build jail World

    env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf make -j4 buildworld

> -jX addjust X to the number of CPU cores, in this case 4

## Create raw images

After having the workd and kernel the `zfs.sh` script can be used to create `raw` images.
