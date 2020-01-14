---
layout: post
title: Installing Ubuntu on a ZFS root, with encryption and mirroring
tags: [filesystems,linux,storage,sysadmin,ubuntu]
last_modified_at: 2010-01-14 11:23:00
---

2019 is a very exciting year for people with at least a minor interest in storage. First, in May, the ZFS support for encryption and trimming has been added, with the release 0.8; then, in August, Canonical has officially announced the plan to add ZFS support to the installer[¹](#footnote01) in the next Ubuntu release.

As of now, achieving a full-ZFS system (with a ZFS root (`/`)) is possible, although non trivial. In this walkthrough, I've made the procedure as simple as possible, additionally setting up encryption and mirroring (RAID-1).

I'll also give an introduction about the concepts involved, so that one has better awareness of the purpose of all the steps (but feel free to jump directly to [the procedure](#procedure)).

Note that this guide is stable, but I'll keep adding a few more sections and content in general.

Contents:

- [Update](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#update)
- [An introduction to the concepts involved](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#an-introduction-to-the-concepts-involved)
  - [The boot process: BIOS and EFI](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#the-boot-process-bios-and-efi)
  - [GRUB](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#grub)
  - [The `/boot` directory/mount](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#the-boot-directorymount)
  - [`/boot` vs. `/boot/efi`](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#boot-vs-bootefi)
  - [Ubuntu's ZFS support](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#ubuntus-zfs-support)
  - [Chroot](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#chroot)
  - [Udev](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#udev)
  - [ZFS pools, filesystems and volumes](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#zfs-pools-filesystems-and-volumes)
- [Philosophy and limitations](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#philosophy-and-limitations)
- [Procedure](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#procedure)
- [Tweaks](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#tweaks)
- [Conclusion](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#databases)
- [Footnotes](/Installing-Ubuntu-on-a-ZFS-root-with-encryption-and-mirroring#footnotes)

## Update

I've turned this article into a program that simplifies and automates the entire procedure, so check it out [on GitHub](https://github.com/saveriomiroddi/zfs-installer)!

For this reason, I'm not going to update and extend this article any more, although, the content may still be of general interest.

## An introduction to the concepts involved

### The boot process: BIOS and EFI

For a very long time, the BIOS boot has been used, and it's still in use. It involves loading some very small code ([up to 446 (!) bytes](https://en.wikipedia.org/wiki/Master_boot_record#Sector_layout)) at a fixed position in the first disk, then following a series of stages ([four (!), in the case of GRUB](https://en.wikipedia.org/wiki/GNU_GRUB#Version_2_(GRUB_2))) before the bootloader presents the menu (or directly loads the O/S).

In the last few years (2010s), motherboards are based on the so-called "EFI" firmware. The boot process provided by it is much more streamlined: it just requires a FAT32 partition with the `ESP` flag ("EFI System Partition") set, and the bootloader(s) installed following the required filename conventions.

Needless to say, the EFI boot is much more convenient: no more multiple stages, fixes disk positions, etc.

The EFI operating system bootloaders are stored in the EFI partition following the structure `EFI/<system>/<bootloader binary>.efi`. Since in Linux, this partition is mounted under `/boot/efi`, one will find them, after boot, as `/boot/efi/EFI/<system>/<bootloader binary>.efi`; the GRUB (main) entry is `/boot/efi/EFI/ubuntu/grubx64.efi`.

### GRUB

The standard Linux bootloader, GRUB, includes drivers for many filesystems, although in a limited form; for example, ZFS is supported, but only with the read-only features (this will affect the boot volume setup, and will be explained later in the article).

GRUB uses a configuration (file): the entries displayed (and the associated boot parameters) are separately configured, they're not dynamically discovered. This is why in some situations, users are asked to run `update-grub`; during typical desktop workflows though, the configuration is always performed automatically when required - for example, when upgrading the kernel.

### The `/boot` directory/mount

The `boot` directory is typically included in the root filesystem. One can easily verify this:

```sh
$ df -h /boot
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2        30G   18G   11G  63% /
```

We observe that `/boot` belongs to the `/` filesystem.

In more complex configurations though, it's on a separate partition; this is the mount on an Ubuntu system with full disk encryption:

```sh
$ df -h /boot
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2       705M  245M  410M  38% /boot
```

Why?

Well, I've mentioned how GRUB has support for many filesystems, but in limited form. On more complex configurations (e.g. encryption, RAID...), GRUB is not able to mount the root partition. Therefore, the kernel image, along with the required modules, are stored on a partition that can be read by GRUB; the kernel then, after loading, is equipped to read every partition needed (in fact, it does typically re-mounts root).

### `/boot` vs. `/boot/efi`

The presence of two nested mounts begs the question: is it possible to use a single partition for both? Sure. EFI defines what it needs to find, not what else is present. It's just a bit confusing, because the files will be mounted with a different structure than usual:

- the `/boot/efi/EFI` mount will be `/boot/EFI`;
- the grub support files will be mixed with the EFI binary files;
- the kernel files will end up stored on a FAT32 partition (there's nothing wrong with it, it's just not very Unix-y).

In this article, I'll follow the conventional setup, and have `/boot` stored on a ZFS volume.

### Ubuntu's ZFS support

There has been, appropriately, a lot of celebration about Canonical's plan to add ZFS support to the official installer (Ubiquity).

However, there is also a common misconception - Ubuntu has been supporting ZFS for a long time: the ZFS module has been preinstalled since v16.04; it just wasn't presented to the user.

Ubuntu Bionic (16.04) bundles the ZFS v0.7 module unfortunately, while we need v0.8 - see the next section.

### Chroot

There's a problem in the setup provided by this article.

We want encryption and trim support (at least, as an option), which have been implemented in [v0.8](https://github.com/zfsonlinux/zfs/releases/tag/zfs-0.8.0). However, ZFS 0.8 is provided only by Ubuntu 19.04 - the older versions, including the latest LTS (18.04) ship the previous version, 0.7.

Assuming we want to install Ubuntu 18.04, when running the live CD, it's easy to upgrade the ZFS in-memory module and prepare the disk using the upgraded version; however, but after installation, the O/S on the disk will boot using the old module (the installer doesn't care what we have in memory - it goes through a preset list of files to copy, which includes the older ZFS version).

How to solve this problem? [Chroot](https://en.wikipedia.org/wiki/Chroot) comes to the rescue.

Chroot, roughly, swaps the operating system underlying root filesystem. Suppose that we run a live CD, and we want to upgrade the apt packages of an installed system! If we run an apt upgrade operation, the live CD packages will be upgraded[²](#footnote02), not the installed system's. 

What we can do is to mount the installed system root device somewhere (e.g. `/mnt`), and chroot into it - that mountpoint will be the new root (`/`). If now an apt upgrade operation is performed, apt will think that it's running from the disk, and upgrade the system as it would regularly do.

Due to the support for this type of operations, chroot is a very well known tool in the domain of system recovery.

### Udev

Udev is the modern Linux subsystem for managing devices. It's not necessary for this installation, however, it's a cool tool to use when working with devices - in this case, excluding removable devices when searching for disks.

### ZFS pools, filesystems and volumes

For those who are not familiar with the basic ZFS concepts:

- pools: the top-level storage unit in ZFS; there can be many. It can be imagined, very roughly, as a storage device (e.g. a disk, or a mirror of disks).
- datasets: the containers for the ZFS filesystems; they belong to a pools, and can be nested. It can be imagine, very roughly, as a disk partition, but much more flexibly.
- volumes: a virtual block device; they belong to a pool. Since they are effectively block devices, they can be formatted (and/or used) at will, e.g. with ext4.

## Philosophy and limitations

There are already several guides on ZFS root/encrypted installations.

I wrote this guide for mostly two reasons:

1. I wanted the most streamlined possible version of an installation procedure; no redundant operations, conditionals, edge cases, advanced options etc.;
1. I needed to get a good idea of the involved concepts; I don't like blindly following a series of steps.

As a consequence, this guide:

1. can be run straight being to end, with the only manual operations to run being using the installer interface;
1. there are no conditionals "if you want X, do Y" - one set the variables as wished, at the very beginning, then copy/paste the rest;
1. the configuration chosen is the simplest possible one (of course, with encryption/mirroring (RAID-1));

Point 3. is also a limitation of this guide:

- only the EFI boot is supported;
- the EFI partition is not mirrored.

These limitations are intentional. I believe it's easier to provide a simplified procedure, which can be after used as a base to add the desired features.

## Requirements and specifications

The requirements are:

- the system must have an EFI firmware;
- the installation is performed from an Ubuntu 18.04 Live CD;
  - it can also be a flash key;
- the target system must have at least one or two disks, of the same size;
  - they can be IDE/SATA/NVMe, also mixed;
  - the NVMe disk will be always used as first disk, if present;
  - the first disk is always the `1`-indexed (e.g. `sda1` in case of SATA).

The specifications are:

- two ZFS pools, boot (`bpool`) and root (`rpool`);
- the root can be encrypted, if desired;
- both pools can be in mirroring (RAID-1), if desired;
- a standard 2 GiB swap volume is configured.

## Procedure

The procedure is executed from a live system, in the terminal, as root. Don't close the terminal at any point! All the instructions below to a single execution.

#### EFI check

Let's double check that the system had an EFI boot:

```sh
ls -l /sys/firmware/efi
```

if there is any content, we're set.

#### Preparations

Setup the variables:

```sh
encrypt_pool=yes
mirror_pool=yes
```

anything other than `yes` will be considered a no.

#### Install the ZFS module in the live (loaded) kernel

Install the ZFS module, and reload it:

```sh
add-apt-repository --yes ppa:jonathonf/zfs
apt install --yes zfs-dkms

systemctl stop zfs-zed
modprobe -r zfs
modprobe zfs
systemctl start zfs-zed
```

(for unclear reasons, the spl module is not reloaded, so we need to manually do it)

#### Find the disks

We find the disks, ignoring the removable devices, via the cool™ Linux tools/systems (Udev, sort, awk...):

```sh
removable_devs_expression=

for device in /sys/block/sd*; do
  (udevadm info --query=property --path=$device | grep -q "^ID_BUS=usb") && removable_devs_expression+="|$(basename $device)"
done

first_disk_id=$(ls -l /dev/disk/by-id/* | sort -t '/' -k 7 -u | grep -vP "/${removable_devs_expression:1}\$" | awk '/\/(nvme0n|sd).$/ {print $9; exit}')
second_disk_id=$(ls -l /dev/disk/by-id/* | sort -t '/' -k 7 -u | grep -vP "/${removable_devs_expression:1}\$" | awk '/\/(nvme0n|sd).$/ {getline; print $9; exit}')
```

#### Prepare the disk(s)

Prepare the partitions:

```sh
sgdisk --zap-all $first_disk_id

sgdisk -n1:1M:+512M   -t1:EF00 $first_disk_id # EFI boot
sgdisk -n2:0:+512M    -t2:BF01 $first_disk_id # Boot pool
sgdisk -n3:0:0        -t3:BF01 $first_disk_id # Root pool

if [[ "$mirror_pool" == "yes" ]]; then
  sgdisk --zap-all $second_disk_id

  sgdisk -n1:+512M:+512M -t1:BF01 $second_disk_id # Boot pool
  sgdisk -n2:0:0         -t2:BF01 $second_disk_id # Root pool
fi
```

The `EF00`/`BF01` labels are the hex codes of the [partiton types](https://en.wikipedia.org/wiki/Partition_type). Interestingly, we use the Solaris type (`BF`) - ZFS was originally developed for this O/S.

Now create the EFI partition:

```sh
mkfs.fat -F 32 -n EFI ${first_disk_id}-part1
```

The ZFS boot pool:

```sh
if [[ "$mirror_pool" == "yes" ]]; then
  bpool_mirror_arg=${second_disk_id}-part1
fi

# See https://github.com/zfsonlinux/zfs/wiki/Ubuntu-18.04-Root-on-ZFS for the details.
#
# `-d` disable all the pool features;
# `-R` creates an "Alternate Root Point", which is lost on unmount; it's just a convenience for a temporary mountpoint;
# `-O` is used to set filesystem properties on a pool (pools and filesystems are distincted entities, however, a pool includes an FS by default).
#
zpool create \
  -d \
  -o ashift=12 \
  -O devices=off -O mountpoint=/boot -R /mnt \
  bpool mirror ${first_disk_id}-part2 $bpool_mirror_arg
```

which has all the features disabled (for compatibility with GRUB); since the boot partition is hardly used during everyday work, it's not worth any hassle of trying to tweak the performance (except the basic [`ashift`](http://open-zfs.org/wiki/Performance_tuning#Alignment_Shift_.28ashift.29)).

The root ZFS pool, with performance tweaks:

```sh
if [[ "$encrypt_pool" == "yes" ]]; then
  encryption_options=(-O encryption=on -O keylocation=prompt -O keyformat=passphrase)
fi
if [[ "$mirror_pool" == "yes" ]]; then
  rpool_mirror_arg=${second_disk_id}-part2
fi

zpool create \
  "${encryption_options[@]}"\
  -o ashift=12 -O acltype=posixacl -O compression=lz4 -O dnodesize=auto -O relatime=on -O xattr=sa \
  -O normalization=formD \
  -O devices=off -O mountpoint=/ -R /mnt \
  rpool mirror ${first_disk_id}-part3 $rpool_mirror_arg
```

Create the swap volume (`/etc/fstab` is configured later):

```sh
zfs create \
  -V 2G -b $(getconf PAGESIZE) \
  -o compression=zle -o logbias=throughput -o sync=always -o primarycache=metadata -o secondarycache=none -o com.sun:auto-snapshot=false \
  rpool/swap

mkswap -f /dev/zvol/rpool/swap
```

#### Install Ubuntu

Create a temporary destination volume:

```sh
zfs create -V 10G rpool/ubuntu-temp
```

Now run the standard Ubuntu installer (without installing GRUB, as we're going to do it manually). At the partitioning stage, do:

- check `Something Else` -> `Continue`
- select `zd16` (the `zd` one without `swap`) -> `New Partition Table` -> `Continue`
- select `(zd16) free space` -> `+` -> Set `Mount point` to `/` -> `OK`
- `Install Now` -> `Continue`
- at the end, choose `Continue Testing`

```sh
ubiquity --no-bootloader
```

Now copy the installed files to the ZFS root filesystem:

```sh
rsync -av --exclude=/swapfile --info=progress2 --no-inc-recursive --human-readable /target/ /mnt
```

(we don't include extended attributes, as there isn't any file using it in a standard installation)

Finally, unmount and destroy the temporary volume:

```sh
swapoff -a
umount /target
zfs destroy rpool/ubuntu-temp
```

we need to swap off, since Ubiquity leaves the swap enabled on the installation partition (mounted as `/target`).

#### Chroot and prepare the jail

Chroot into the ZFS root filesystem:

```sh
for mnt in proc sys dev; do
  mount --rbind /$mnt /mnt/$mnt
done

# Pass the first disk id, so we don't need to find it again.
first_disk_id=$first_disk_id chroot /mnt
```

(by the way, chrooted environments are called "jails")

We set a temporary DNS, because the systemd resolver is stored under `/run`, which is not mounted:

```sh
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
```

#### Install ZFS 0.8 packages

```sh
add-apt-repository --yes ppa:jonathonf/zfs
apt install --yes zfs-initramfs zfs-dkms grub-efi-amd64-signed shim-signed
```

#### Install and configure the bootloader

First, make sure the EFI partition is in the fstab:

```sh
echo PARTUUID=$(blkid -s PARTUUID -o value ${first_disk_id}-part1) /boot/efi vfat nofail,x-systemd.device-timeout=1 0 1 > /etc/fstab
```

(we also wipe the previous fstab content).

Now, mount it, and install GRUB on it:

```sh
mkdir /boot/efi
mount /boot/efi

grub-install
```

Now, we configure GRUB, and workaround a warning:

```sh
# We need to specify what to mount as root, otherwise, it's attempted to mount `rpool/`, which
# causes an error.
perl -i -pe 's/(GRUB_CMDLINE_LINUX=")/${1}root=ZFS=rpool /' /etc/default/grub
# Silence `device-mapper: reload ioctl on osprober-linux-sda3  failed: Device or resource busy`
# during grub-probe
echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub

update-grub

umount /boot/efi
```

#### Cloning the EFI partition

On a mirrored setup, we want to make sure that the loss of any disk doesn't prevent the system from working regularly.

In this case, there is a problem though: while the mirroring of boot and root pools is handled by ZFS, the EFI partition is FAT32, which doesn't support mirroring itself (remember: the first stage of boot is running the bootloader from the EFI partition; the kernel is loaded after, from the boot pool).

As a consequence of this, we can't have a 100% mirror that is managed automatically. We can still get a functional mirror by cloning the EFI partition through all the disks:

```sh
dd if="$first_disk_id-part1" of="$second_disk_id-part1"
efibootmgr --create --disk "$second_disk_id" --label "ubuntu-2" --loader '\EFI\ubuntu\grubx64.efi'
```

What we're doing here is very simple:

- we clone the EFI partition from the first disk to the second;
- we add the partition to the list of UEFI boot entries (`--create`: "create new variable bootnum and add to bootorder").

If, say, the first disk is now pulled off the system, the firmware will not find the EFI partition on the first disk, and will try (and succeed) to boot from the EFI partition on the second disk.

There are two concepts to be aware of.

First, the EFI partitions are not automatically synced. If the user makes a breaking change to the system (say, rename the root pool), and consequently make a change in the bootloader configuration, **and** the disk with the updated EFI partition breaks, the system won't load.  
Generally speaking, this is unlikely to happen in real world, since, outside test/experimental setups, this type of change is atypical.  
Regardless, a solution to this problem is to write a package manager hook, so that after the grub configuration changes, the partitions are synced (at a quick glance, dpkg triggers should be the appropriate solution).

Second, important!, this is a perfectly working solution, but it's also very cheap. Since the EFI partitions are clones, the Linux system won't be able to discern them, therefore, the partition to be mounted on `/boot/efi` will be randomly chosen between the disks.
This is not a problem, however, a better solution (not explained here; currently to be implemented in the `zfs-installer` project), is to clone the content rather than the partition.

All in all, this strategy works in real life, but of course, users need to be aware of the consequences.

#### Configure the boot pool import, and remaining settings

In order to mount the boot pool during boot, we need to create a systemd unit, and set the mount in the fstab:

```sh
cat > /etc/systemd/system/zfs-import-bpool.service <<UNIT
[Unit]
DefaultDependencies=no
Before=zfs-import-scan.service
Before=zfs-import-cache.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/zpool import -N -o cachefile=none bpool

[Install]
WantedBy=zfs-import.target
UNIT

systemctl enable zfs-import-bpool.service

zfs set mountpoint=legacy bpool
echo "bpool /boot zfs nodev,relatime,x-systemd.requires=zfs-import-bpool.service 0 0" >> /etc/fstab
```

Now the remaining settings:

```sh
# Configure the swap volume
echo /dev/zvol/rpool/swap none swap discard 0 0 >> /etc/fstab

# Disable suspend/resume from/to disk
echo RESUME=none > /etc/initramfs-tools/conf.d/resume
```

### End

Exit from the chroot, and unmount the bind mounts:

```sh
exit

for mnt in dev sys proc; do
  umount --recursive --force --lazy /mnt/$mnt
done
```

Export the pools, so that they're flushed and closed (also, so that on boot, ZFS doesn't think they're in use by another system):

```sh
zpool export -a
```

At this point, just remove the medium and perform a hard reset (this is expected, due to the chroot session, which doesn't guarantee the live system consistency).

## Tweaks

### Databases

If databases data is stored on a ZFS filesystem, it's better to create a separate dataset with several tweaks:

```sh
zfs create -o recordsize=8K -o primarycache=metadata -o logbias=throughput -o mountpoint=/path/to/db_data rpool/db_data
```

- `recordsize`: match the typical RDBMSs page size (8 KiB)
- `primarycache`: disable ZFS data caching, as RDBMSs have their own
- `logbias`: essentially, disabled log-based writes, relying on the RDBMSs' integrity measures (see detailed [Oracle post](https://blogs.oracle.com/roch/synchronous-write-bias-property))

## Conclusion

To paraphrase an ex colleague of mine, "Can Windows do this?"[³](#footnote03).

Enjoy rock-solid, greatly flexible, feature-packed storage 😉.

## Footnotes

<a name="footnote01">¹</a>: To be precise, Ubuntu has already bult-in support for ZFS, in the form of a kernel module, since at least 16.04; what's groundbreaking is that, with support in the installer, it will be trivial to setup a full-ZFS system.<br/>
<a name="footnote02">²</a>: Typically, in memory.<br/>
<a name="footnote03">³</a>: Steve also says you can't do this on OS X 🙄.<br/>
