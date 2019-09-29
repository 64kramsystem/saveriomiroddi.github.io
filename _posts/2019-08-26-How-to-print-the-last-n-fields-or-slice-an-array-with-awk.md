---
layout: post
title: How to print the last N fields (or slice an array) with awk
tags: [awk,perl,shell_scripting,text_processing]
last_modified_at: 2019-09-09 13:22:00
---

A functionality that I require, relatively frequently, when scripting, is to print the last N fields of a stream, with awk.

A typical example, is to copy part of the commits of a git `cherry`/`log` command:

```
+ 81061edd2023c399539f1ff5cfdc267fd41c5c43 Ruby GUI development article: add `Some references` section
+ 5c60b7ef357683137b5f772f8590ab7d12c8e218 Ruby GUI development article: add `Footnotes` section
+ b6fe3469bc2ae59a7eba629c16ab11c67b7fbcbf Ruby GUI development article: add note about browser-based toolkits
[...]
```

This post explains how to do it, with some extra goodies.

Contents:

- [Reformulating the approach](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#reformulating-the-approach)
- [The pieces](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#the-pieces)
  - [Automatically printing the newline (in Perl 5.x)](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#automatically-printing-the-newline-in-perl-5x)
  - [Autosplit](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#autosplit)
  - [Slicing an array](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#slicing-an-array)
  - [Send the stdout of a process to the global clipboard](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#send-the-stdout-of-a-process-to-the-global-clipboard)
- [Putting everything together](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#putting-everything-together)
- [Conclusion](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#conclusion)
- [Footnotes](/How-to-print-the-last-n-fields-or-slice-an-array-with-awk#footnotes)

## Reformulating the approach

So, how does one print the last N fields with awk? The answer is simple: one doesn't.

I'll reformulate the question, instead: "what's the most convenient way to print the last N fields of a stream?".

Awk's solution is inelegant: since there's no support to slice an array, one has to cycle the field variables (or blank the unwanted fields).

So, let's explore what Perl provides.

## The pieces

### Automatically printing the newline (in Perl 5.x)

Having to add `\n` at the end of each string `print`ed is very nasty business. Fortunately, Perl has a functionality that helps (see the [documentation](https://www.perl.com/pub/2004/08/09/commandline.html/#Record_Separators)):

```sh
$ perl --help | grep terminator
  -l[octal]         enable line ending processing, specifies line terminator
```

Without a parameter (and when specified with `-n`/`-p`), this option chomps the input and automatically adds `\n` to the `print` invocations:

```sh
$ print "operation1: log content 1\noperation2: log content 2" | perl -l -ne 'print /: (.*)/'
log content 1
log content 2
```

Here's an extra goodie: in Perl, print a regular expression capturing groups, will print the capturing groups - in this case, `print /: (.*)/` will print anything after `: `.

... and we don't need any newline 😉

Note that in Perl 6, the `say` command does this without using any option.

### Autosplit

Perl actually has a functionality to automatically split an input (into the `@F` variable), which matches (in the base form) awk's field variables:

```sh
$ perl --help | grep autosplit
  -a                autosplit mode with -n or -p (splits $_ into @F)

$ echo 'this is the input' | perl -l -a -ne 'print @F[3]'
input
```

Note how, differently from awk, `@F` is 0-indexed.

### Slicing an array

Slicing an array in Perl is very familiar for those working with scripting languages (Ruby, Python...), with the only nag being that [in this context[¹](#footnote01)] we can't reference the last field as `-1`; we just use the array length operator (`$#`) and we're done:

```sh
$ echo 'this is the input' | perl -lane 'print "@F[2..$#F]"'
the input
```

### Send the stdout of a process to the global clipboard

This is unrelated to Perl, but very useful: in Linux, one can use the `xsel` program (on Debian/Ubuntu, just install the package with the same name) to copy the stdout of a process to the clipboard:

```sh
$ xsel --help | grep -P '-[ib]'
  -i, --input           Read standard input into the selection
  -o, --output          Write the selection to standard output

$ echo 'this goes to the clipboard' | xsel -ibo
# nothing in the output! goes to the clipboard
```

## Putting everything together

Let's suppose we're on a git branch. We want to create a bullet list of the commits contained in the branch [but not in master], and copy it to the clipboard, so that we can paste it on a PR (😉).

This is the output, when executing from the branch:

```sh
$ git cherry -v master
+ 81061edd2023c399539f1ff5cfdc267fd41c5c43 Ruby GUI development article: add `Some references` section
+ 5c60b7ef357683137b5f772f8590ab7d12c8e218 Ruby GUI development article: add `Footnotes` section
+ b6fe3469bc2ae59a7eba629c16ab11c67b7fbcbf Ruby GUI development article: add note about browser-based toolkits
+ 71a9752e7ec3d6bd59bcf342faa8ee974596e238 Ruby GUI development article: add status to (and reorder) main table; use ruby names, not libraries
+ 25f3827acc3c798075e21d003c4b73ddf8256237 Ruby GUI development article: reorder some entries
+ 743a3df39168380cda51e873121262fc54266708 Ruby GUI development article: add a subsection for unassessed libraries (added Ruby-QML)
```

Now, let's use all the tools/functionalities gathered until now:

```sh
$ git cherry -v master | perl -lane 'print "- @F[6..$#F]"' | xsel -io
```

and lo and behold, this is going to be the content of the clipboard:

```
- add `Some references` section
- add `Footnotes` section
- add note about browser-based toolkits
- add status to (and reorder) main table; use ruby names, not libraries
- reorder some entries
- add a subsection for unassessed libraries (added Ruby-QML)
```

## Conclusion

As an engineer, I'm not really concerned with what I use, rather, with what's the best[²](#footnote02) approach to a given job; in this case, I require compactness, as long as readability is sacrificed, at most, only a little.

Personally, I consider consolidating as many use cases/requirements as possible into a single tool/service, a significant engineering principle. In this area, I found Perl a very successful tool.

Enjoy effective and efficient text processing!

## Footnotes

<a name="footnote01">¹</a>: `-1` actually addresses the last field, but only when the first parameter in the range is also negative, e.g. `[-3..-1]`.<br/>
<a name="footnote02">²</a>: "Best" of course, has a different meaning based on the context.<br/>
