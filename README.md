# Setup

Fabrik images need a work/kernel for the host and a custom world for the jails.

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
