---
layout: post
title: Using a persistent live Ubuntu USB flash drive in VirtualBox
tags: [linux,sysadmin,small,ubuntu]
---

Recently, I needed to test some operations to be performed during the installation of Ubuntu on a system.

This requires multiple sessions and reboots, so retaining the changes on the installation media would considerably streamline the task.


VirtualBox doesn't support booting a VM from a USB flash drive though, so a workaround is required.

This small article explains how to do this.

Contents:

- [Options and procedure(s)](/Using-a-persistent-live-ubuntu-usb-flash-drive-in-virtualbox.md#options-and-procedures)
  - [Using the VMDK format](/Using-a-persistent-live-ubuntu-usb-flash-drive-in-virtualbox.md#using-the-vmdk-format)
  - [Using the key dump as a disk](/Using-a-persistent-live-ubuntu-usb-flash-drive-in-virtualbox.md#using-the-key-dump-as-a-disk)
- [Conclusion and considerations](/Using-a-persistent-live-ubuntu-usb-flash-drive-in-virtualbox.md#conclusion-and-considerations)

## Introduction, and options

The standard Ubuntu live system - which in the past was on CD, while nowadays on USB flash drives - doesn't persist changes; they're applied in-memory, and lost on shutdown.

Some live media tools though (but currently, not the standard Ubuntu installation tool), can create a so-called "persistent live" system on a flash drive.

Now, the problem is to make the system accessible from a (VirtualBox) virtual machine; there are currently two options.

### Using the VMDK format

The `VMDK` format is the format typically used by VMWare products, and supported (but not used by default) by VirtualBox.

It's a very flexible format. The relevant functionality in this case is the "Raw device mapping": the VMDK file simply acts as a proxy for a device.

With this functionality, using a flash key is simple: one creates the proxy VMDK, then makes the virtual machine use it, so that I/O operations are redirected to the raw device.

The security implications of this setup are very serious, though; therefore, although this is an exact solution to the problem, I won't go into the details; instead, I'll just leave a reference to the [Stack Overflow answer](https://askubuntu.com/a/693729) to a relevant question.

For people interested in raw device mapping (in the context of VMWare products), the VMWare website has a [dedicated guide](https://www.vmware.com/pdf/esx25_rawdevicemapping.pdf).

### Using the key dump as a disk

My first attempts at accomplishing the tasks were to use a loop device associated to a blank file, so that I could instruct the live media tool to create the live system on the file itself, pretending it was a flash key/disk.

These attempts failed because the tools typically available on Ubuntu (`mkusb`, `tuxboot`, `unetbootin`) they don't support loop devices, or persistent live systems, or both.

However, the subsequent solution was very simple.

1. Create the live system

Create the desired live system on the USB flash key, via any tool fulfilling the requirements (I chose `mkusb`).

Note that `mkusb` has a bug that sometimes causes the flash drive write operation to file, resetting to the first menu, without error messages; the workaround I've found to this is to first switch to root user, then invoke `mkusb`:

```sh
username$ sudo su
root# mksub
```

Don't invoke mkusb via sudo:

```sh
username$ sudo mkusb # no!
```

or let it switch:

```sh
username$ mkusb # no!
```

2. Make a disk image that is usable by VirtualBox

Another VirtualBox limitation is that it doesn't directly support raw disk images, so we should assume that another step - the conversion - is required after dumping.

Turns out, it's not needed at all. Let's create a VDI image directly from the flash drive:

```sh
disk_device=/dev/sdb # change according to the case
VBoxManage convertfromraw -format VDI $disk_device ubuntu_live.vdi
```

This is a bit ugly; there is no progress! So let's pipe from stdin, instead:

```sh
disk_device=/dev/sdb
disk_size=$(sudo blockdev --getsize64 $disk_device)
sudo dd if=$disk_device status=progress | VBoxManage convertfromraw -format VDI stdin ubuntu_live.vdi $disk_size
```

Don't forget to unmount all the partitions before dumping (see my RPI VPN router project [installation file](https://github.com/saveriomiroddi/rpi_vpn_router/blob/master/install_vpn_router.sh) for a neat way to script unmounting).

3. Run the image in a virtual machine

Now we're ready. Create a standard virtual machine, and attach the disk to a controller; there are two options:

- attach it to the IDE controller; this will make it boot by default, but it will also cause the drive to be mapped to `/dev/sda`, which could cause some confusion to the user when (if) it's detached from the controller;
- attach it to the SATA controller; this will require invoking the boot menu (tap F12 on boot), but it won't change the other devices mapping.

## Conclusion and considerations

While originally I preferred the idea of directly using the flash drive in the VM, I changed idea while using the new solution.

I don't really have a use case requiring a single device to be used (I seldom change the content of the system on the flash drive), and if I need, say, to copy anything, I can still attach the key to the VM.

Having the persistent live system in my archive of ready-to-use disk images is actually very practical, so ultimately, the solution has been a win-win.
