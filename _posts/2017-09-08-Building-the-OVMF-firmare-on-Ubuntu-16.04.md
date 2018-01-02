---
layout: post
title: Building the OVMF firmware on Ubuntu 16.04
tags: [vfio, virtualization, ubuntu, linux, trivia]
---

In my [VGA Passthrough guide][VGA Passthrough guide], I explain how to configure an Ubuntu machine for VFIO.

With the release of QEMU 2.10, some bugs in the OVMF firmware surfaced, which make Windows guests unstable; such bugs have been fixed in the master branch of the [EDK II Project repository][EDK II Project repository], so, in order to use QEMU 2.10, it's required to build the firmware from scratch.

## Execution

Prepare the machine:

```sh
sudo apt-get install build-essential uuid-dev iasl git gcc-5 nasm
```

Clone the repository and change path:

```sh
git clone https://github.com/tianocore/edk2.git
cd edk2
```

Compile and build the tools:

```sh
make -C BaseTools
export EDK_TOOLS_PATH=$(pwd)/BaseTools
. edksetup.sh BaseTools
```

Configure the build, in this case for an X64 target:

```sh
export COMPILATION_MAX_THREADS=$((1 + $(lscpu --all -p=CPU | grep -v ^# | sort | uniq | wc -l)))

perl -i -pe 's/^(ACTIVE_PLATFORM).*              /$1 = OvmfPkg\/OvmfPkgX64.dsc/x'  Conf/target.txt
perl -i -pe 's/^(TOOL_CHAIN_TAG).*               /$1 = GCC5/x'                     Conf/target.txt
perl -i -pe 's/^(TARGET_ARCH).*                  /$1 = X64/x'                      Conf/target.txt
perl -i -pe "s/^(MAX_CONCURRENT_THREAD_NUMBER).*/\$1 = $COMPILATION_MAX_THREADS/x" Conf/target.txt
```

Build:

```sh
build
```

Enjoy!:

```sh
$ ls -1 Build/OvmfX64/DEBUG_GCC5/FV/OVMF_*.fd
Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd
Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd
```

[VGA Passthrough guide]: https://github.com/saveriomiroddi/vga-passthrough
[EDK II Project repository]: https://github.com/tianocore/edk2
