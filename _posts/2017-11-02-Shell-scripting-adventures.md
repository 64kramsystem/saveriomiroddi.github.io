---
layout: post
title: Shell scripting adventures
tags: [shell_scripting,sysadmin]
last_modified_at: 2017-11-02 23:19:49
---

I've always thought of shell scripting as a second class scripting form, being awkward and limited.
After a deep dive in my [RPi VPN router project](https://github.com/saveriomiroddi/rpi_vpn_router), I still think it's awkward and limited, but I do appreciate it as first class choice under specific conditions.

Shell scripting generally can't be disassociated from system/infrastructure administration, so developing the project has been actually, as a whole, a very interesting and pleasant undertaking.

This post lays the structure of the future posts I'll publish about the experience.

## The domain

When I write about specific conditions, I refer mostly to a couple of things:

1. use of Bash: certain features of Bash are very handy; using Dash (which may be forced in far cases of compatibility requirements) definitely would make several functionalities cumbersome;
2. small/medium sized, linear scripts: Bash scripting is not appropriate for non-linear flows, and it doesn't have the tooling of bigger programming languages.

Within this context, viewing shell scripting as the glue for systems management, becomes a very natural option.

Having said that, Bash is awkward by nature, as it's full of small details that must be kept in mind, and has some very obscure syntaxes.

## Structure

The objective of the project is to create an installer that interacts with the user for choosing the router configuration, downloads the required image and code, optionally modifies the image, then writes it on an SD card, then configures it.

As in the Unix tradition, there are tools for doing everything needed, including simple GUIs.  
There is only one thing missing from a standard/common distribution, and it's binary diffing/patching - this forced me to change strategy for the post-configuration stage.

The installer is a [single script](https://github.com/saveriomiroddi/rpi_vpn_router/blob/master/install_vpn_router.sh).  
Although the description may be easy, many areas are covered, and especially, gathering and applying best practices is very time consuming.

Indicatively, the structure of the blog posts, and their content, will be:

1. bash
  - associative arrays
  - expand strings into separate options
  - escape strings
  - regexes
  - find file basename
  - replace extension
  - cycle a multi-line input
  - heredoc
2. linux tools/system concepts
  - check sudo
  - awk/sed/perl
  - stdbuf
  - process wget/dd progress (pipes shuffling)
  - xz
  - usb storage devices/udev
  - trap
  - disk resize
3. using whiptail
  - base widgets
  - radio list
  - gauge/text processing/pipes
4. pathing the binaries in a filesystem, and large file storage: considerations
  - git lfs
  - google drive
  - binary patching
  - dpkg --root
  - rsync
