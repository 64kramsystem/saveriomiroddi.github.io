---
layout: post
title: Announcement&#58; Ticketsolve's Ruby PPA is available
tags: [announcement,distribution,linux,packaging,ruby,sysadmin,ubuntu]
---

As a companion of the [PPA learning article]({% post_url 2020-05-26-Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA %}), we ([Ticketsolve](https://www.ticketsolve.com/)) are publishing a PPA with the stable, vanilla Ruby versions, which we'll keep up to date for the foreseeable future.

Content:

- [Disclaimer](/Announcement-Ticketsolve-s-Ruby-PPA-is-available#disclaimer)
- [Installation](/Announcement-Ticketsolve-s-Ruby-PPA-is-available#installation)
- [How about Fullstaq Ruby?](/Announcement-Ticketsolve-s-Ruby-PPA-is-available#how-about-fullstaq-ruby)

## Disclaimer

The PPA provides packages that have the simplest possible structure for a Ruby distribution; in other words, they're the virtual equivalent of running Ruby's standard `make install`, with the added benefits of the Debian packaging (explicit dependencies and possible automatic updates).

Like Ruby's standard `make install` installation, this configuration doesn't prevent users from shooting themselves in the foot by installing conflicting packages (ie. Ruby or Ruby-related).

This is not a problem (for example, Fullstaq Ruby does essentially the same, just with a different installation prefix), as long as the users are aware of the choice.

## Installation

From the terminal:

```sh
sudo add-apt-repository -y ppa:ticketsolve/ruby-builds
sudo apt update
sudo apt install ruby2.6
```

All the stable versions are provided, and updated shortly after they're officially released.

As of May/2020, the packages/versions provided are:

- `ruby2.5`
- `ruby2.6`
- `ruby2.7`

## How about Fullstaq Ruby?

Before creating our own PPA, we've evaluated Fullstaq Ruby on our servers, which relies on Rbenv (as it's not installed in a directory included in the default `$PATH`).

Ruby version managers work by manipulating the PATH in one way or another (Rbenv and RVM, for example, use different strategies). This can't be entirely transparent to the user, so it introduces overhead; for example, cron jobs need to be version manager-aware.

For this reason, in a single-version use case like ours, a system-wide Ruby installation is simpler to manage. Since our granularity is at container level, if we need to, say, test another Ruby, we just spin a separate EC2 instance.

But of course, there's a variety of use cases; additionally, Fullstaq Ruby has some optimizations (in our system, it didn't provide any measurable improvement, but your mileage may vary!).
