---
layout: post
title: Remotely wiping the disk(s) of a headless linux server
tags: [linux,shell_scripting,sysadmin,ubuntu]
last_modified_at: 2020-03-02 23:03:00
---

Seldom, the subject of how to wipe the disk(s) of a headliness linux server comes up; there are a few resources online about it. This blog summarizes all the information around into a clean, stable and generic script that can be used in order to perform this task.

As typical of this blog, the script is also used as an exercise in shell scripting and system administration, therefore, it contains (arguably) useful/interesting commands/concepts.

Contents:

- [Preamble/specifications](/Remotely-wiping-the-disks-of-a-headless-linux-server#preamblespecifications)
- [Procedure](/Remotely-wiping-the-disks-of-a-headless-linux-server#procedure)

## Preamble/specifications

There is a variety of details that can be changed/implemented (eg. nohup, [more] secure wiping, devices ordering...). The current implementation is (relatively) basic but solid, usable with typical setups.

The script creates a chrooted minimal environment, and from there, it wipes the machine disks.

The target machine is any Debian-based one, although, with minimal changes (`debootstrap` tool installation, and service stop), it will work on any distribution.

## Procedure

All the commands must be run as root.

Install the program for creating a minimal environment:

```sh
apt install debootstrap
```

During the wipe, the filesystem will be destroyed, however, some pages may be written to disk. Therefore, we want to minimize all the potential write sources.

Check the running daemons, the stop the required ones (update the list as required):

```sh
ps ax | awk '$5 !~ /^\[/ {print $0}' # exclude system processes

for daemon in cron atd postfix ntp syslog-ng; do
  service $daemon stop 2> /dev/null
done
```

Disable all swaps:

```sh
swapoff -a
```

Flush the system caches:

```sh
echo 3 > /proc/sys/vm/drop_caches
```

Create a minimal environment (in RAM, so that it won't be affected by the wipe):

```sh
mount -t tmpfs tmpfs /mnt

debootstrap --variant=minbase --include=bsdmainutils xenial /mnt

mount --bind /dev /mnt/dev      # mirror /dev and /sys - allows block dev operations to work
mount --bind /sys /mnt/sys      #
mount --bind /proc /mnt/proc    # if /proc is not mirrored, after wiping, the system will crash
```

The `xenial` Ubuntu version is required for the `status=progress` dd option; the package `bsdmainutils` includes `hexdump`, used later for inspection.

A reader kindly reported an error (that I can't reproduce on my system):

```sh
# If, when running the `debootstrap` command, you get:
#
#     E: Failed getting release file https://deb.debian.org/debian/dists/xenial/Release
#
# replace it with:
#
debootstrap --variant=minbase --include=bsdmainutils --arch=amd64 xenial /mnt http://archive.ubuntu.com/ubuntu/
```

Now, switch to the temporary environment!:

```sh
chroot /mnt
```

Find the disks:

```sh
# `lsblk` sample output:
#
#   NAME    MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
#   sda       8:0    0 953,9G  0 disk
#   └─sda1    8:1    0  89,8G  0 part /media/vfio
#   loop3     7:3    0  86,6M  1 loop /snap/core/4571
#   sr0      11:0    1  1024M  0 rom
#
disk_devices=$(lsblk | awk '$6 == "disk" {print $1}' | sort -r)
```

We reverse sort the devices, with the simple assumption that the lexicographically first device (eg. `sda`) is the one containing the system data.

Cycle and wipe them:

```sh
while read -r disk_device; do
  disk_size=$(blockdev --getsize64 "/dev/$disk_device")

  echo "Wiping /dev/$disk_device ($((disk_size / 2**30)) GiB)..."

  # `conv`: sync on completion; `bs`: improve speed.
  #
  dd if=/dev/zero of="/dev/$disk_device" status=progress conv=fdatasync bs=64k
done <<< "$disk_devices"
```

(as an alternative to `status=progress`, the `pv` tool can be used; see comment thread at the end of the page)

With the hexdump tool, we can now inspect, for fun, what's remaining in the disk(s):

```sh
while read -r disk_device; do
  echo "/dev/$disk_device content:"
  hexdump -C "/dev/$disk_device" | more
  echo
done <<< "$disk_devices"
```

The result is lean and easy to inspect; since hexdump doesn't show duplicate rows, the dump will be relatively short. Typically, a few pages are still written after the wipe.

Shutdown the system:

```sh
# At this stage, the `shutdown` command is not available anymore [in the host].
# Also, we don't need to exit from the guest, as the command is sent directly to the kernel.
echo 1 > /proc/sys/kernel/sysrq
echo o > /proc/sysrq-trigger
```
