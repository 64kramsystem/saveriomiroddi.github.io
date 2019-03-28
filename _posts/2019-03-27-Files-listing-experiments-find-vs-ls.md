---
layout: post
title: Files listing experiments&#58; &#96;find&#96; vs. &#96;ls&#96;
tags: [shell_scripting,linux]
---

I wanted to tweak a script of mine; it included the conventional `find </path> -maxdepth 1 -type f`. I wasn't fully convinced it was the best choice, so I checked out what's the `ls` equivalent.

This post is about the research I've done; as usual, it's an exercise in extensive usage of the available tools.

Contents:

- [Introduction to the problem, and the `find` tool](/Files-listing-experiments-find-vs-ls#introduction-to-the-problem-and-the-find-tool)
- [Exploring `ls`](/Files-listing-experiments-find-vs-ls#exploring-ls)
- [Conclusion](/Files-listing-experiments-find-vs-ls#conclusion)

## Introduction to the problem, and the `find` tool

Let's say we want to copy all the files from a directory, without descending into the subdirectories, while processing the filenames.  
An extra requirement is that we need to perform this operation from an arbitrary location (therefore, we need full paths).

For simplicity, we use files without spaces/wildcards; for covering those cases, [sophisticated handling](https://unix.stackexchange.com/a/9499) is required.

Full directory structure of the example:

```sh
$ find /tmp/source -mindepth 1
/tmp/source/dir_d
/tmp/source/dir_d/file_f.src
/tmp/source/.file_c.src
/tmp/source/file_a.src
/tmp/source/file_b.src
```

Note how we skip the parent directory `/tmp/source`, via `-mindepth 1`.

We can perform the operation via an interesting `find` usage:

```sh
find /tmp/source -maxdepth 1 -type f -exec sh -c '
  cp $0 /tmp/dest/$(basename ${0%.src})
' {} \;
```

the functionalities used are:

- `-maxdepth 1`: don't descend into subdirectories
- `-type f`: only files
- `-exec`: exec the given command for each cycle; `sh -c` executes a command in a dash (sub)shell;
    the general `-exec` format is `-exec <command> {} \;`, where `{}` is the filename placeholder
- `basename <filename>`: linux tool for printing the basename of a file; the corresponding bash string function is `${<variable>##*/}`
- `${<variable>%<suffix>}`: bash string function for printing `<variable>` with `<suffix>` removed (in this case, the extension)

The clever part of this pattern is that `-exec` passes the filename via placeholder `{}` to the `sh` subshell, so that the latter can use it as parameter (`$0`).

We could in theory put the placeholder inside the command, in the form:

```sh
find /tmp/source -maxdepth 1 -type f -exec sh -c '
  echo {}
' \;
```

but this way, we couldn't use bash string manipulation functions, which need a variable.

## Exploring `ls`

Let's explore, instead, what `ls` provides.

First, let's start with a simple `ls -1`:

```sh
$ ls -1 /tmp/source
dir_d
file_a.src
file_b.src
```

This won't work: we need the full path for executing the command from an arbitrary location; additionally, the hidden file is missing.

We try using a wildcard:

```sh
$ ls -1 /tmp/source/*
/tmp/source/file_a.src
/tmp/source/file_b.src

/tmp/source/dir_d:
file_f.src
```

Now we have the full path: when `ls -1` receives full paths as parameters, it also prints the files with a full path (like `find`).

We still don't have the hidden file in the list, and following this path, `-a` won't work, since the wildcard explicitly selects the files to be listed, and filters out the hidden ones (more on this later).

Let's avoid descending into the subdirectory, using `-d`:

```sh
$ ls -1d /tmp/source/*
/tmp/source/dir_d
/tmp/source/file_a.src
/tmp/source/file_b.src
```

We need to exclude directories (like `find -type f`); we can achieve this via `-p` and complementing with `grep`:

```sh
$ ls -1dp /tmp/source/*
/tmp/source/dir_d/
/tmp/source/file_a.src
/tmp/source/file_b.src

$ ls -1dp /tmp/source/* | grep -v '/$'
/tmp/source/file_a.src
/tmp/source/file_b.src
```

The standard `grep` supports basic regex metacharacters (`$` = end of the line), so we don't need to specify options for advanced regular expressions support (`-E` or `-P`).

The hidden file is missing! Let's use an interesting bash feature - brace expansion:

```sh
$ ls -1dp /tmp/source/{,.}* | grep -v '/$'
/tmp/source/file_a.src
/tmp/source/file_b.src
/tmp/source/.file_c.src
```

the brace splits the braces content with comma, then expands the token using the containing string.  
In this case, the tokens are an empty string (between `{` and `,`) and `.`, resulting in respectively `/tmp/source/*` and `/tmp/source/.*`:

```sh
$ ls -1dp /tmp/source/* /tmp/source/.* | grep -v '/$'
/tmp/source/file_a.src
/tmp/source/file_b.src
/tmp/source/.file_c.src
```

There is an unfortunate side effects to this expression. If there are no hidden files, the statement (expanded, for clarity) will print an error:

```sh
$ ls -1dp /tmp/source/* /tmp/source/.* | grep -v '/$'
ls: cannot access '/tmp/source/.*': No such file or directory
/tmp/source/file_a.src
/tmp/source/file_b.src
# we assume .file_c.src is not present
```

Shame. If we want the command to allows hidden files to be optional (and/or non-hidden), we need to filter out `stderr`:

```sh
$ ls -1dp /tmp/source/{,.}* 2> /dev/null | grep -v '/$'
/tmp/source/file_a.src
/tmp/source/file_b.src
# we assume .file_c.src is not present
```

we accomplish this via sending stderr to /dev/null (`2> /dev/null`).

We can finally write the cycle as:

```sh
for f in $(ls -1dp /tmp/source/{,.}* 2> /dev/null | grep -v '/$'); do
  cp $f /tmp/dest/$(basename ${f%.src})
done
```

## Conclusion

The experiment failed, quite miserably: using `find` is significantly cleaner.

However, we've discovered interesting `ls` options, and dusted the `find` functionalities.
