---
layout: post
title: Quickly building a custom Linux (Ubuntu) kernel, with modified configuration (kernel timer frequency)
tags: [linux,small,sysadmin,ubuntu]
last_modified_at: 2020-03-16 23:43:00
---

Recently, I had to build a custom Linux kernel with a modified configuration (specifically, a modified kernel timer frequency).

This is a relatively typical task, so there is plenty of information around, however, I've found lack of clarity about the concepts involved, outdated and incompleted information, etc.

For this reason, I've decided to write a small guide about this task, in the form of a truly-hassle-free-copy-paste™ set of commands, with some clarifications.

As per my blogging style, I've spiced the script up with some (Linux/Scripting/Regex)-fu - of course, for the lulz™.

Content:

- [Requirements](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#requirements)
- [Procedure](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#procedure)
  - [Preparation](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#preparation)
  - [Handling the ZFS module](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#handling-the-zfs-module)
  - [Installing the build dependencies and the kernel source packages](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#installing-the-build-dependencies-and-the-kernel-source-packages)
    - [Alternative sources for the Linux kernel source](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#alternative-sources-for-the-linux-kernel-source)
  - [Customizing the kernel configuration](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#customizing-the-kernel-configuration)
    - [Create the default Ubuntu configuration](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#create-the-default-ubuntu-configuration)
    - [Create the default Ubuntu configuration, and customize it](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#create-the-default-ubuntu-configuration-and-customize-it)
    - [Conveniently displaying the changes](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#conveniently-displaying-the-changes)
  - [Building the kernel](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#building-the-kernel)
  - [Installing, rebooting and testing](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#installing-rebooting-and-testing)
- [Conclusion](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#conclusion)
- [References](/Quickly-building-a-custom-linux-ubuntu-kernel-with-modified-configuration-kernel-timer-frequency#references)

## Requirements

This guide is based on Ubuntu systems, however, it can be easily adapter to other systems, in particular, Debian-based ones.

The commands must be executed in a single terminal session, since at least one variable is used multiple times.

Aside the (optional) step where the user interactively configures the kernel, the commands can be pasted into a script that takes care of everything.

## Procedure

### Preparation

Let's create an empty directory, and find out the running kernel version, so that we'll compile the same:

```sh
mkdir linux-ubuntu
cd linux-ubuntu

kernel_release=$(uname -r)
```

### Handling the ZFS module

If the system is running on ZFS, some care needs to be taken (otherwise, ignore this step).

First, we need to install the `zfs-dkms` package (see [StackOverflow question](https://askubuntu.com/questions/1268519/ubuntu-20-04-building-patched-kernel-results-in-no-zfs-support)), in order to compile and add the module to the custom kernel.

Additionally, if running on kernel 5.8+ (e.g Ubuntu Focal HWE), then the ZFS module may not build, so we install version 5.4 (see [Launchpad report](https://bugs.launchpad.net/ubuntu/+source/zfs-linux/+bug/1902701)).

```sh
# Check if the module is running.
#
if lsmod | grep -qP '^zfs\s'; then
  sudo apt install zfs-dkms

  # `uname -r` sample output:
  #
  #     5.8.0-38-generic
  #
  if dpkg --compare-versions "$(uname -r | awk -F. '{ print $1"."$2 }')" ge 5.8; then
    # `apt-cache search` sample output:
    #
    #     linux-image-unsigned-5.4.0-62-generic - Linux kernel image for version 5.4.0 on 64 bit x86 SMP
    #
    kernel_release=$(apt-cache search '^linux-image-unsigned-5.4.[[:digit:]-]+-generic' | perl -ne 'eof && print /unsigned-(\S+)/')
  fi
fi
```

### Installing the build dependencies and the kernel source packages

For simplicity, we're going to download the Ubuntu-specific kernel source packages; they are stored in the source repositories, which are not enabled by default, so we enable them:

```sh
# Source lines to change:
#
#     # deb-src http://de.archive.ubuntu.com/ubuntu/ focal main restricted
#     # deb-src http://de.archive.ubuntu.com/ubuntu/ focal-updates main restricted
#
sudo perl -i.bak -pe "s/^# (deb-src .* $(lsb_release -cs)(-updates)? main restricted$)/\$1/" /etc/apt/sources.list
```

Install the build dependencies:

```sh
# Probably more packages than needed, but it's tedious (and fragile) to find out and install exactly
# the needed ones.
#
sudo apt install kernel-package libncurses5 libncurses5-dev libncurses-dev qtbase5-dev-tools flex \
  bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf

sudo apt build-dep "linux-image-unsigned-$kernel_release"
```

and download/prepare the kernel source packages:

```sh
# We need to install the `unsigned` package, since the `linux-image-$kernel_release` package does not
# include the source.
#
apt source "linux-image-unsigned-$kernel_release"
```

Note that both `apt build-dep` and `apt source` require the source repositories to be enabled.

At this stage, if desired, we can disable the source repositories back:

```sh
sudo mv -f /etc/apt/sources.list{.bak,}
```

#### Alternative sources for the Linux kernel source

There are alternative sources for the kernel source:

- `git://kernel.ubuntu.com/ubuntu/ubuntu-$release_codename.git`: the Ubuntu custom kernel
- `git@github.com:torvalds/linux.git`: the vanilla kernel

although it's more convenient to use the source packages.

### Customizing the kernel configuration

Enter the kernel source directory:

```sh
cd */
```

Now we need to generate the configuration (`.config` file), and optionally modify it.

Modifications to the kernel configuration should not be performed manually; even a single change like the kernel timer frequency may not be a single line change.

Using the kernel source packages (downloaded in the previous section) has the advantage that it includes the changes used by the Ubuntu kernel(s).

Now there are a few options to generate and customize the configuration.

#### Create the default Ubuntu configuration

Run the following:

```sh
make oldconfig
```

#### Create the default Ubuntu configuration, and customize it

In order to create a default Ubuntu configuration, and customize it, run the following:

```sh
make xconfig
```

and edit away!

There is also a terminal tool for the same purpose:

```sh
make menuconfig
```

however, the GUI version is much more practical, since it shows the configuration tree and the subtree entries at the same time, making it much easier to explore it.

For those who want to change the kernel timer frequency, the entry is listed as `Processor type and features` -> `Timer frequency`.

Unnecessary components can be removed, which will save compile time, although it's important to be 100% sure of it 🙂

#### Conveniently displaying the changes

There is a script for conveniently comparing two config files, `scripts/diffconfig`.

If, for example, the configuration was first created via `make oldconfig`, then modified it via `make xconfig`, the backup and current configuration files can be compared via:

```sh
$ scripts/diffconfig .config{.old,}
HZ 250 -> 100
HZ_100 n -> y
HZ_250 y -> n
```

This is clearer than the conventional diff:

```sh
457,458c457,458
< # CONFIG_HZ_100 is not set
< CONFIG_HZ_250=y
---
> CONFIG_HZ_100=y
> # CONFIG_HZ_250 is not set
461c461
< CONFIG_HZ=250
---
> CONFIG_HZ=100
```

### Building the kernel

Time to build the kernel!

It's good practice to add a version modifier, in order to make the kernel recognizable:

```sh
kernel_local_version_modified="timer-100"
fakeroot make-kpkg -j "$(nproc)" --initrd --append-to-version="$kernel_local_version_modified" kernel-image kernel-headers
```

This will take some time (several minutes), and generate two `*.deb` packages in the parent directory.

### Installing, rebooting and testing

Install the generated packages:

```sh
sudo dpkg -i ../*.deb
```

Now reboot; the new kernel will be in the GRUB list.

After booting, one can verify that the changes have been applied:

```sh
$ grep -P '^CONFIG_HZ=\d+$' "/boot/config-$(uname -r)"
CONFIG_HZ=100
```

Yay!

## Conclusion

Although I would have expected the procedure to be trivial, it wasn't. Once the involved concepts were clear though, the procedure became simple and straightforward.

It's now trivially possible for everybody to have a standard-as-desired kernel, with the intended customizations.

Happy kernel hacking!

## References

- [What's a simple way to recompile the kernel?](https://askubuntu.com/questions/163298/whats-a-simple-way-to-recompile-the-kernel)
- [BuildYourOwnKernel](https://wiki.ubuntu.com/Kernel/BuildYourOwnKernel)
- [Compiling the kernel with default configurations](https://unix.stackexchange.com/questions/29439/compiling-the-kernel-with-default-configurations)
- [What does “make oldconfig” do exactly in the Linux kernel makefile?](https://stackoverflow.com/questions/4178526/what-does-make-oldconfig-do-exactly-in-the-linux-kernel-makefile)
- [Where can I get the 11.04 kernel .config file?](https://askubuntu.com/questions/28047/where-can-i-get-the-11-04-kernel-config-file)
- [make config vs oldconfig vs defconfig vs menuconfig vs savedefconfig](http://embeddedguruji.blogspot.com/2019/01/make-config-vs-oldconfig-vs-defconfig.html)
