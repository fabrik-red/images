# Download

More about Fabrik: https://fabrik.red

To create a jail using with `create-jail.sh`:

    # ./create-jail.sh -p=/jails/foo

Here `/jails` already exists

To mount the `disk.raw`:

```
> zpool import -o readonly=on -d /dev -f -R /mnt
   pool: zroot
     id: 15033985127548010097
  state: ONLINE
 action: The pool can be imported using its name or numeric identifier.
 config:

        zroot        ONLINE
          gpt/disk0  ONLINE
```

Then use:

    zpool import -o readonly=on -d /dev -f -R /mnt 15033985127548010097

If know the pool name:

    zpool import -o readonly=on -d /dev -f -R /mnt zroot

## update existing jail

cd into `/usr/src`:

    env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make -DNO_CLEAN -j16 buildworld

Then stop the jail and install the world:

    env MAKEOBJDIRPREFIX=/fabrik/jail/obj SRCCONF=/etc/src-jail.conf __MAKE_CONF=/etc/make.conf make DESTDIR=/jails/test installworld
