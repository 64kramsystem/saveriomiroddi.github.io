---
layout: post
title: Processing key/values tuples in text files with Perl (how to enable unattended upgrades for PPAs)
tags: [linux,perl,shell_scripting,sysadmin,text_processing,ubuntu]
---

In my latest sysadmin experimentations, I've configured the unattended upgrades on my new server (an Odroid H2 😍).

Among the other things, I had to add a PPA to the list of allowed origins to automatically upgrade. This required some interesting text processing, so I decided to dig into Perl's text processing functionalities.

This post describes how to enable unattended upgrades for a PPA, while explaining several useful Perl features, in particular, how to process key/value tuples; a few regular expression functionalities are also used.

Contents:

- [A high level overview of how to enable unattended upgrades for a PPA](/Processing-key-values-tuples-in-text-files-with-perl#a-high-level-overview-of-how-to-enable-unattended-upgrades-for-a-ppa)
- [Premises, and structuring the procedure](/Processing-key-values-tuples-in-text-files-with-perl#premises-and-structuring-the-procedure)
  - [Capturing groups](/Processing-key-values-tuples-in-text-files-with-perl#capturing-groups)
  - [Processing the input text as a single string](/Processing-key-values-tuples-in-text-files-with-perl#processing-the-input-text-as-a-single-string)
    - [The "multiple lines" match operator modifier (`m`)](/Processing-key-values-tuples-in-text-files-with-perl#the-multiple-lines-match-operator-modifier-m)
  - [The "global" match operator modifier (`g`)](/Processing-key-values-tuples-in-text-files-with-perl#the-global-match-operator-modifier-g)
  - [The join() function](/Processing-key-values-tuples-in-text-files-with-perl#the-join-function)
  - [Adding a line to an input, after a match](/Processing-key-values-tuples-in-text-files-with-perl#adding-a-line-to-an-input-after-a-match)
- [The final commands](/Processing-key-values-tuples-in-text-files-with-perl#the-final-commands)
- [Conclusion](/Processing-key-values-tuples-in-text-files-with-perl#conclusion)

## A high level overview of how to enable unattended upgrades for a PPA

The `unattended-upgrades` package is installed by default on Ubuntu Server installations, and takes care of upgrading the system, according to its configuration.

Not everything in the system is upgraded: only the configured origins, which are specified in the configuration file `/etc/apt/apt.conf.d/50unattended-upgrades`:

```
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
//      [other entries...]
};
```

Let's say we have the Libreoffice PPA installed (`ppa:libreoffice/ppa`); in order to find the corresponding origin, we need to dig into the apt state information files.

Each repository has a few files located under `/var/lib/apt/lists/`, with the relevant file ending with `_InRelease`. In this case, the target is `ppa.launchpad.net_libreoffice_ppa_ubuntu_dists_bionic_InRelease`, which contains the following data:

```
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

Origin: LP-PPA-libreoffice
Label: LibreOffice Fresh
Suite: bionic
Version: 18.04
[other data...]
```

now we pick the `Origin` and `Suite` values, and add them to the `unattended-upgrades` configuration file:

```
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
        "LP-PPA-libreoffice:bionic";
//      [other entries...]
};
```

pretty simple. Now let's automate it.

## Premises, and structuring the procedure

The user needs to be aware of the difference of the two execution modes:

- `-n`: doesn't automatically print any output; the user must invoke `print`
- `-p`: in short, prints automatically the output

I'm also assuming some other concepts, whose explanations can be found in my previous [perl-related posts](/tag/perl) (and other tags).

### Capturing groups

First, let's start with regular expressions. We want to print the values corresponding to the keys `Origin` and `Suite`. Typically, we would just use the awk-style approach:

```sh
$ perl -lane 'print $F[1] if $F[0] =~ /^(Origin|Suite):/' /var/lib/apt/lists/ppa.launchpad.net_libreoffice_ppa_ubuntu_dists_bionic_InRelease
LP-PPA-libreoffice
bionic
```

however, for reasons explained later, we need to use capturing groups instead:

```sh
perl -lne 'print $1 if /^(?:Origin|Suite): (.*)/' /var/lib/apt/lists/ppa.launchpad.net_libreoffice_ppa_ubuntu_dists_bionic_InRelease
```

The notable concept here is the non-capturing group (`(?:Origin|Suite)`): it expresses a condition (`Origin` *or* `Suite`) that needs to match, but whose matching text is not captured; the second, regular, capturing group (`(.*)`) instead captures the text.

Since we have only one capturing group (the second), the corresponding variable is `$1`.

### Processing the input text as a single string

Text processing programs work, by default, by cycling on lines, and applying the specified operations on each line; therefore, we have a problem here: we can't process values on different lines.

In order to introduce the next concepts, we'll work temporarily on text replacement rather than match. The operator for replacing text is `s/<expr>/<expr>/`, very similar to the match (`/<expr>/`).

Let's suppose we have the input:

```
Key1: Value1
Key2: Val\
ue2
Key3: Value3
```

and we want to remove the tuple 2, which spans two lines. 

Perl can operate on the input text as a single string, using the (strange) option `-0777`, so we can easily execute:

```sh
$ perl -0777 -pe 's/Key2: Val\\\nue2\n//' <<'INPUT'
Key1: Value1
Key2: Val\
ue2
Key3: Value3
INPUT

Key1: Value1
Key3: Value3
```

There you go!

#### The "multiple lines" match operator modifier (`m`)

When working on a single string input, an interesting problem arises: what will the beginning/end of string metacharacters (`^`/`$`) refer to?

Let's see:

```sh
$ perl -0777 -pe 's/^Key1: Value1$//' <<INPUT
Key1: Value1
AltKey1: AltValue1
Key2: Value2
INPUT

Key1: Value1
AltKey1: AltValue1
Key2: Value2
```

It didn't work! The reason is that the `^`/`$` metacharacters refer to the beginning/end of the string. When we operate on a single string input, they will match the beginning/end of the entire input.

In order to apply the per-line behavior, we use the `m` match operator modifier:

```sh
$ perl -0777 -pe 's/^Key1: Value1$//m' <<INPUT
Key1: Value1
AltKey1: AltValue1
Key2: Value2
INPUT

AltKey1: AltValue1
Key2: Value2
```

now this worked as expected.

### The "global" match operator modifier (`g`)

This is straightforward: by default, substitution (and match) applies only once per processed string. If we want to replace multiple occurrences, we use the `g` modifier:

```sh
$ perl -pe 's/Vallue/Value/g' <<INPUT
Key1: Vallue1a Vallue1b
Key2: Value2
INPUT

Key1: Value1a Value1b
Key2: Value2
```

the same principle works for single-string input (`-0777`) mode.

### The join() function

The `join()` function is a standard tool in scripting languages; it takes a list and a string, and concatenates the entries of the former using the latter. In Perl, it has the signature:

```
join(<concatenator>, <list>)
```

We're going to produce the list using the match operator; since the purpose of `join()` is to concatenate multiple entries, we need to apply the `g` modifier to the match operator, otherwise, the match only returns one element.

Silly example; let's print the ingredients of a menu:

```sh
$ perl -0777 -ne 'print join(",", /[: ](\w+)/g)' <<INPUT
Pizza: flour mozzarella sauce
Pasta: pasta pesto
INPUT

flour,mozzarella,sauce,pasta,pesto
```

note that, simplicity's sake, we consider ingredients anything that is preceded by a space or a colon (`[: ]`).

### Adding a line to an input, after a match

There are many cases of additions to an input; in this case, we want to add a line after another line that matches a pattern.

Let's say we want to add an `A2` after `A` in the following example:

```
A
B
```

to:

```
A
A2
B
```

In Perl, this is simple, although not very readable. We simply use the variable containing the current line (`$_`) and concatenate (`.=`) the specified text:

```sh
$ perl -pe '$_ .= "A2\n" if /A/' <<INPUT
A
B
INPUT

A
A2
B
```

Easy!

## The final commands

Let's review the inputs:

```
# 
Origin: LP-PPA-libreoffice
Label: LibreOffice Fresh
Suite: bionic

Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
```

the series of logical steps to apply:

1. for the entire input, in a single string form,
1. find all the lines...
1. ...starting with `Origin` or `Suite`
1. for those lines, capture the value string after the key
1. join all the captured strings using a colon (`:`)
1. finally, insert the result in the apt info file

and the translation to the corresponding Perl concepts:

1. `-0777`
1. `/.../g`
1. `/^(Origin|Suite)/m`
1. `/(?:...): (.*)/`
1. `join(":", <tokens>)`
1. `$_ .= "<new_line>\n" if /<match_line>/`

Let's put it together:

```sh
$ APT_INFO_FILE="/var/lib/apt/lists/ppa.launchpad.net_libreoffice_ppa_ubuntu_dists_bionic_InRelease"
$ UNATTENDED_UPGRADES_FILE="/etc/apt/apt.conf.d/50unattended-upgrades"

$ export LIBREOFFICE_ORIGIN="$(perl -0777 -ne 'print join(":", /^(?:Origin|Suite): (.*)/mg)' $APT_INFO_FILE)"

$ echo $LIBREOFFICE_ORIGIN
LP-PPA-libreoffice:bionic

$ perl -i -pe '$_ .= "        \"$ENV{LIBREOFFICE_ORIGIN}\";\n" if /^Unattended-Upgrade::Allowed-Origins/' $UNATTENDED_UPGRADES_FILE

$ cat /etc/apt/apt.conf.d/50unattended-upgrades
[...]
Unattended-Upgrade::Allowed-Origins {
        "LP-PPA-libreoffice:bionic";
        "${distro_id}:${distro_codename}";
[...]
```

Done!

## Conclusion

In this article we've put together many different concepts, in order to automate a text processing task.

Although the task is simple, reviewing the concepts involved, and adding a few new ones, is a very useful exercise. While in real world cases, it can be hard to quickly come up with a script, exercising for the sake of exercising has two effects:

1. it raises the complexity lower bound of problems that can be handled immediately (e.g., for sysadmins, ability to process logs);
2. it also raises the upper bound of those that require more effort (e.g., for devops, tooling).

This effectively increase the engineering skills.
