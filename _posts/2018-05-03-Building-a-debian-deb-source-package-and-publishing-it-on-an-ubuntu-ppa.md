---
layout: post
title: Building a Debian (`.deb`) source package, and publishing it on an Ubuntu PPA
tags: [c,distribution,linux,packaging,sysadmin,ubuntu]
last_modified_at: 2019-07-04 13:54:00
redirect_from:
- /Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa-part-1/
---

Although the concepts involved in preparing a Debian (`.deb`) source package and publishing it on an Ubuntu PPA are simple, due to the many moving parts involved, it's not easy to find a single source of information.

This article provides all the information required to perform the process, using a trivial program as an example.

Contents:

- [About the approach and standards](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#about-the-approach-and-standards)
- [Conventions](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#conventions)
- [The procedure](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#the-procedure)
  - [Setup](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#setup)
    - [Preparing the system](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#preparing-the-system)
    - [Setting up and publishing the PGP key(s)](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#setting-up-and-publishing-the-pgp-keys)
    - [Setting up a Launchpad account](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#setting-up-a-launchpad-account)
    - [Creating the PPA](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#creating-the-ppa)
  - [Preparing the source package](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#preparing-the-source-package)
    - [Introduction to Debian packaging](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#introduction-to-debian-packaging)
    - [Preparing the source code](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#preparing-the-source-code)
    - [The makefile](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#the-makefile)
    - [Debian packaging metadata creation and core concepts](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#debian-packaging-metadata-creation-and-core-concepts)
    - [Updating `changelog`](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#updating-changelog)
    - [Updating `control`](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#updating-control)
    - [Updating `copyright`](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#updating-copyright)
  - [Building the source package](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#building-the-source-package)
  - [Uploading the package](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#uploading-the-package)
  - [Deleting a package](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#deleting-a-package)
- [Using the PPA](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#using-the-ppa)
- [Conclusion](/Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa#conclusion)

## About the approach and standards

Since the concepts involved are quite simple (at least, the basic ones), the approach used is to describe what is required/used, and provide a link to get in-depth information.

It's assumed that the reader is a programmer, or at least, has working knowledge of programming and shell scripting concepts.

A few steps involve manual editing. I've used perl regexes to denote (automate) them; the reader can either use them, or simply open the required files in an editor.

## Conventions

The working directory is irrelevant - any is fine; the main work is performed in a subdirectory of it.

The following placeholder data is used:

- Author name: `Barry Foo`
- Email: barry@foo.baz
- Github project page: https://github.com/foobarry/testpackage
- Launchpad page: https://launchpad.net/~barryfoo
- PPA name: testppa

## The procedure

### Setup

#### Preparing the system

First, we install the required tools:

```sh
$ sudo apt install gnupg dput dh-make devscripts lintian
```

#### Setting up and publishing the PGP key(s)

The Ubuntu publishing platform is [Launchpad](https://launchpad.net/); operations on it require electronic signing, so the first thing is to:

- setup a PGP key (a good tutorial is [here](https://help.ubuntu.com/community/GnuPrivacyGuardHowto))

Ubuntu verifies the keys via its own key server, so next:

- the public key must be uploaded on the Ubuntu key server: https://keyserver.ubuntu.com

#### Setting up a Launchpad account

A Launchpad account is required; it can be:

- created on the [Launchpad login page](https://login.launchpad.net)

On creation, a user page will be created, which is also the user panel.

The crucial relevant step in this context is to:

- register the PGP key (via `OpenPGP keys` edit page: https://launchpad.net/~barryfoo/+editpgpkeys)

#### Creating the PPA

Now we:

- create the PPA (via `Create a new PPA` add page: https://launchpad.net/~barryfoo/+activate-ppa)

for this example, the PPA name will be `testppa`.

### Preparing the source package

#### Introduction to Debian packaging

The most widespread Debian package type is the binary package. It's very easy to create one as, in the basic form, they're essentially a snapshot of the files to install (plus, a minimal amount of metadata).

Publishing on a PPA requires source packages, instead: they are significantly more complex to prepare, due to the fact that they live in an ecosystem, rather than being a snapshot.

The concepts to deal with are:

- the Debian package metadata
- the Makefile
- the build system

#### Preparing the source code

First, we create a directory with a basic source file:

```sh
$ mkdir testpackage
$ cd testpackage

$ echo '#include <stdio.h>

int main()
{
  printf("Hello world!\n");
}
' > main.c
```

#### The makefile

For those not familiar with the it, the makefile is a file defining the operations related to a source code.

In this context, we're concerned (basically) with two operations:

- `all`: compiles the source code;
- `install`: installs it.

The following command will create a basic makefile including both operations:

```sh
$ echo -e 'BINDIR := /usr/bin

all:
\tgcc main.c -o my_hello_world

install:
\tmkdir -p ${DESTDIR}${BINDIR}
\tcp my_hello_world ${DESTDIR}${BINDIR}/
' > Makefile
```

A few notes:

1. the references to `$DESTDIR` are required because the build system has its own working directory (for compiling, installing, etc.), so the makefile must give the option to customize it; when the user builds/compiles on his environment via Make, `$DESTDIR` is not specified, so it doesn't affect his operations;
2. actions (operations) are indented via tab; using spaces will cause an error;
3. in case we want to copy to `/usr/local/bin`, additional operations are required, so we choose `/usr/bin` as example.

Something important to be aware of is that the build system will automatically infer the installed files structure by inspecting the result of `make install`; therefore, for simple packages, the developer doesn't need to specify anything explicitly.

#### Debian packaging metadata creation and core concepts

Now we need to create the package metadata templates:

```sh
$ dh_make -p testpackage_0.0.0.1 --single --native --copyright mit --email barry@foo.baz
$ rm debian/*.ex debian/*.EX 		# these files are not needed
```

This will create the Debian package metadata templates with the specified values; replace all the parameters with the intended ones.

The metadata is included in the (newly created) `debian/` directory, in the form of several files, which contain both informations about the package and the people involved, and (programmatic) instructions for the build/installation.

The strictly necessary files are:

- `changelog`: list of changelog entries, along with some other metadata, including the distribution
- `control`: the main body of the package metadata: dependencies, descriptions, links...
- `copyright`

##### Updating `changelog`

For the first release, the first entry is prefilled, so we only need to change the:

```sh
$ perl -i -pe "s/unstable/$(lsb_release -cs)/" debian/changelog
```

The parameter changed is called "distribution", in the "channel" sense of the term (see the [Debian reference](https://www.debian.org/doc/manuals/developers-reference/pkgs.html#distribution)); we replace it with the current developer O/S distribution.

Subsequent changelog updates can be performed via the `dch` tool.

##### Updating `control`

There are many changes to do here.

First, the [section](https://www.debian.org/doc/manuals/developers-reference/resources.html#archive-sections):

```sh
$ perl -i -pe 's/^(Section:).*/$1 utils/' debian/control
```

we just use the generic `utils` section.

Then, web references:

```sh
$ perl -i -pe 's/^(Homepage:).*/$1 https:\/\/testpackage.barryfoo.org/'              debian/control
$ perl -i -pe 's/^#(Vcs-Browser:).*/$1 https:\/\/github.com\/barryfoo\/testpackage/' debian/control
$ perl -i -pe 's/^#(Vcs-Git:).*/$1 https:\/\/github.com\/barryfoo\/testpackage.git/' debian/control
```

note that, for `Vcs-Git`, the Debian convention is to prefer the `https` source over `git` , since the first is (considered) necessarily public.

Now the descriptions:

```sh
$ perl -i -pe 's/^(Description:).*/$1 A short description/'                               debian/control
$ perl -i -pe $'s/^ <insert long description.*/ A long description,\n very long indeed!/' debian/control
```

each line of the long description must be indented with a single space.

And finally, housekeeping:

```sh
$ perl -i -pe 's/^(Standards-Version:) 3.9.6/$1 3.9.7/' debian/control
```

since, at least on Xenial, the default version used (3.9.6) is not the latest, and will cause a warning when building the package.

##### Updating `copyright`

Just put the basic information (current year, author name and email):

```sh
$ perl -i -0777 -pe "s/(Copyright: ).+\n +.+/\${1}$(date +%Y) Barry Foo <barry@foo.baz>/" debian/copyright
```

### Building the source package

We're ready now! Let's build the package:

```sh
$ debuild -S | tee /tmp/debuild.log 2>&1  	# log file used in the next section
```

This will create a few files in the parent of the current directory:

```
testpackage_0.0.0.1.dsc
testpackage_0.0.0.1_source.build
testpackage_0.0.0.1_source.changes
testpackage_0.0.0.1.tar.xz
```

The `dsc` and `changes` files contain, respectively, the package metadata and the changelog; both are signed.

### Uploading the package

Now the package [files] can be uploaded to the PPA, to be built and then published:

```sh
$ dput ppa:barryfoo/testppa "$(perl -ne 'print $1 if /dpkg-genchanges -S >(.*)/' /tmp/debuild.log)"  	# uses log file from previous section
```

If everything is fine, an email will be sent to the PGP email (typically within minutes), notifying that the package [version] is accepted.  

It's **crucial** that everything related to the PGP security is set up (see the specific section above), otherwise, Launchpad may act unexpectedly - in worst case, accepting the package but not publishing it without any warning, and preventing any further operation on the version uploaded.

In the background, the package will be built, and another email will be sent with the notification about the build final status (success/failure).

The builds are performed, by default, for the amd64 and i386 architectures; logs can be found in the package details page: https://launchpad.net/~barryfoo/+archive/ubuntu/testppa/+packages.

### Deleting a package

In case of botched operation, it's possible to delete a package [version] via Launchpad interface: 

- go to the PPA page
- click on `View Package details` (top right): https://launchpad.net/~barryfoo/+archive/ubuntu/testpackage/+packages
- click on `Delete packages` (top right): https://launchpad.net/~barryfoo/+archive/ubuntu/testpackage/+delete-packages

## Using the PPA

The PPA and the first package release are now ready!

The installation can be performed as usual:

```sh
$ sudo add-apt-repository ppa:barryfoo/testppa
$ sudo apt update
$ sudo apt install testpackage
```

## Conclusion

Distributing source packages has a particular significance - distributing the source code and the binaries (binary packages) of a program is crucial, however, it doesn't constitute not the whole picture, as building is an important part.

With this awareness, Debian has in fact started the [Reproducible builds initiative](https://wiki.debian.org/ReproducibleBuilds), with the objective of standardizing the build process for the Debian packages; the manifesto can be read [here](https://reproducible-builds.org/).

Hopefully, distributing source packages will become a more widespread practice; this post is an easy start for the interested people.
