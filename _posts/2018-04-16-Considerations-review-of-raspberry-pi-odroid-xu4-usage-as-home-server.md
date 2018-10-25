---
layout: post
title: Considerations (review) of Raspberry Pi/Odroid XU4 usage as home server
tags: [hardware]
last_modified_at: 2018-10-25 16:10:00
---

With the large diffusion of SBCs [Single Board Computers], and subsequent maturation of their ecosystem, it's now relatively easy to setup a home server.

I've had three SBCs until now; a Raspberry Pi 2 model B, a 3 model B, and recently, an Odroid XU4.

In this post, I'm going to share some considerations about their usage as home servers.

*Updated on 25/Oct/2018: added new RK3399 boards, and updated prices.*

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
  - [The infamous fan noise](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#the-infamous-fan-noise)
    - [Introduction](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#introduction)
    - [Base setup](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#base-setup)
    - [Solutions and references](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#solutions-and-references)
  - [Performance tweaking](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#performance-tweaking)
- [Alternatives](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#alternatives)
- [Benchmark](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#benchmark)
- [Conclusions](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#conclusions)
- [Footnotes](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#footnotes)

## General characteristics of an SBC/home server

The root question when considering SBC is: what is a home server?

Although there is no strict definition, a home server, typically:

- provides services within a private network;
- the services are not computationally intensive;
- it is relatively cheap;
- it is based on an easily maintainable operating system;
- it is realiable as much as desktop machine - in other words, it should operate for potentially extended amount of times, but without requiring any form of redundancy (processors, RAM, disks...);
- it may or may not have a large amount of storage (from dozens of GB to TB);
- it is compact in size.

Requirements are always very tricky; people may give more weight to a certain requirement rather than another.

In general, the SBC mentioned satisfy the above requirements.

Originally, the Raspberry Pi was groundbreaking because it made hobbyist electronics easy, due to the very low barrier of entry (both in price and in tooling).  
Although this is not strictly related to home server projects, it's important as context under which evaluate the boards.

In the following sections I will not discuss the RPi 2B - only the 3B and the XU4, as, for the purpose of home server, the latter RPi supersedes the former.

## Brief informations about ARM processors

The ARM processors for SBC are generally classified in two series; in the lower/mid-range, the most common are (latest > earliest generation):

- High-power: A72 > A57 > A15
- Low-power: A53 > A7

SBCs can also use a combination of more CPUs (like XU4's Exynos-5422), in order to suit the demand of the current load, swapping cores dynamically.

A searchable database of SBCs is [Board-DB.org](https://www.board-db.org).

## Raspberry Pi 3 Model B

### Specifications

The RPi 3B is a 4-core 1.4 GHz A53 machine, with 1 GiB of RAM; it uses micro SD for storage.

It's not very easy to assess the price; a standard configuration comprises:

- board: 45$
- sd card, 16 GB: 16$
- power supply + cable: 18$

For a very approximate amount of 80$.

It's possible to save 10 or more USD by buying an incendiary power supply from Amazon or any Chinese direct seller.

### Support and documentation

Raspberry Pis are widely and very well supported/documented; they're essentially the state of the art in this aspect.

The Raspbian is essentially a standard Debian distribution.

#### BEWARE: Stay far from the Ubuntu Pi Flavour Maker

I'm dedicating an entire section because this is an exceptional case of engineering irresponsibility.

Do **not** use the Ubuntu Pi Flavour Maker for the Raspberry Pi 3; it's broken.

There is [a critical bug](https://bugs.launchpad.net/ubuntu/+source/linux-raspi2/+bug/1652270) that causes the O/S to brick on the first reboot, if the system is updated. Since updates are automatic, first-time users of this distribution will have a nasty surprise on first reboot, without any obvious sign.

I consider this an exceptional case of irresponsibility because the maintainer(s) are refusing to put any warning (check out [the website](https://ubuntu-pi-flavour-maker.org)), or pull out this distribution entirely, even if this source is one of the top results in the search engines, and the bug is official.

Instead, RPi 3 users should use [Raspbian](https://www.raspbian.org), which works as intended.

### Usage impressions

The RPi 3B works OK as home server; the major problem is that it's very slow, due to both the processor and the storage.

While the available RAM, 1 GiB, is not a lot, it is not a bottleneck for the typical home server services; on a headless configuration, assuming 100/150 MB per service, there is space for 6/7 running in parallel (even ignoring that unused process pages can be swapped out).

Having both slow processor and storage though, is a deadly combination, as many tasks will be affected either by one or another.

Even basic tasks like updating the packages can take long times (dozens of minutes); let alone intensive tasks like compiling a program.

For reference, the RPi 3B bottlenecks the download bandwidth of a VPN connection to 20 MBit/s [¹](#footnote01).

The upside is the power draw, which is low to the point that when used without peripherals in a headless configuration, it can fed entirely from the USB port of a desktop device (I use it connected to the USB port of my modem (!)).

When idle, the power draw is 2W. The RPi 3B can be used without any active, or even passive, cooling.

## Odroid XU4

### Specifications

The Odroid XU4 is based an 8-core (4\*A15@2.1 GHz + 4\*A7@1.4 GHz) machine, with 2 GiB of memory; is uses eMMC and/or micro SD for storage.

The XU4 is currently the top of the Odroid line; the next high-end model (Odroid-N2) will be released in 2019 (see [Alternatives](/Considerations-review-of-raspberry-pi-odroid-xu4-usage-as-home-server#alternatives)).

A crucial development in the Odroid business strategy has been the partnership with a network of world-wide distributors.  
I advice not to buy an SBC from an overseas distributor/producer, for the high demand (time and money) in case of issues.

I purchased in April 2018 (from the German distributor) an XU4 all-inclusive set (with 16 GB eMMC, power supply and housing) for 135$ plus shipment, although now (September 2018), the board itself can be found for as low as 60$.

### Support and documentation

Hardkernel is a Chinese company, historical competitor of the RPi foundation (the other being Banana Pis; nowadays, the market is crowded).

I've been very impressed by the dedication put by Hardkernel to the documentation and support of their products.

While they're clearly not comparable to a world-size community like the RPi one, the company:

- actively participates to the forums
- keeps the documentation up to date, and extends it when/where useful
- improves the product based on community feedback
- maintains official Ubuntu and Android distributions

Hardkernel provides an Ubuntu 16.04 distribution (provided in both desktop and server versions), and an Android one.

Again, the community limitation must be kept in mind - especially in the Linux case, it's not possible to know if the hardware support will be mainlined in the next years, and if not, what will happen to it. 

There is also an Armbian distribution (developed by the Armbian community).

### Usage impressions

I was blown away by the XU4 as soon as I started using it. Actually, even before: writing to the eMMC was an order of magnitude faster than writing to a (class 10) micro SD (30+ MB/s vs. 3+ MB/s).

The XU4's performance is essentially comparable to a low-end desktop, in a tiny package that consumes up to 15 W. I consider this impressive.

The amount of RAM (2 GiB) and the number of cores (8) allow a wide amount of operations to be performed; for example, one can build qBittorent (a mid-sized C++ program) in a few minutes, with 8 parallel jobs.

For reference, one core (likely, one of the A15) bottlenecks the download bandwidth of a VPN connection at 100 MBit/s - five times as fast as the RPi 3B.

The downside of this is the power draw. There is no way an XU4 can be fed from the USB port of another device. With higher power demands, cooling also plays a role.

### Power draw

Samples of power draw taken at different loads, with default settings (see next sections):

```csv
Load,Draw,Temperature (°C)
Idle,5,45
0.5,7,56
1,8.5,64
4,12.5,85
8,14.5,86
```

### The infamous fan noise

#### Introduction

There is a significant amount of discussion about the fan, which is in fact annoyingly noisy.

I spent some time investigating, and I've found that, fortunately, the XU4 standard cooling can be made fairly quiet without any hardware change.

There are two concepts two be aware of in order to tackle the solution: the governor and the fan driver trip points.

The CPU governor is the kernel code that manages the CPU speed based on the demand. Although of course the implementation are strictly based on the O/S and CPU, there are a few denominations which are typically shared between all the governors.

Two typical governors are `Ondemand` and `Performance`. The former adjusts the load very dynamically, based on the load; the latter runs the CPU at full speed.

The second concept to know is how the fan driver works.

The XU4 fan driver is based on "trip points" - a set of temperatures associated with fan speeds.

There are four trip points; the preset values are:

- up to 60 °C: no fan
- 60 °C: 120 PWM
- 70 °C: 180 PWM
- 80 °C: 240 PWM

#### Base setup

On Ubuntu 4.14, the XU is setup with a `performance` governor, and the trip points above.

The problem is that the first trip point is excessively optimistic: with passive cooling [of the standard fan], the temperature rises quickly even under idle conditions or light load.

This will cause an infinite cycle:

1. the fan kicks in at 60 °C;
2. the temperature drops;
3. the fan stops;
4. the temperature rises;
5. back to point 1.

The continuous switch on/off is very noisy, and essentially, can't be interrupted.

#### Solutions and references

The most conservative, and simple solution, is to set the PWM of the first trip point to 80 (the minimum achievable); with this configuration, the fan will be always active, but also fairly quiet.

Under idle conditions, or light load, the temperature will stabilize at \~45 °C, which is cool.

A more elaborate solution is to use the `ondemand` governor; since the CPU will not run all the time at the max speed, the power consumption will be lower, potentially allowing passive cooling for idle/light load.

The downside of an `ondemand` governor is that it needs to be tweaked accordingly to the usage pattern, in order to react quick enough, but not too rigidly, to the CPU load changes; this concept is essentially the same of how car shock absorbers work.

A reference article for governor tweaking can be found [here](https://obihoernchen.net/1235/odroid-xu4-with-openmediavault/).

### Performance tweaking

For power users, it's possible to "pin" demanding processes to the faster cores; a discussion about a pinning example is [here](https://forum.odroid.com/viewtopic.php?f=95&t=30613).

## Alternatives

The market is quickly evolving; new CPUs/boards are introduced every year, and existing ones are proposed at lower prices.

A notable CPU is the RK3399; it has 2 high-power (A72) and 4 low-power (A53) cores, less but newer/faster than the Exynos-5422 (4\*A15 + 4\*A7). 
Recently, cheap RK3399 SBCs surfaced, with a base price just a bit more expensive than the XU4 (60+$ vs 70+$):

- Friendly Elec NanoPi M4: ~70$; 2GB RAM (options available); worldwide distributors
- Vamrs Rock960: 79$; 2 GB RAM (options available); ships from China
- Orange Pi RK3399: 109$; 2GB RAM/integrated 16 GB eMMC (options available); ships from China
- Libre Computer Renegade Elite: 99$; 4GB RAM; release date unclear

Overall, the NanoPC-T4 is a very attractively priced board, however, a very careful analysis should be performed - primarily of software support and cooling.

Interestingly, Hardkernel had in plan an RK3399 based product, the Odroid-N1, however, due to changes in the hardware landscape, they moved to a new project, the N2, with "faster CPU/GPU cores and native DDR4 support" (see [here](https://forum.odroid.com/viewtopic.php?f=149&t=31277)). This new SBC is planned to be released in early 2019.

## Benchmark

I've tested the XU4 with the Phoronix Test Suite; this benchmark uses real-world applications, so the test results can be reasonably (within limits) used a reference.

The results are published on OpenBenchmarking.org, [on this page](https://openbenchmarking.org/result/1805276-FO-1703199RI52).

This is a summary composed of an RPi 3B, the XU4, and also the Nvidia Jetson TX1:

| Test | Raspberry Pi 3 Model B | ODROID-XU4 | Jetson TX1 |
| ---- | ---------------------- | ---------- | ---------- |
| pts/fftw-1.1.0 - fftw-stock/tests/bench  --time-repeat 100 -opatient ibc256x256 | 150.89 | 1218.18 | 1615.9 |
| pts/john-the-ripper-1.5.1 - BLOWFISH | 510 | 1284 | 1354 |
| pts/c-ray-1.1.0 - | 254.13 | 85.04 | 107.22 |
| pts/smallpt-1.0.2 - | 1400 | 499 | 441 |
| pts/encode-flac-1.5.0 - | 228.74 | 53.35 | 43.81 |
| pts/redis-1.0.0 - -t set | 138793.89 | 179642.33 | 396905.94 |
| pts/redis-1.0.0 - -t get | 170020.06 | 206553.59 | 484971.9 |
| pts/mafft-1.4.0 - | 54.92 | 17.14 | 16.88 |
| pts/himeno-1.2.0 - | 56.51 | 161.38 | 229.56 |
| pts/openssl-1.9.0 - | 19.98 | 60.37 | 39.07 |

For reference, the Jetson TX1 is has 4\*A57@1.73 GHz.

The XU4 is consistently faster, around 3 times as the RPi. This large margin is inline with my experience, where OpenVPN decryption is 5x as fast.

## Conclusions

Users have wildly different requirements, so there is no better or worse product, in absolute terms.

In general, there are three categories of home servers:

- as cheapest as possible SBCs (~50/60$ range)
- moderately cheap but sufficiently performing SBCs (~100/120$)
- mini servers PCs (300$+)

Mini servers are frequently mentioned in discussions, however, their price point and size is significantly higher (they can be found for lower prices in special offers, but that makes them an apples-to-oranges comparison).  
I'm also excluding SBCs with big (3.5") disks (or even RAID configurations) because they start to lose the advantages compared to mini server PCS.

In my opinion, the Raspberry Pis are excellent for the use case where they broke ground: hobbyist electronics.

They're OK as home server, however it's important to consider the long term usage; buying a cheap board as a toy it's fine, however, in the longer term, the low performance can be limiting or significantly annoying.

In the long-term perspective, SBCs like the XU4 make a radical difference, for a relatively low difference in price (in the configuration above, 140 vs. 85 USD).

Considering external storage makes the comparison somewhat more complex; there's plenty of compact cases for RPis with 2.5" disks, and only a few (or even only one) for XU4.  
On the other hand, velcroing an XU4 case to a portable 2.5" is still a very functional solution, being very compact and not requiring an additional power supply. This is not a solution for everybody's taste, though.

## Footnotes

<a name="footnote01">¹</a>: This can be worked around, however, this bottleneck is crucial for evaluating the speed (slowness) of single-threaded performance.
