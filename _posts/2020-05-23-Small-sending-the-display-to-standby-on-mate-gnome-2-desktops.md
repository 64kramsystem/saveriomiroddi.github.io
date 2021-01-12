---
layout: post
title: Small&#58; Sending the display to standby on MATE (GNOME 2) desktops
tags: [linux,shell_scripting,small,sysadmin,ubuntu]
redirect_from:
- Small_sending_the_display_to_standby_on_mate_gnome_2_desktops
---

Sometimes, I want to send my display to standby, rather than the entire system. Long ago, the `xset` tool alone would do the trick, but nowadays, it doesn't.

This short article describes how to accomplish this task.

Content:
- [Sending the screen to standby via commandline, and the problems](/Small-sending-the-display-to-standby-on-mate-gnome-2-desktops#sending-the-screen-to-standby-via-commandline-and-the-problems)
- [The solution](/Small-sending-the-display-to-standby-on-mate-gnome-2-desktops#the-solution)

## Sending the screen to standby via commandline, and the problems

In general, on Linux desktops, the display can be sent to standby via the command:

```sh
xset dpms force off
```

It's generally best to put this into a script, and precede it with a small `sleep` (even 0.5 seconds will do), otherwise, the keystroke may be interpreted by the system as an exit from the standby.

However, in the last years, on my MATE desktop, the the display would instead come out of standby after a few seconds. It turns out, this is caused by the screensaver owning the display.

The screensaver functionality can't be entirely disabled via desktop preferences, so a startup application (script) needs to be used.

However, there are many issues:

1. the related process (`mate-screensaver`) can't be killed, because it also handles the screen locking;
2. exiting the screensaver (`mate-screensaver-command --exit`) is not effective, since the screensaver is automatically restarted, at least once;
3. the screensaver also starts asynchronously, so one needs to wait for the screensaver to be executed;
4. the screensaver process can take a bit of time to be active after execution,
5. and many small issues.

## The solution

The solution, in general terms, is to inhibit the screensaver:

```sh
mate-screensaver-command -i
```

however, the asynchronousness of the startup applications needs to be managed.

In order to avoid hairpulling for several reasons (including 3. and 4.), we'll use a blunt approach:

```sh
cat > ~/.config/autostart/inhibit_screensaver.desktop << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=Inhibit screensaver
Exec=sh -c 'while true; do mate-screensaver-command -i 2> /dev/null; sleep 1; done'
X-GNOME-Autostart-enabled=true
Comment=Without this, the screen turns on a few seconds after invoking  `xset dpms force off`
DESKTOP
```

This creates a startup application (whose location is `$HOME/.config/autostart`), that invokes a small shell script.

The command `mate-screensaver-command -i` will fail until the screensaver process is executed _and_ active. Then, it will perform its duty (inhibiting the screensaver), and the command will block.

I don't like blunt solutions, but handling asynchronousness, internal events, automatic restarts and so on, made a precise solution an uninteresting and futile time expenditure.
