---
layout: post
title: Installing Ruby Tk bindings/gem on Ubuntu
tags: [gui,ruby,ubuntu]
last_modified_at: 2018-10-04 22:44:00
---

The bindings for the standard Ruby GUI toolkit, Tk, need some trickery in order to be installed on Ubuntu. This article shows how to do it.

Contents:

- [Some history](/Installing-ruby-tk-bindings-gem-on-ubuntu#some-history)
- [Prerequisites](/Installing-ruby-tk-bindings-gem-on-ubuntu#prerequisites)
- [Workaround and installation](/Installing-ruby-tk-bindings-gem-on-ubuntu#workaround-and-installation)

## Some history

Until Ruby 2.3, the Tk module was part of Ruby; from 2.4 onwards, it has been extracted into [a gem](https://github.com/ruby/tk).

The extraction actually made the setup easier, as (not considering the workaround) instead of building the Tk extension and compiling the Ruby interpreter with it, the only operation required is to install the gem.

## Prerequisites

The Tcl/Tk libraries and development files need to be installed; the version depends on the O/S:

- on Ubuntu 18.04, install 8.5;
- on Ubuntu 20.04, install 8.6.

In this guide I'll use v8.5; Ubuntu 20.04 users can perform a simple textual search/replace in the commands provided.

Both versions have been verified on Ruby 2.5, 2.6 and 2.7. If v8.6 happened not to work on your (20.04) system, please leave a comment at the bottom, and in the meanwhile, try the v8.5 packages from the Ubuntu Bionic repository.

Install the required version of the (development) libraries:

```sh
$ sudo apt-get install tcl8.5-dev tk8.5-dev
```

## Workaround and installation

Ruby extensions are written in C, and they follow the typical steps of a C program build: configuration and compile.

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

The gem provides many switches for specifying the configuration parameters, however, the related parameters (`--with-tk-lib` and `--with-tcl-lib`) don't yield the desired effect (actually, any effect at all).

The workaround, originally found in [a Ruby forum](https://www.ruby-forum.com/t/building-ext-tk-on-ubuntu-14-04/231470/5) is to symlink the libraries to the paths where the extension expects them to be:

```sh
sudo ln -s /usr/lib/x86_64-linux-gnu/tcl8.5/tclConfig.sh /usr/lib/tclConfig.sh
sudo ln -s /usr/lib/x86_64-linux-gnu/tk8.5/tkConfig.sh /usr/lib/tkConfig.sh
sudo ln -s /usr/lib/x86_64-linux-gnu/libtcl8.5.so.0 /usr/lib/libtcl8.5.so.0
sudo ln -s /usr/lib/x86_64-linux-gnu/libtk8.5.so.0 /usr/lib/libtk8.5.so.0
```

After this, the gem will install without any problem!:

```
$ gem install tk
Building native extensions. This could take a while...
Successfully installed tk-0.2.0
1 gem installed
```
