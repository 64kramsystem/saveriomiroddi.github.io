---
layout: post
title: Handling the apt lock on Ubuntu Server installations (the infamous &quot;Could not get lock /var/lib/apt/lists/lock&quot;)
tags: [concurrency,linux,sysadmin,ubuntu]
---

When managing Ubuntu Server installations, for example image templates in the cloud, one of the main issues one comes across is apt locking, which causes the the annoying error `Could not get lock /var/lib/apt/lists/lock`, typically "at the worst times".

This seems to be a matter of discussion on the Stack Overflow network, but there are no working and stable solutions.

In order to get an idea of the confusion about the subject, check out the number and scope of solutions in [this Stack Overflow question](https://askubuntu.com/questions/132059/how-to-make-a-package-manager-wait-if-another-instance-of-apt-is-running).

In this post I'll talk about a few approaches, and the stable solution I've implemented.

Readers interested in just solving the problem can skip to [The Final Solution™](#the-final-solution) section.

Contents:

- [The general setup](/Handling-the-apt-lock-on-ubuntu-server-installations#the-general-setup)
- [Assumptions](/Handling-the-apt-lock-on-ubuntu-server-installations#assumptions)
- [The problem](/Handling-the-apt-lock-on-ubuntu-server-installations#the-problem)
- [Potential solutions](/Handling-the-apt-lock-on-ubuntu-server-installations#potential-solutions)
  - [Retrying in case of errors](/Handling-the-apt-lock-on-ubuntu-server-installations#retrying-in-case-of-errors)
  - [Inspecting the running processes](/Handling-the-apt-lock-on-ubuntu-server-installations#inspecting-the-running-processes)
  - [Disabling the services](/Handling-the-apt-lock-on-ubuntu-server-installations#disabling-the-services)
  - [Waiting on `cloud-init` to complete](/Handling-the-apt-lock-on-ubuntu-server-installations#waiting-on-cloud-init-to-complete)
  - [Using flock](/Handling-the-apt-lock-on-ubuntu-server-installations#using-flock)
  - [Using fnctl](/Handling-the-apt-lock-on-ubuntu-server-installations#using-fnctl)
  - [The "screw it" solution: replace `/usr/lib/apt/apt.systemd.daily`](/Handling-the-apt-lock-on-ubuntu-server-installations#the-screw-it-solution-replace-usrlibaptaptsystemddaily)
- [The Final solution™](/Handling-the-apt-lock-on-ubuntu-server-installations#the-final-solution)
- [Conclusion](/Handling-the-apt-lock-on-ubuntu-server-installations#conclusion)

## The general setup

Teams working with cloud services typically have a process, either manual or automated, for building virtual machine images.

In our case, we:

1. use Packer, which, when invoked, based on the configuration provided in a template...
1. instantiates an EC2 virtual machine, using a stock Ubuntu AMI (image),
1. configures the machine, using Chef, and
1. stores the result into a new AMI (image).

This is fairly standard procedure.

The crucial point is that, during the machine configuration stage, independently of how it's performed, it's desirable to update the machine (packages).

## Assumptions

For style purposes, I'll use the inappropriate phrase "update apt", intended as "update the apt indexes".

## The problem

Stock Ubuntu server distributions perform packages update very aggressively.

In particular, as soon as a machine is booted for the first time, an update is performed. Updates are also performed as soon as the machines boots, if it hasn't been launched for a long time (based on these cases, it's clear why I've previously wrote that the error typically happens "at the worst times").

Package updates can't be run in parallel, as they could interfere with each other.

Unfortunately, the Ubuntu (Debian) package manager, apt, doesn't support waiting on other processes to terminate updates; the result is that two concurrent apt invocations will cause:

```sh
$ apt update
E: Could not get lock /var/lib/apt/lists/lock - open (11: Resource temporarily unavailable)
E: Unable to lock directory /var/lib/apt/lists/
```

There are a couple of (cheap) solutions to this, for example, retrying in case of \[specific\] errors, or inspecting the running processes to ensure apt is not running.

Another solution is to simply isolate the processes invoking an update and stopping or disabling them.

I'll go through each solution, and explain why it it's not good enough or doesn't not work, and the process that lead to The Final Solution™.

## Potential solutions

### Retrying in case of errors

The idea behind this solution, is simply to check, in some way, the outcome of the `apt`, and retry until it succeeds.

There are two approaches to accomplish this task: inspecting the text output, and inspecting the exit status. However:

- parsing text to gather the state of a program is generally brittle, as it's subject to changes like corrections, translations and so on;
- the exit status may be confusing, generic and so on.

Additionally, abstractly, retrying is a form of polling, which is inferior to finding out the exact event and waiting on it.

In the case of parsing, for fun, one can use some shell trickery:

```sh
# `2>`  redirects stderr, where the error is printed
# `>()` called "process substitution", executes the enclosed commands, passing the input (in this
#       case, from stderr) to them, and (in this form) also printing the output
#
# We use process substitution because the syntax `apt update 2> grep ...` is interpreted as "send the
# stderr output to the file `grep`, which is not what we want.
#
apt update 2> >(grep "Could not get lock /var/lib/apt/lists/lock" > /tmp/apt-lock-err.log)
```

then inspect if the file `/tmp/apt-lock-err.log` is empty or not (note that we're discarding non-matching stderr lines, but this solution is not good anyway).

Regarding the exit status, we can't rely on it with apt (apt-get), for several reasons:

- exit statuses are not documented [in the man pages];
- a failed update due to locking yields an exit status of `100`, but we don't know if this exit status is associated with other failures;
- the exit status is success (`0`), even if the indexes download fails (!).

### Inspecting the running processes

One can inspect the running processes and check if apt is running.

Rather than parsing the output of `ps`, one would use `pgrep`:

```sh
# Silence stdout, otherwise it will print the PID when matching.
#
while pgrep apt > /dev/null; do
  sleep 1
done

do_update_packages
```

There are a couple of reasons why this is not a reliable solution.

First, it's not clear which process to check (`apt`? `apt-get`? `dpkg`?).

Second, what if the pattern unexpected matches another program?

Finally, this approach is subject to race conditions: apt may kick in between the exit from the `while` loop and the `do_update_packages` command.

### Disabling the services

One may take a different approach, and just stop/disable the services that invoke apt. The idea is intuitive and (supposedly) straightforward, and it has been our first attempt.

In modern Ubuntu/Debian, Systemd is used. Routine jobs are handled via "timers", which, at prefixed times, invoke the so-called "units" (which, in this context, never run autonomously).

Let's have a look at the timers:

```sh
# Output edited
$ systemctl list-timers
NEXT                         LEFT        LAST                         PASSED        UNIT                         ACTIVATES
Tue 2020-02-18 22:12:12 GMT  8h left     Tue 2020-02-18 07:23:16 GMT  5h 55min ago  apt-daily.timer              apt-daily.service
Wed 2020-02-19 07:45:17 GMT  18h left    Tue 2020-02-18 07:45:17 GMT  5h 33min ago  systemd-tmpfiles-clean.timer systemd-tmpfiles-clean.service
Mon 2020-02-24 00:00:00 GMT  5 days left Mon 2020-02-17 00:00:12 GMT  1 day 13h ago fstrim.timer                 fstrim.service
Mon 2020-02-24 07:00:00 GMT  5 days left Mon 2020-02-17 07:00:06 GMT  1 day 6h ago  apt-daily-upgrade.timer      apt-daily-upgrade.service
```

and the units:

```sh
# Output edited
$ systemctl list-unit-files apt-daily*.service
UNIT FILE                 STATE 
apt-daily-upgrade.service static
apt-daily.service         static
```

Now, what we could do is:

```sh
$ systemctl disable apt-daily.timer apt-daily-upgrade.timer
$ systemctl stop apt-daily.timer apt-daily-upgrade.timer
$ do_update_packages
```

With `disable`, we prevent the timers to start on the following boot. When to restart and reenable them, depends on the adopted lifecycle of the virtual machines.

This is not a reliable solution, as it's susceptible to race conditions: by the time the `stop` command is invoked, the timer/unit may have already started.

Now, let's assume that won't happen (but it does 😬). Does this solution work?

No! 🤦‍

It turns out that also cron performs apt update jobs (!), so we need to disable it as well:

```sh
$ systemctl disable cron
$ systemctl stop cron
```

Did we finally solve the issue?

NO! 🤯

Even after three services disabled (and a reboot, which makes sure none of the services are running), updates still happen.

Let's try to find out the process invoking the update via `ps`, when the error happens:

```sh
# Output edited
$ ps aux --forest
root      0000  0.0  0.0   0000   000 ?        Ss   00:00   0:00 /bin/sh /usr/lib/apt/apt.systemd.daily install
root      0000  0.0  0.0   0000  0000 ?        S    00:00   0:00  \_ /bin/sh /usr/lib/apt/apt.systemd.daily lock_is_held install
root      0000  0.0 00.0 000000 000000 ?       Sl   00:00   0:00      \_ /usr/bin/python3 /usr/bin/unattended-upgrade
```

This doesn't help, as we don't see the parent process; it could be due to a variety of reasons, for example, the parent process disowning the child.

Even in a better situation (e.g. if the process descended from a Systemd one), it may not be necessarily informative enough.

After such amount of work, it's better to abandon this road and try another. Even if it worked, if something changed, this approach is too time-consuming and obscure.

(For reference, after further investigations along other ways, it seems that `cloud-init` is involved)

### Waiting on `cloud-init` to complete

A colleague of mine attempted an interesting solution - waiting for `cloud-init` to complete ([from Unix Stack Exchange](# https://unix.stackexchange.com/questions/463498/terminate-and-disable-remove-unattended-upgrade-before-command-returns/463503#463503)):

```sh
systemd-run --property="After=cloud-init.service apt-daily.service apt-daily-upgrade.service" --wait /bin/true

do_update_packages
```

This approach worked... until it didn't 😬.

It worked when run early enough, but when not, it would cause the command to wait for around 20 minutes.

I suspect that the long wait is caused by waiting on the next occurrence of `cloud-init` to run after it run already.

Ultimately, the very fact of questioning the mechanics behind it, has been a reason to discard this approach as well.

### Using flock

Some attempted solutions on the net suggest using `flock`:

```sh
$ man flock | head -n 4
FLOCK(1)                         User Commands                        FLOCK(1)

NAME
       flock - manage locks from shell scripts
```

Unfortunately, this doesn't work. Run the following in a terminal:

```sh
$ sudo flock /var/lib/apt/lists/lock sleep 10
```

then update apt in another terminal:

```sh
$ sudo apt update
Hit:1 http://security.ubuntu.com/ubuntu bionic-security InRelease
Hit:2 http://archive.canonical.com/ubuntu bionic InRelease
# [...]
```

Ouch. What?

### Using fnctl

Ok, it's time to dive in the `apt` source code, and see what happens.

Let's clone the repository:

```sh
$ git clone https://salsa.debian.org/apt-team/apt.git
```

Since we don't know anything about the structure of the source code, let's start searching the error message:

```
$ ag "Could not get lock" apt
apt/apt-pkg/contrib/fileutl.cc
309:	       _error->Errno("open", _("Could not get lock %s. It is held by process %d"), File.c_str(), fl.l_pid);
311:	       _error->Errno("open", _("Could not get lock %s. It is held by process %d (%s)"), File.c_str(), fl.l_pid, name.c_str());
314:	    _error->Errno("open", _("Could not get lock %s"), File.c_str());

apt/po/ast.po
685:#| msgid "Could not get lock %s"
686:msgid "Could not get lock %s. It is held by process %d"
691:msgid "Could not get lock %s. It is held by process %d (%s)"
696:msgid "Could not get lock %s"
949:#| msgid "Could not get lock %s"
# [...]
```

We're lucky! The first file found seems the right one (or we're close, anyway). Let's see:

```cpp
int GetLock(string File,bool Errors)
{
   // GetLock() is used in aptitude on directories with public-write access
   // Use O_NOFOLLOW here to prevent symlink traversal attacks
   int FD = open(File.c_str(),O_RDWR | O_CREAT | O_NOFOLLOW,0640);
   if (FD < 0)
   {
      // Read only .. can't have locking problems there.
      if (errno == EROFS)
      {
	 _error->Warning(_("Not using locking for read only lock file %s"),File.c_str());
	 return dup(0);       // Need something for the caller to close
      }
      
      if (Errors == true)
	 _error->Errno("open",_("Could not open lock file %s"),File.c_str());

      // Feh.. We do this to distinguish the lock vs open case..
      errno = EPERM;
      return -1;
   }
   SetCloseExec(FD,true);
      
   // Acquire a write lock
   struct flock fl;
   fl.l_type = F_WRLCK;
   fl.l_whence = SEEK_SET;
   fl.l_start = 0;
   fl.l_len = 0;
   if (fcntl(FD,F_SETLK,&fl) == -1)
   {
      // always close to not leak resources
      int Tmp = errno;
// [...]
```

So, it turns out that the locks manipulated by `flock` are not the only form of locking in Unix. This is a different beast, and it's comes from a Linux API called `fnctl`.

Let's have a look at the [man page](http://man7.org/linux/man-pages/man2/fcntl.2.html), also considering the flag passed `F_SETLK`:

```
FCNTL(2)                  Linux Programmer's Manual                 FCNTL(2)
NAME         top
       fcntl - manipulate file descriptor

[...]

   Advisory record locking
       Linux implements traditional ("process-associated") UNIX record
       locks, as standardized by POSIX.  For a Linux-specific alternative
       with better semantics, see the discussion of open file description
       locks below.

       F_SETLK, F_SETLKW, and F_GETLK are used to acquire, release, and test
       for the existence of record locks (also known as byte-range, file-
       segment, or file-region locks).  The third argument, lock, is a
       pointer to a structure that has at least the following fields (in
       unspecified order).

           struct flock {
               ...
               short l_type;    /* Type of lock: F_RDLCK,
                                   F_WRLCK, F_UNLCK */
               short l_whence;  /* How to interpret l_start:
                                   SEEK_SET, SEEK_CUR, SEEK_END */
               off_t l_start;   /* Starting offset for lock */
               off_t l_len;     /* Number of bytes to lock */
               pid_t l_pid;     /* PID of process blocking our lock
                                   (set by F_GETLK and F_OFD_GETLK) */
               ...
           };

[...]
```

So we have it. Unfortunately, it turns out that there is not standard tool that allows manipulation of such locks.

Let's write a minimal C program, which emulates the apt locking, and invokes an `apt update`:

```cpp
// Extremely minimal version. Relies on automatic closure of lock/file descriptor on exit.
//
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>

int main (int argc, char* argv[])
{
  int fd = open("/var/lib/apt/lists/lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0640);

  if (fd == -1) {
    printf("Error opening the file\n");
    return 1;
  }

  struct flock lock;
  lock.l_type = F_WRLCK;
  lock.l_whence = SEEK_SET;
  lock.l_start = 0;
  lock.l_len = 0;

  if (fcntl(fd, F_SETLKW, &lock) == -1) {
    printf("Error locking the file\n");
    return 1;
  }

  // Ignore the status.
  system("apt update");

  return 0;
}
```

Since the lock is released once the program is closed, I run `apt update` from the it. Let's test it!:

```
$ clang test_apt_locking.c -o test_apt_locking
$ sudo ./test_apt_locking
Reading package lists... Done
E: Could not get lock /var/lib/apt/lists/lock - open (11: Resource temporarily unavailable)
E: Unable to lock directory /var/lib/apt/lists/
```

Ouch! What happens? [This](http://man7.org/linux/man-pages/man2/fcntl.2.html) happens:

> [...] Locks are not inherited by a child process.

So, the apt process can't lock the file, because it's locked by parent process, even if it's its child.

Therefore, this is another failed attempt.

### The "screw it" solution: replace `/usr/lib/apt/apt.systemd.daily`

At this point, enough time has been spent to warrant a dirty-but-working solution.

From the looks of the `ps aux` invocation, the program used to update apt is `/usr/lib/apt/apt.systemd.daily`.

It's a shell script!:

```sh
$ head -n 10 /usr/lib/apt/apt.systemd.daily
#!/bin/sh
#set -e
#
# This file understands the following apt configuration variables:
# Values here are the default.
# Create /etc/apt/apt.conf.d/10periodic file to set your preference.
#
#  Dir "/";
#  - RootDir for all configuration files
#
```

Now, the idea is to replace it as soon as the machine starts, perform the updates etc., then restore it.

Since packages are upgraded in the process, let's first check if doing so will override the file:

```sh
$ dpkg -S /usr/lib/apt/apt.systemd.daily
apt: /usr/lib/apt/apt.systemd.daily
```

The script belongs to the `apt` package. The packages upgraded during the first upgrade procedure are:

```sh
$ apt list --upgradable
Listing...
apport/bionic-updates 2.20.9-0ubuntu7.11 all [upgradable from: 2.20.9-0ubuntu7.9]
base-files/bionic-updates 10.1ubuntu2.8 amd64 [upgradable from: 10.1ubuntu2.7]
bsdutils/bionic-updates 1:2.31.1-0.4ubuntu3.5 amd64 [upgradable from: 1:2.31.1-0.4ubuntu3.4]
cloud-init/bionic-updates 19.4-33-gbb4131a2-0ubuntu1~18.04.1 all [upgradable from: 19.3-41-gc4735dd3-0ubuntu1~18.04.1]
dmidecode/bionic-updates 3.1-1ubuntu0.1 amd64 [upgradable from: 3.1-1]
# [...]
```

apt is not among them, so this solution can be at least be tried in the short term (I guess in the long term, the Debian alternatives may help preserving the replaced version, during the upgrade).

Let's hack the program with a straight exit and proceed:

```sh
$ sudo perl -MEnglish -i.bak -ne 'print "#!/bin/sh\nexit 0" if $NR == 1' /usr/lib/apt/apt.systemd.daily
$ apt update
$ apt dist-upgrade -y
Reading package lists...
Building dependency tree...
Reading state information...
Calculating upgrade...
The following NEW packages will be installed:
  linux-aws-headers-4.15.0-1060 linux-headers-4.15.0-1060-aws
# [...]
$ apt update
E: Could not get lock /var/lib/apt/lists/lock - open (11: Resource temporarily unavailable)
E: Unable to lock directory /var/lib/apt/lists/
```

This officially certifies that apt is cursed.

Some `cat`ing reveals that the `dist-upgrade` updates the script, overwriting the hack. It's not clear which package updates the file, but as a matter of fact it happens, excluding also this approach from the candidates.

## The Final solution™

While punching the screen, I noticed, for a fraction of a second, that the `cat` output had something interesting: the "lock" word.

So I opened the file and had a look at it:

```sh
    # Maintain a lock on fd 3, so we can't run the script twice at the same
    # time.
    eval $(apt-config shell StateDir Dir::State/d)
    exec 3>${StateDir}/daily_lock
    if ! flock -w 3600 3; then
        echo "E: Could not acquire lock" >&2
        exit 1
    fi
```

Bingo! I coudn't believe it.

It turns out that `apt-daily` has a lock of its own, and it's obtained via `flock`. This means that we can finally perform exactly the locking required:

```sh
# Check the filename.
$ apt-config shell StateDir Dir::State/d
StateDir='/var/lib/apt/'

# Now that we know the format, we can either hardcode the value, or gather it dynamically, which is
# more complex.
# Of course we do the latter, with Perl 😬. We assume that the trailing slash is there; if something
# changes in the future, flock will fail.
#
# Regex explanation:
#
# - "capture"               -> `(` and `)` (round brackets)
# - "anything"              -> `.*`
# - "followed by a slash`   -> `/`
# - "between single quotes" -> `'`
#
# Anything outside the capturing group is not included (and printed). The slash needs to be escaped,
# since it's the Perl character for regex delimiter.
#
$ flock "$(apt-config shell StateDir Dir::State/d | perl -ne "print /'(.*)\/'/")"/daily_lock apt update
Hit:1 http://apt.llvm.org/bionic llvm-toolchain-bionic-9 InReleas
Hit:2 http://download.virtualbox.org/virtualbox/debian bionic InRelease
Hit:3 http://archive.canonical.com/ubuntu bionic InRelease
```

Apt runs smoothly. End of the story.

## Conclusion

I'm not sure what's the lesson here.

System services are quite tricky, and there is seemingly no obvious way of pinpointing what exactly does what. I was, so to speak, lucky to keep the eyes open (and to keep typing) while "punching the screen".

Definitely, inspecting sources has been crucial in solving the problem, so I'll close this post with "Hacker culture all the way down!".
