---
layout: post
title: Considerations (review) of Raspberry Pi/Odroid XU4 usage as home server
tags: [hardware]
---

With the large diffusion of SBCs [Single Board Computers], and subsequent maturation of their ecosystem, it's now relatively easy to setup a home server.

I've had three SBCs until now; a Raspberry Pi 2 model B, a 3 model B, and recently, an Odroid XU4.

In this post, I'm going to share some considerations about their usage as home servers.

Contents:

- [General characteristics of an SBC/home server](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#general-characteristics-of-an-sbchome-server)
- [Brief informations about ARM processors](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#brief-informations-about-arm-processors)
- [Raspberry Pi 3 Model B](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#raspberry-pi-3-model-b)
  - [Specifications](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#specifications)
  - [Support and documentation](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#support-and-documentation)
    - [BEWARE: Stay far from the Ubuntu Pi Flavour Maker](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#beware-stay-far-from-the-ubuntu-pi-flavour-maker)
  - [Usage impressions](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#usage-impressions)
- [Odroid XU4](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#odroid-xu4)
  - [Specifications](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#specifications)
  - [Support and documentation](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#support-and-documentation)
  - [Usage impressions](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#usage-impressions)
    - [Power draw](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#power-draw)
    - [The infamous fan](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#the-infamous-fan)
- [Conclusions](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#conclusions)
- [Footnotes](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#footnotes)

## General characteristics of an SBC/home server

The root question when considering SBC is: what is a home server?

Although there is no strict definition, a home server, typically:

- provides services within a private network
- the services are not computationally intensive
- it is based on an easily maintainable operating system
- it is realiable as much as desktop machine - in other words, it should operate for potentially extended amount of times, but without requiring any form of redundancy (processors, RAM, disks...)

All the SBC mentioned are able to satisfy the above requirements.

Originally, the Raspberry Pi was groundbreaking because it made hobbyist electronics easy, due to the very low barrier of entry (both in price and in tooling).  
Although this is not strictly related to home server projects, it's important as context under which evaluate the boards.

In the following sections I will not discuss the RPi 2B - only the 3B and the XU4, as, for the purpose of home server, the latter RPi supersedes the former.

## Brief informations about ARM processors

The ARM processors for SBC are generally classified in two series (latest to oldest generation):

- High-power: A72 > A57 > A15
- Low-power: A53 > A7

SBCs can also use a combination of both architecture, in order to suit the demand of the current load, swapping cores dynamically.

## Raspberry Pi 3 Model B

### Specifications

The RPi 3B is a 4-core 1.4 GHz A53 machine, with 1 GiB of RAM; it uses micro SD for storage.

It's not very easy to assess the price; a standard configuration comprises:

- board: 40€
- sd card, 16 GB: 13€
- power supply + cable: 15€

For a very approximate amount of 65/70€.

It's possible to save 10 or more Euros by buying an incendiary power supply from Amazon or any Chinese direct seller.

### Support and documentation

Raspberry Pis are widely and very well supported/documented; they're essentially the state of the art in this aspect.

The Raspbian is essentially a standard Debian distribution.

#### BEWARE: Stay far from the Ubuntu Pi Flavour Maker

I'm dedicating an entire section because this is an exceptional case of engineering irresponsibility.

Do **not** use the Ubuntu Pi Flavour Maker for the Raspberry Pi 3; it's broken.

There is [a critical bug](https://bugs.launchpad.net/ubuntu/+source/linux-raspi2/+bug/1652270) that causes the O/S to brick on the first reboot, if the system is updated. Since updates are automatic, first-time users of this distribution will have a nasty surprise on first reboot, without any obvious sign.

I consider this an exceptional case of irresponsibility because the maintainer(s) are refusing to put any warning (check out [the website](https://ubuntu-pi-flavour-maker.org)), or pull out this distribution entirely, even if this source is one of the top results in the search engines, and the bug is official.

Instead, RPi 3 users should use [Raspbian](https://www.raspbian.org/), which works as intended.

### Usage impressions

The RPi 3B works OK as home server. The major problem is that it's very slow, due to both the processor and the storage; while the available RAM, 1 GiB, is not a lot, it is not a bottleneck for the typical home server services.

Having both slow processor and storage is a deadly combination, as many tasks will be affected either by one or another.

Even basic tasks like updating the packages can take long times (dozens of minutes); let alone intensive tasks like compiling a program.

For reference, the RPi 3B bottlenecks the download bandwidth of a VPN connection to 20 MBit/s [¹](#footnote01).

The upside is the power draw, which is low to the point that when used without peripherals in a headless configuration, it can fed entirely from the USB port of a desktop device (I use it connected to the USB port of my modem (!)).

When idle, the power draw is 2W. The RPi 3B can be used without any active, or even passive, cooling.

## Odroid XU4

### Specifications

The Odroid XU4 is based an 8-core (4\*A15@2.1 GHz + 4\*A7@1.4 GHz) machine, with 2 GiB of memory; is uses eMMC and/or micro SD for storage.

The XU4 is the top of the line Odroid, although it's in under development an RK3399-based product (2\*A72@2 GHz + 4\*A53@1.5 Ghz), which may become the next high-end SBC market reference.

A crucial development in the Odroid business strategy has been the partnership with a network of world-wide distributors.  
I advice not to buy an SBC from an overseas distributor/producer, for the high demand (time and money) in case of issues.

I purchased (from the German distributor) an XU4 all-inclusive set (with 16 GB eMMC) for 115€.

### Support and documentation

Odroid is a Chinese company, historical competitor of the RPi foundation (the other being Banana Pis; nowadays, the market is crowded).

I've been very impressed by the dedication put by Odroid to the documentation an support of their products.

While they're clearly not comparable to a world-size community like the RPi one, the company:

- actively participates to the forums
- keeps the documentation up to date, and extends it when/where useful
- improves the product based on community feedback
- maintains official Ubuntu and Android distributions

Again, the limitation must be kept in mind, however, when buying an Odroid product, a user has significant means of support.

Odroid provides an Ubuntu 16.04 distribution (provided in both desktop and server versions), and an Android one.

There is also an Armbian distribution (developed by the Armbian community).

### Usage impressions

I was blown away by the XU4 as soon as I started using it. Actually, before: writing to the eMMC was ten times as fast as writing to a (class 10) micro SD (30 MB/s vs. 3 MB/s).

The XU4's performance is essentially comparable to a low-end desktop, in a tiny package that consumes up to 15 W. I consider this impressive.

The amount of RAM (2 GiB) and the number of cores (8) allow a wide amount of operations to be performed; for example, one can build qBittorent (a relatively large C++ program) in a few minutes, with 8 parallel jobs.

For reference, one core (likely, one of the A15) bottlenecks the download bandwidth of a VPN connection at 100 MBit/s - five times as fast as the RPi 3B.

The downside of this is the power draw. There is no way an XU4 can be fed from the USB port of another device. With higher power demands, cooling also plays a role.

#### Power draw

Samples of power draw taken at different loads:

```csv
Load,Draw,Temperature (°C)
Idle,5,45
0.5,7,56
1,8.5,64
4,12.5,85
8,14.5,86
```

#### The infamous fan

There is a significant amount of discussion about the fan, which is in fact annoyingly noisy.

I spent some time investigating, and I've found that, fortunately, the XU4 standard cooling can be made fairly quiet without any hardware change.

In order to understand the problem and the solution, one needs to know the cooling logic.

The XU4 fan driver supports for "trip points" - a set of temperatures associated with fan speeds.

There are four trip points:

- up to 60 °C: no fan
- 60 °C: 120 PWM
- 70 °C: 180 PWM
- 80 °C: 240 PWM

While this configuration works well for an idle state, it leads to disaster under mild load.

Since without active cooling, with the standard fan, the temperature rises quickly, as soon as a user starts to perform some tasks, the CPU will alternate frequently below and after 60 °C, causing the fan to start and stop very frequently, which is *very* annoying.

There are a couple of solutions to this.

The most conservative, and simple, is to set the PWM of the first trip point to 80 (the minimum achievable); with this configuration, the fan will be always active, but also fairly quiet.

A more sophisticated approach, which requires tweaking, is to set the first trip point to around 50 °C at 80 PWM; this way, during idle times, the fan doesn't rotate, while during active (low) usage, it will rotate but quietly. The trickiness of this approach is that it requires to find the right temperature, which depends on the active usage load.

## Conclusions

In my opinion, the Raspberry Pis are excellent for the use case where they broke ground: hobbyist electronics.

I don't think that they are suitable as home servers, where the radically superior performance and flexibility of the XU4 makes a fundamental difference, for a relatively low difference in price (115 vs. 65 Euros).

## Footnotes

<a name="footnote01">¹</a>: This can be worked around, however, this bottleneck is crucial for evaluating the speed (slowness) of single-threaded performance.
