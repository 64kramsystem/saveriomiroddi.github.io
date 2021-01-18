---
layout: post
title: Quick RISC-V cross compilation and emulation
tags: [hardware,linux,sysadmin,ubuntu,virtualization]
redirect_from:
- Quick_riscv_cross_compilation_and_emulation
last_modified_at: 2020-01-18 11:56:00
---

RISC-V is a hot topic lately. There's lots of talk, and experimentation/research.

Experimenting on the platform is actually easy, through open source tools. In this article I'll explain how to easily setup the RISC-V development and emulation tools, and how to build and run, as example, the parallel gzip compressor ([`pigz`](https://github.com/madler/pigz)).

I'll also show how to configure the QEMU disk image, and a few useful related functionalities.

Content:

- [Introduction to the tooling options](/Quick-riscv-cross-compilation-and-emulation#introduction-to-the-tooling-options)
- [Setup](/Quick-riscv-cross-compilation-and-emulation#setup)
  - [Preliminary steps](/Quick-riscv-cross-compilation-and-emulation#preliminary-steps)
  - [Building the toolchain](/Quick-riscv-cross-compilation-and-emulation#building-the-toolchain)
  - [Building zlib and pigz](/Quick-riscv-cross-compilation-and-emulation#building-zlib-and-pigz)
  - [Downloading and preparing the Fedora RISC-V image](/Quick-riscv-cross-compilation-and-emulation#downloading-and-preparing-the-fedora-risc-v-image)
  - [Installing QEMU](/Quick-riscv-cross-compilation-and-emulation#installing-qemu)
- [Execution!](/Quick-riscv-cross-compilation-and-emulation#execution)
- [Conclusion](/Quick-riscv-cross-compilation-and-emulation#conclusion)
- [Footnotes](/Quick-riscv-cross-compilation-and-emulation#footnotes)

## Introduction to the tooling options

There are a few ways to prepare a RISC-V development environment, and emulate the platform binaries.

In this post, I'll use:

- the official [RISC-V toolchain project](https://github.com/riscv/riscv-gnu-toolchain);
- the prepackaged QEMU, in [system emulation (SoftMMU) mode](https://wiki.qemu.org/Features/SoftMMU).

Alternatives are:

- use the prepackaged RISC-V toolchain;
- compile QEMU from source;
- use the [`riscv-tools` project](https://github.com/riscv/riscv-tools).

Over the next few days, I'll update the post with more details about the alternatives (the prepackaged toolchain makes for an even simpler setup).

The setup is intended to be run on Debian-based (including Ubuntu) distributions, but the concepts can be adapted to other ones.

## Setup

### Preliminary steps

Before starting, we set a few variables, for convenience:

```sh
# The workspace where the projects will be downloaded
#
WORKSPACE_PATH=/path/to/workspace

# Pre-add the cross-compiler to the $PATH.
#
PATH=$WORKSPACE_PATH/riscv-gnu-toolchain/build/bin:$PATH

ZLIB_PROJECT_PATH=$WORKSPACE_PATH/riscv-gnu-toolchain/riscv-gcc/zlib
```

**Do not close/switch terminal** while executing the subsequent sections, as the variables are used across the sections!

### Building the toolchain

```sh
cd "$WORKSPACE_PATH"

# Install the required packages.
#
sudo apt install autoconf automake autotools-dev curl python3 libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat1-dev

# Clone the repository. Will take a lot (it's 3.6+ GiB)!!
#
git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain

# Build the project in a `build` directory. The binaries will be under `build/bin`, which is what we
# added in the preliminary step.
#
mkdir build
cd !$

# Configure and build the Linux cross compiler. The alternative is the so-called "Newlib" cross-compiler,
# which is typically used in embedded environments; since our target is the Fedora distribution, we
# compile the Linux version.
# In order to build the Newlib version, remove the `linux` parameter from the `make` command.
#
../configure --prefix="$PWD"
make linux
```

That was it! Now we have a `riscv64-unknown-linux-gnu-gcc` cross-compiler 🙂

### Building zlib and pigz

Incidentally, the RISC-V GNU toolchain project also includes the `zlib` project, so we don't need to download the original project. The steps for using the original project (hosted [on GitHub](https://github.com/madler/zlib)) are almost identical, so there's no meaningful difference.

```sh
cd "$ZLIB_PROJECT_PATH"

# Configure to use the cross compiler, and compile!
#
# If compiling the original zlib project, remove the `--host` option from the `configure` command.
#
CC=riscv64-unknown-linux-gnu-gcc ./configure --host=x86_64
make
```

Now, let's download, configure and build `pigz`:

```sh
cd "$WORKSPACE_PATH"
git clone https://github.com/madler/pigz.git
cd pigz

# The is now `configure` here, so we specify the cross-compiler, and importantly, the headers and libraries
# location.
#
# Having `zlib1g-dev` installed doesn't work out of the box for this purpose, so we just use the built
# project paths.
#
make "CC=riscv64-unknown-linux-gnu-gcc -I $ZLIB_PROJECT_PATH -L $ZLIB_PROJECT_PATH"
```

We're done! We have a `pigz` that can be run on the RISC-V platform:

```sh
$ file pigz
pigz: ELF 64-bit LSB executable, UCB RISC-V, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-riscv64-lp64d.so.1, for GNU/Linux 4.15.0, with debug_info, not stripped
```

### Downloading and preparing the Fedora RISC-V image

The Fedora foundation produced a RISC-V ready image at the beginning of 2020; this very practical for our purposes.

```sh
# Install the virtual image tools.
#
sudo apt install libguestfs-tools

FEDORA_IMAGE_HTTP_PATH=https://dl.fedoraproject.org/pub/alt/risc-v/repo/virt-builder-images/images

mkdir "$WORKSPACE_PATH/fedora_riscv_image"
cd !$

wget -O- "$FEDORA_IMAGE_HTTP_PATH"/Fedora-Minimal-Rawhide-20200108.n.0-sda.raw.xz | xz -d > Fedora-Minimal-Rawhide-20200108.n.0-sda.raw
wget "$FEDORA_IMAGE_HTTP_PATH"/Fedora-Minimal-Rawhide-20200108.n.0-fw_payload-uboot-qemu-virt-smode.elf

# Make the image sparse (skip the logically unallocated block in the image), in order to increase the
# compression; also, compress the output.
# The standard QEMU tool `qemu-img` supports conversion and compression, but not "sparsification"; the
# `virt-sparsify` tool actually uses `qemu-img` internally.
#
# Sudoing is unfortunately needed with this tool. Errors are not printed by default; in case of problems,
# run via `sudo LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1 virt-sparsify ...`
#
sudo virt-sparsify --convert qcow2 --compress Fedora-Minimal-Rawhide-20200108.n.0-sda.{raw,qcow2}
sudo chown $USER: Fedora-Minimal-Rawhide-20200108.n.0-sda.qcow2

# We don't need the raw image anymore...
#
rm Fedora-Minimal-Rawhide-20200108.n.0-sda.raw

# ... but we create on a convenient diff ("backing") image to work on. In order to rollback to the original
# image, just delete the diff file and recreate a new one.
#
qemu-img create -f qcow2 -b Fedora-Minimal-Rawhide-20200108.n.0-sda.{qcow2,diff.qcow2}
```

### Installing QEMU

The last piece is QEMU; the RISC-V version is included in the package below:

```sh
sudo apt install qemu-system-misc
```

This will install the version provided by the distribution, which is generally fairly recent (e.g. v4.2 on Ubuntu 20.04).

It's quite easy to download and compile from the [original project](https://github.com/qemu/qemu). I maintain [a fork](https://github.com/saveriomiroddi/qemu-pinning), which in addition to make the compilation trivial, also adds the process pinning functionality and other minor tweaks.

## Execution!

Now we'll start the virtual machine and run pigz; note that the diff image is used (see `-drive` option).

```sh
# No more than 8 processors are supported by the `virt` QEMU machine.
#
GUEST_PROCESSORS=8
GUEST_MEMORY=2G
SSH_REMOTE_PORT=10000

# Run in background, and display a window. In order to shut down, either use the window, or SSH (it
# seems that this guest doesn't respond to the ACPI shutdown signal).
#
# The credentials (login/pwd) are: riscv/fedora_rocks!
#
qemu-system-riscv64 \
   -machine virt \
   -smp "$GUEST_PROCESSORS" \
   -m "$GUEST_MEMORY" \
   -kernel Fedora-Minimal-Rawhide-20200108.n.0-fw_payload-uboot-qemu-virt-smode.elf \
   -bios none \
   -object rng-random,filename=/dev/urandom,id=rng0 \
   -device virtio-rng-device,rng=rng0 \
   -device virtio-blk-device,drive=hd0 \
   -drive file=Fedora-Minimal-Rawhide-20200108.n.0-sda.diff.qcow2,format=qcow2,id=hd0 \
   -device virtio-net-device,netdev=usernet \
   -netdev user,id=usernet,hostfwd=tcp::"$SSH_REMOTE_PORT"-:22 \
   -daemonize

# Copy and compress the compressor 🙂, then decompress it.
#
# This commands can be comfortably performed via scp + ssh and so on; this is a single command for performing
# a quick smoke test.
#
# Those who wanted to perform similar operations in an entirely scripted fashion, can use the `sshpass`
# tool.
#
cat "$WORKSPACE_PATH/pigz/pigz" | ssh -p "$SSH_REMOTE_PORT" riscv@localhost "
  cat > pigz       &&
  chmod +x pigz    &&
  ./pigz -v pigz   &&
  gzip -dv pigz.gz
"
```

For general reference, guests that support the ACPI shutdown signal (not this case), can be shut down using the QEMU monitor:

```sh
QEMU_MONITOR_FILE=$(mktemp)

# Start QEMU with this option:
#
qemu-system-x86_64 -monitor unix:"$QEMU_MONITOR_FILE",server,nowait # ...

# Shut down via socket:
#
echo system_powerdown | socat - UNIX-CONNECT:"$QEMU_MONITOR_FILE"
```

## Conclusion

While an open [ISA](https://en.wikipedia.org/wiki/Instruction_set_architecture) doesn't equate with "competitive chips tomorrow" (which require expensive investments, not a goal of the RISC-V association[¹](#footnote01)), nonetheless, an open ISA is the necessary starting point, and it's exciting to be able to witness (and experiment with) a technology in the pioneering stage.

This article has given the tools and very practical instructions to start experimenting with RISC-V.

Happy emulation!

## Footnotes

<a name="footnote01">¹</a>: From https://riscv.org/about/history: "RISC-V International does not manage or make available any open-source RISC-V implementations, only the standard specifications"
