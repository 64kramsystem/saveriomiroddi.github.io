---
layout: post
title: Announcement&#58; New ZFS installer release
tags: [announcement,filesystems,linux,storage,sysadmin,ubuntu]
---

The 0.5 series of the [ZFS installer](https://github.com/saveriomiroddi/zfs-installer) has been released.

The new version integrates parts of the [updated official procedure](https://openzfs.github.io/openzfs-docs/Getting%20Started/Ubuntu/Ubuntu%2020.04%20Root%20on%20ZFS.html) for installing ZFS on Ubuntu-based distributions.

The main changes are:

- ability to specify the root pool datasets, for users who want a granular subdivision of the filesystem;
- KUbuntu support;
- removal (at least temporary) of Debian support, as it diverges more than expected from the base procedure.

Users can follow the instructions [on the home page](https://github.com/saveriomiroddi/zfs-installer), which is simply:

```sh
GET https://git.io/JelI5 | sudo bash
```
