---
layout: post
title: Shell scripting adventures (Introduction)
tags: [shell_scripting,sysadmin]
last_modified_at: 2018-03-09 18:15:00
---

I've always thought of shell scripting as a second class scripting form, being awkward and limited.
After a deep dive in my [RPi VPN router project](https://github.com/saveriomiroddi/rpi_vpn_router), I still think it's awkward and limited, but I do appreciate it as first class choice under specific conditions.

Shell scripting generally can't be disassociated from system/infrastructure administration, so developing the project has been actually, as a whole, a very interesting and pleasant undertaking.

This post lays the structure of the future posts I'll publish about the experience.

Following chapters:

- [Part 1]({% post_url 2017-11-08-Shell-scripting-adventures-part-1 %})
- [Part 2]({% post_url 2017-11-22-Shell-scripting-adventures-part-2 %})
- [Part 3]({% post_url 2017-12-23-Shell-scripting-adventures-part-3 %})

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

- 1) Bash general functionalities
  - Associative arrays (hash maps)
  - Escape strings
  - Expand strings into separate options
  - Regular expressions matching
  - Find a filename's basename
  - Replace the extension of a filename
  - Cycle a multi-line variable
  - Heredoc
- 2) Text processing extravaganza
  - Awk/sed/perl considerations
  - Perl text processing
  - Awk text processing
  - Progress bars processing with awk (and stdbuf)
- 3) Terminal-based dialog boxes: Whiptail
  - Widgets, with snippets
    - Message box
    - Yes/no box
    - Gauge
    - Radio list
  - Other widgets

An extra article won't be published; it originally was planned to include:

- 4) Linux tools/system concepts
  - handling xz archives
  - handling usb storage devices/udev
  - signals trapping
  - resizing a disk, via parted, in a non-interactive way
