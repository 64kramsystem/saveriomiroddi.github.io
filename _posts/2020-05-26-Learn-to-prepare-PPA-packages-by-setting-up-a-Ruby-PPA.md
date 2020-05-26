---
layout: post
title: Learn to prepare PPA packages, by setting up a Ruby PPA
tags: [distribution,linux,packaging,ruby,shell_scripting,sysadmin,ubuntu]
---

(Those looking for a ready Ruby PPA, please have a look at the [announcement article]({% post_url 2020-05-26-Announcement-Ticketsolve-s-Ruby-PPA-is-available %}) )

Recently, the ubiquitous [Brightbox Ruby PPA](https://www.brightbox.com/docs/ruby/ubuntu) has been discontinued.

This caused a problem, because there aren't other stable Ruby PPAs, thus requiring engineers to manually package their own Ruby.

In this article, I'll explain how to setup a Ruby PPA and the related scripts, so that engineers can package and automatically deploy their own Ruby, and, very importantly, benefit from automated updates, virtually without any manual operation.

I've dealt with the PPA subject [in the past](Building-a-debian-deb-source-package-and-publishing-it-on-an-ubuntu-ppa); this article is an "updated, extended, and more automated version"™.

Content:
- [Disclaimer](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#disclaimer)
- [Requirements](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#requirements)
  - [System preparation](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#system-preparation)
- [Procedure](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#procedure)
  - [High-level overview](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#high-level-overview)
  - [Procedure style](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#procedure-style)
  - [Preparation: variables](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#preparation-variables)
  - [Preparing the package base metadata](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#preparing-the-package-base-metadata)
  - [Preparing the `debian/rules`](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#preparing-the-debianrules)
  - [Builder configuration](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#builder-configuration)
  - [Per-distro build steps](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#per-distro-build-steps)
  - [Building the source package](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#building-the-source-package)
  - [Testing the build](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#testing-the-build)
  - [Uploading the package](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#uploading-the-package)
- [Automating the operation](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#automating-the-operation)
- [Conclusion](/Learn-to-prepare-PPA-packages-by-setting-up-a-Ruby-PPA#conclusion)

## Disclaimer

It's important to clarify the package structure underlined in this article.

Building packages with rigorous structure is not a trivial task, and arguably, it's also not a really interesting one, as it's entirely, or almost, boilerplate.

The structure I'm presenting here is the simplest possible one for a Ruby distribution; in other words, it's the virtual equivalent of running Ruby's standard `make install`, with the added benefits of the Debian packaging (explicit dependencies and possible automatic updates).

Like Ruby's standard `make install` installation, this configuration doesn't prevent users from shooting themselves in the foot by installing conflicting packages (ie. Ruby or Ruby-related).

This is not a problem (for example, Fullstaq Ruby does essentially the same, just with a different installation prefix), as long as the users are aware of the choice.

## Requirements

The following are the requirements for the procedure:

- GnuPG installed, with a key configured, signed, trusted, and published on https://keyserver.ubuntu.com
- a Launchpad account set up
- a PPA set up (creating one and uploading the PGP key is enough)
- an Ubuntu 20.04 system, with the packages `dh-make`, `devscripts` and `cowbuilder` installed
- a Ruby source tarball (downloadable from the [official page](https://www.ruby-lang.org/en/downloads))
- the Bash shell (execution under Zsh may fail)
- all the commands must be run in a single shell

Instructions for the operations that can be executed via terminal, are provided in the [next section](#system-preparation).

### System preparation

Install the required packages:

```sh
apt install -y dh-make devscripts cowbuilder
```

Prepare the PGP key:

```sh
# Generate a key, if not existing already.
#
gpg --gen-key

# Make sure the key is signed and trusted.
#
printf $'fpr\nsign\n'   | gpg --command-fd 0 --edit-key <key_id_or_email>
printf $'trust\n5\ny\n' | gpg --command-fd 0 --edit-key <key_id_or_email>
```

Setup a builder test distro:

```sh
v_build_distro=bionic
builder_distros_path="/var/cache/pbuilder/distros"

sudo mkdir "$builder_distros_path"

sudo cowbuilder --create --basepath "$builder_distros_path/$v_build_distro" --distribution "$v_build_distro"
```

Although using multiple distros can be configured using a `~/.pbuilderrc` initscript, for simplicity, in this article I'll use `--basepath`.

An important concept is to simulate the Launchpad build environment more accurately, by matching (some of) the installed packages:

```sh
echo '
EXTRAPACKAGES="dwz pkgbinarymangler"
' | sudo tee -a /etc/pbuilderrc
```

Such programs are used automatically by the builders when found, and since at least one (`dwz`) is a troublemaker, by installing it on the local builder, it will be possible to catch build problems earlier in the process, rather than waiting for the Launchpad build to fail.

Now let's download and unpack Ruby:

```sh
v_project_directory=~/ppas/ruby-2.6.6
mkdir -p "$v_project_directory"
wget -qO- https://cache.ruby-lang.org/pub/ruby/2.6/ruby-2.6.6.tar.gz | tar xvz -C "$(dirname "$v_project_directory")"
```

## Procedure

### High-level overview

Starting from an unpacked and configured tarball:

- the package metadata is created and updated, with the most important steps being:
  - defining the package name and version
  - defining the dependencies (build-time and installation-time)
  - overriding some undesired builder tasks (rules)
- for each given target Ubuntu distribution
  - define the packaging framework version
  - (re)define the changelog entry
  - create the source package
  - optionally build it on a local testing environment
  - upload it to Launchpad

### Procedure style

The procedure is styled in script form, using upfront variables, which allows easy customization.

Additionally, the code comes straight out of the [project I use for packaging](https://github.com/saveriomiroddi/ppa_packaging), which can be used directly as opposed to manually executing the commands.

### Preparation: variables

First, let's define basic, self-explanatory data:

```sh
# Those two have been defined in the previous section.
v_project_directory=~/ppas/ruby-2.6.6
export v_build_distro=bionic

export v_ppa_address=ppa:saverio/ruby-test
export v_author_email=saverio.notrealemail@gmail.com
export v_description='Interpreter of object-oriented scripting language Ruby'
export v_long_description="\
Ruby is the interpreted scripting language for quick and easy
object-oriented programming.  It has many features to process text
files and to do system management tasks (as in perl).  It is simple,
straight-forward, and extensible.

This package provides up-to-date patch versions of the Ruby branch;
major/minor versions are not updated."
export v_section='interpreters'
export v_homepage='https://www.ruby-lang.org/'
export v_vcs_browser='https://github.com/ruby/ruby/'
export v_vcs_git='https://github.com/ruby/ruby.git'
```

Now, let's get to versioning:

```sh
export v_package_name=ruby2.6
export v_package_version_with_debian=2.6.6-$(whoami)1
```

We are defining a package `ruby2.6` name which keeps the major and minor Ruby version fixed, and will update the patch versions; this is a common practice for avoiding breakages due to the major/minor version upgrades, while keeping the bugfixes of the patch versions.

The so-called "debian version" (in this case, if the logged in user is `foobar`, translates to `foobar1`) is generally used for package-related changes (like in this context), or for indicating new patches to the upstream version (like the standard Debian/Ubuntu packages).

Say that we add an installation dependency (e.g. `libgmp-dev`) which we missed in our first release; since the Ruby version itself hasn't changed, we just bump the Debian version:

```sh
# Example; not necessary in this procedure.
#
export v_package_version_with_debian=2.6.6-$(whoami)2
```

Now, the copyright:

```sh
v_dhmake_copyright_options=(--copyright custom --copyrightfile "$v_project_directory/BSDL")
```

We manually specify the copyright (file) because the Ruby license is not supported by the tooling (specifically, by `dh_make`).

Let's configure the dependencies:

```sh
export v_build_depends="autoconf,automake,bison,ca-certificates,curl,libc6-dev,libffi-dev,libgdbm-dev,libncurses5-dev,libsqlite3-dev,libtool,libyaml-dev,make,openssl,patch,pkg-config,sqlite3,zlib1g,zlib1g-dev,libreadline-dev,libssl-dev,libgmp-dev"
export v_depends="libgmp-dev"
```

Very likely, we don't need so many build dependencies, but it's best to avoid having to add new ones in the future; adding build dependencies won't affect the built package, so there are no side effects.

The installation dependencies (`libgmp-dev`) in this case are important. One may actually place here all the packages required by the gems used by the target application(s); this avoids developers having to figure out which packages to install when building the gems.

Finally, some constants (explained in later sections):

```sh
export c_changelog_description="Upstream version"
c_pbuilder_distros_base_path="/var/cache/pbuilder/distros"
c_pbuilder_output_dir="/var/cache/pbuilder/result"
c_package_ppa_version=1
declare -A c_debhelper_distro_versions=([focal]=12 [bionic]=11 [xenial]=9)
```

### Preparing the package base metadata

Switch to the source directory:

```sh
cd "$v_project_directory"
```

And (re)create the basic metadata:

```sh
rm -rf debian

# The phony name is replaced at upload time.
#
dh_make -p "${v_package_name}_1.2.3-foo4~bar5" --yes --single --native "${v_dhmake_copyright_options[@]}" --email "$v_author_email"
rm debian/*.ex debian/*.EX
```

Let's add a stock changelog entry:

```sh
# The version change part of this file is performed at the distro cycle.
#
# Example, prior to the change:
#
#     ruby2.5 (1.2.3-foo4~bar5) unstable; urgency=medium
#
#       * Initial Release.
#
#      -- Saverio Miroddi <saverio.notrealemail@gmail.com>  Thu, 21 May 2020 11:58:40 +0200
#
perl -i -pe 's/Initial Release/$ENV{c_changelog_description}/' debian/changelog
```

While the changelog is normally performed via `dch` tool, in this case we want to modify the existing entry, preferably non-interactively, so we've changed it manually.

Now let's set the dependencies, and some other metadata:

```sh
perl -i -pe 's/^Build-Depends: .*\K/,$ENV{build_depends}/' debian/control
perl -i -pe 's/^Depends: .*\K/,$ENV{depends}/'             debian/control
perl -i -pe 's/^Section: \K.*/$ENV{v_section}/'            debian/control
perl -i -pe 's/^Homepage: \K.*/$ENV{v_homepage}/'          debian/control
perl -i -pe 's/^Description: \K.*/$ENV{v_description}/'    debian/control
perl -i -pe 's/^#(Vcs-Browser:).*/$1 $ENV{v_vcs_browser}/' debian/control
perl -i -pe 's/^#(Vcs-Git:).*/$1 $ENV{v_vcs_git}/'         debian/control
```

The long description requires some processing; each line needs to be prefixed with a space, and empty lines are encoded as dots (`.`):

```sh
while IFS= read -r description_line; do
  [[ -z $description_line ]] && description_line="."
  processed_long_description+=" $description_line"$'\n'
done <<< $v_long_description

description=$processed_long_description perl -i -pe 's/^ <insert long description.*/$ENV{description}/' debian/control
```

A passage we skip is the architectures to build:

```sh
# perl -i -pe 's/^(Architecture:) .*/$1 amd64/' debian/control
```

We leave the default as is (`any`); and select the architectures via PPA configuration (the defaults are `amd64` and `i386`).

### Preparing the `debian/rules`

Builders base their execution on the project makefile.

In our case, we want to change some behavior; in terms of Debian packaging standards, this is performed via `debian/rules`, which allows customization of the original makefile.

The `debian/rules` file, as generated by `dh_make`, simplify forwards all the tasks to the original makefile; this is a sample (edited) version:

```makefile
#!/usr/bin/make -f

# See debhelper(7) (uncomment to enable)
# output every command that modifies files on the build system.
#export DH_VERBOSE = 1

%:
	dh $@
```

An optional, convenient, step is to enable the debugging log:

```sh
perl -i -pe 's/.*(export DH_VERBOSE).*/$1=1/' debian/rules
```

Now, something we need to disable is the `jwz` execution:

```sh
echo $'override_dh_dwz:
\techo Skipping dh_dwz target

' >> debian/rules
```

`dwz` is an optimizer, which in the Ruby context, is troublesome, because it doesn't manage to compress the intended files, and exits with error, breaking the build.

We use standard Makefile syntax to override the rule `dh_dwz`.

We can optionally skip the test suite:

```sh
printf $'override_dh_auto_test:
\techo Skipping dh_auto_test target

' >> debian/rules
```

Doing this will cause no tests to be run during the package build (in case there is a test suite; Ruby has one). This is at discretion of the engineer; the Ruby test suite doesn't take much time, so one can leave it as it is.

### Builder configuration

When a builder runs, it executes `./configure`, which generates a `Makefile`, tailored to the system.

The standard Launchpad configuration is:

```sh
./configure --build=x86_64-linux-gnu --prefix=/usr --includedir=\${prefix}/include --mandir=\${prefix}/share/man
  --infodir=\${prefix}/share/info --sysconfdir=/etc --localstatedir=/var --disable-silent-rules --libdir=\${prefix}/lib/x86_64-linux-gnu
  --runstatedir=/run --disable-maintainer-mode --disable-dependency-tracking
```

This is a valid configuration, and we don't need to change it.

It's important to know that it diverges from the default Ruby source configuration, whose prefix is `/usr/local` (which causes binaries to be installed under `/usr/local/bin`).

Installing under `/usr/local/bin` breaks the Debian standard, which dictates installation under `/usr/bin`.

Those who want to break this standard need to be aware that it will break at least another target (`dh_usrlocal`), and it will cause `debuild` (a tool invoked later) to fail.

If one wants to tweak the Makefile configuration step (`./configure ...`), just override the rule:

```sh
printf $'override_dh_auto_configure:
\t./configure --myoption=myvalue

' >> debian/rules
```

### Per-distro build steps

Now we configure the distro-dependent metadata.

This step could actually be performed before, however, if one wants to script the entire operation, the last step is likely a for-cycle with commands [using a distro variable](https://github.com/saveriomiroddi/ppa_packaging/blob/master/prepare_ppa_package#L282).

The package version is not completed yet! We still need to append another, distro-dependent suffix, because the PPA needs unique package versions, even if they belong to different distros:

```sh
# Example: `ruby2.6.6-foobar1~bionic1`
#
package_version_with_ppa=${v_package_version_with_debian}~${v_build_distro}${c_package_ppa_version}
```

Now, we update the changelog entry header:

```sh
# Change the first line to be in the format:
#
#     ruby2.6 (ruby2.6.6-foobar1~bionic1) bionic; urgency=medium
#
sed -i -E "1c$v_package_name ($package_version_with_ppa) ${v_build_distro}; urgency=medium" debian/changelog
```

One, annoying, part, is the debhelper version constraint; we need to instruct the build about the packaging version, however, the definition format changed between Ubuntu versions, and additionally, we need to take care of a few quirks. We define a function for this:

```sh
# Creates `debian/compat`, if required, and returns the build-dependency package
# definition.
#
# $1: debhelper version
#
function prepare_debhelper_dependency {
  if [[ $1 -le 9 ]]; then
    # Insanity. In case of v9:
    #
    # - the package is `debhelper`;
    # - debuild requires `debian/compat` to be specified; but it must not be specified when the
    #   package is `debhelper-compat` (v11+);
    # - `= 9` doesn't work (the current package version is `9.20160115ubuntu3`), although,
    #   with `debhelper-compat`, `= X` works with versions `X.Y` (eg. `11.2`).
    #
    echo -n "debhelper (>= 9)"
    echo "9" > debian/compat
  else
    echo -n "debhelper-compat (= $1)"
  fi
}

export debhelper_dependency=$(prepare_debhelper_dependency "${c_debhelper_distro_versions[$v_build_distro]}")
perl -i -pe 's/debhelper-compat \(.+?\)/$ENV{debhelper_dependency}/' debian/control
```

### Building the source package

We're done with the configuration! The last bit of "insanity" is in the package builder tool itself.

Specifically, the tool is called `debuild`, which is a wrapper around a few other tools. Because of this structure, the first oddity one comes across is that the options are dispatched to the underlying programs, based on their position (!).

In practice, the options need to have a specific order, and at least one option don't even work as expected. The command we'll use is:

```sh
debuild --no-tgz-check -d -S -Zgzip --tar-ignore=//
```

There are quite a few things to know:

option            | explanation
-                 | -
`--no-tgz-check`  | don't search for the original source when a debian version is present;
`-d`              | skip the dependency checks, due to `debhelper` on xenial (debuild assumes that the build happens on the same machine, which is not the case);
`-S`              | build a source package; `--build=source` is the long form, but oddly, doesn't find the changes file during build;
`-Zgzip`          | fast compression (the end package is different, anyway);
`--tar-ignore=//` | the invoked `dpkg-source` filters out some files by default, including `.gitignore`, which is needed by some bundled gems - this sets a phony pattern.

By far, the most insidious issue is the one solved by `--tar-ignore=//`. Without this, Ruby will fail while building at least one of the prepackaged gems, with a headscratching error; the value `//` is phony, and it's meant not to match any file, therefore overriding the default.

The tool also creates `debian/files`, which can be ignored.

### Testing the build

Time to build the package! We feed cowbuilder the `des`cription file of the source package, and let it build:

```sh
# Sample: ruby2.6_ruby2.6.6-foobar1~bionic1
#
package_name_with_version_with_ppa="${v_package_name}_${package_version_with_ppa}"

sudo cowbuilder --build --basepath "$c_pbuilder_distros_base_path/$v_build_distro" --distribution "$v_build_distro" "../${package_name_with_version_with_ppa}.dsc"
```

The package will be built as:

```sh
echo "Built package: $c_pbuilder_output_dir/${package_name_with_version_with_ppa}_amd64.deb"
```

We don't really need it (the PPA doesn't accept binary packages; only source ones), but it proves that our specification is finally complete and ready to be shipped to the PPA.

### Uploading the package

Once the build succeeds, we can upload the package:

```sh
dput "$v_ppa_address" "../${package_name_with_version_with_ppa}_source.changes"
```

We're done! Shortly after upload, Launchpad will send an email with the package acceptance (or rejection).

A motive for rejection can be that, for example, there is a more recent version of the package already in the PPA, or the same (once published, a given version can't be replaced, but only deleted).

If the acceptance email is not sent in a short time, there is likely an issue with the PGP key.

## Automating the operation

In order to prepare Ruby PPA packages, you can either read and apply all the above, or:

1. make sure the `Requirements` are satisfied
2. `git clone https://github.com/saveriomiroddi/ppa_packaging.git`
3. `ppa_packaging/prepare_ruby_packages --upload ppa:myaccount/my-ruby-ppa myuser1 my@email.com`

which will download, package, and upload, all the current stable Ruby versions.

There are also a few useful options available, and a more generic `prepare_ppa_package` is provided.

## Conclusion

We've built our Ruby, and made it available for (internal) distribution.

It's not exactly a trivial job (it costed me a lot of hair), but it can be scripted easily, and most importantly, I find PPAs a great platform for software distribution, in particular, considering that nowadays a certain value is put into tracing the exact (open) software production chain (see, for example, the Debian [Reproducible Build initiative](https://wiki.debian.org/ReproducibleBuilds)).

If one wants to explore how more complex projects are packaged (or, to exact, even how to _properly_ package Ruby for large distribution), it's a child's play - just use the specific `add-apt-repository` option:

```sh
sudo add-apt-repository -y --enable-source ppa:brightbox/ruby-ng
apt-get source ruby2.6
```

and investigate the downloaded (source) package.

Happy distribution!
