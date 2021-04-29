---
layout: post
title: Installing Ruby Tk bindings/gem on Ubuntu
tags: [gui,ruby,ubuntu]
last_modified_at: 2021-04-29 10:34:00
---

The bindings for the standard Ruby GUI toolkit, Tk, need some trickery in order to be installed on Ubuntu. This article shows how to do it.

*Updated on 29/Apr/2021: Updated procedure to use Rubygems' provided options for build flags.*

Contents:

- [Some history](/Installing-ruby-tk-bindings-gem-on-ubuntu#some-history)
- [Prerequisites](/Installing-ruby-tk-bindings-gem-on-ubuntu#prerequisites)
- [Workaround and installation](/Installing-ruby-tk-bindings-gem-on-ubuntu#workaround-and-installation)

## Some history

Until Ruby 2.3, the Tk module was part of Ruby; from 2.4 onwards, it has been extracted into [a gem](https://github.com/ruby/tk).

The extraction actually made the setup easier, as (not considering the workaround) instead of building the Tk extension and compiling the Ruby interpreter with it, the only operation required is to install the gem.

## Prerequisites

Different Ubuntu versions may ship different Tcl/Tk versions, or even (ie. Ubuntu 18.04) with multiple versions.

Generally speaking, one can use the latest version (8.6 for both Ubuntu 18.04 and 20.04); if 8.6 happens not to work, use version 8.5.

First, let's install the Tcl/Tk development libraries:

```sh
# Ignore the apt `WARNING: apt does not have a stable CLI interface`.
#
# If 8.6 doesn't work, set `latest_version=8.5`.
#
$ latest_version=$(apt search '^tcl[[:digit:]]+\.[[:digit:]]+-dev' | perl -lne 'print /^tcl(\d+\.\d+)/' | sort -V | tail -n 1)

# If the compiler suite is not installed, this will do it.
#
$ sudo apt-get install --yes "tcl${latest_version}-dev" "tk${latest_version}-dev"
```

## Workaround and installation

Ruby extensions are written in C, and they follow the typical steps of a C program build: configuration and compilation.

The gem installation takes care of both, however, on Ubuntu, the Tcl/Tk library files are not found:

```
$ gem install tk
Building native extensions. This could take a while...
ERROR:  Error installing tk:
  ERROR: Failed to build gem native extension.
# ...
Search tcl.h
checking for tcl.h... no
Search tk.h
checking for tk.h... no
Search Tcl library............*** extconf.rb failed ***
# ...
Warning:: cannot find Tcl library. tcltklib will not be compiled (tcltklib is disabled on your Ruby. That is, Ruby/Tk will not work). Please check configure options.

Can't find proper Tcl/Tk libraries. So, can't make tcltklib.so which is required by Ruby/Tk.
If you have Tcl/Tk libraries on your environment, you may be able to use them with configure options (see ext/tk/README.tcltklib).
```

This is because the gem expects the libraries to be under `/usr/lib`, while in Ubuntu, they're under `/usr/lib/x86_64-linux-gnu`.

The gem provides the options for specifying the locations - the key is to pass them not as Rubygems options, rather, as build flags:

```sh
$ Usage: gem install GEMNAME [GEMNAME ...] [options] -- --build-flags [options]
```

which is accomplished by specifying two dashes (`--`) before the build flags.

Therefore, we can build the gem this way:

```
$ gem install tk -- \
  --with-tcltkversion="$latest_version" \
  --with-tcl-lib=/usr/lib/x86_64-linux-gnu \
  --with-tk-lib=/usr/lib/x86_64-linux-gnu \
  --with-tcl-include=/usr/include/tcl"$latest_version" \
  --with-tk-include=/usr/include/tcl"$latest_version" \
  --enable-pthread
Building native extensions with: '--with-tcltkversion=8.6 --with-tcl-lib=/usr/lib/x86_64-linux-gnu --with-tk-lib=/usr/lib/x86_64-linux-gnu --with-tcl-include=/usr/include/tcl8.6 --with-tk-include=/usr/include/tcl8.6 --enable-pthread'
This could take a while...
Successfully installed tk-0.4.0
1 gem installed
```
