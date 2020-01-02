---
layout: post
title: Working with dates and number in Bash (and other goodies)
tags: [linux,shell_scripting,awk,perl,text_processing]
---

Every month, I purge the files trashed more than one month before.

Since it's been scientifically proven that manual operations cause PTSD in system administrators, I've made a script.

In this small article, I'll explain some concepts involved, most notably, working with dates and numbers in Bash, and some other scripting-related concepts.

Contents:

- [The base structure](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#the-base-structure)
  - [Writing safer Bash scripts](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#writing-safer-bash-scripts)
    - [`errexit`](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#errexit)
    - [`nounset`, with pattern](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#nounset-with-pattern)
    - [`pipefail`](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#pipefail)
      - [`pipefail` versus `grep -q`](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#pipefail-versus-grep--q)
  - [First step: Handling dates, cycling the data](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#first-step-handling-dates-cycling-the-data)
  - [Splitting a string via Perl](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#splitting-a-string-via-perl)
  - [Splitting a string via `cut`](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#splitting-a-string-via-cut)
  - [Dates, arithmetic, and putting all together](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#dates-arithmetic-and-putting-all-together)
- [Conclusion](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#conclusion)
- [Footnotes](/Working-with-dates-and-numbers-in-Bash-and-other-goodies#footnotes)

## The base structure

The [`purge_trash`](https://github.com/saveriomiroddi/openscripts/blob/master/purge_trash) script is pretty simple:

- it lists the content of the trash (via `trash-list`);
- it extracts the timestamp of each file;
- if the trashing timestamp is before the threshold, it purges the file (via `trash-rm <filename>`).

Readers can check the source; here, I'll explain the most interesting parts.

### Writing safer Bash scripts

Bash provides a set of options, some of whom make scripts more solid, and that should always be used.

The extended syntax for setting an option is `set -o <extended_option_name>`. Generally, one puts all the options setting at the top of the file.

The next sections will explain the relevant options.

#### `errexit`

The option `errexit` causes the script to terminate when there is an error.

Bash, by default, uses a `On Error Resume Next` approach (RIP Visual Basic 6 😉), so setting this option is a no-brainer.

However, this requires some cases to be handled - some commands exit with error codes during the normal workflow, `grep` being one of the most common.

There is an exception to this behavior: expressions of `if` conditionals will not cause the script to terminate. In other words, in a script like:

```sh
if <command_that_fails>; then
  echo "Extensive error message!"
  exit 1
fi
```

The "Extensive error message!" will be printed; Bash will not terminate after executing `<command_that_fails>`.

A real-world, typical example, is `grep` filtering; a subsection below is dedicated to this.

#### `nounset`, with pattern

The option `nounset` treats as an error referencing a variable that hasn't been initialized.

The most common logic that needs some treatment when this option is set, is user parameters handling.

Let's suppose we write a script with the following definition: `myscript [<optional_parameter>]`, which can translate to:

```sh
set -o nounset

if [[ "$1" == "value_1" ]]; then
  # ...
fi
```

If the user invokes `myscript` without the parameter, the script will blow up, because `$1` hasn't been initialized!

The Bash functionality handling this case is a form of [parameter expansion](https://wiki.bash-hackers.org/syntax/pe); the syntax is `${<variable_name>:-<value>}`.

If we want to default to an empty string, we can omit `<value>`; therefore, the `myscript` specific code will be:

```sh
set -o nounset

if [[ "${1:-}" == "value_1" ]]; then
  # ...
fi
```

This won't fail.

Note that this expansion considers uninitialized variables and empty strings the same; see:

```sh
$ myvar=
$ myvar=${myvar:-myvalue}
$ echo $myvar
myvalue
```

#### `pipefail`

The option `pipefail` treats as an error a pipeline (a sequence of commands chained via pipe (`|`)) whose any of the commands fails.

By default, Bash considers, in a pipeline, only the exit status of the last command; for example:

```sh
$ bash -c '
set -o errexit

false | echo "pipeline with error"
echo "following command"
'
pipeline with error
following command
```

Let's see what happens with `pipefail` enabled:

```sh
$ bash -c '
set -o errexit
set -o pipefail

false | echo "pipeline with error"
echo "following command"
'
pipeline with error
```

The "following command" is not executed; the script exited.

Note how `set -o errexit` is required; `pipefail` will mark the pipeline as errored, but that alone doesn't imply that an error will cause an exit.

##### `pipefail` versus `grep -q`

A **very** headscratching behavior is `grep -q` causing an exit with error when `pipefail` (with `errexit`) is enabled.

`grep -q` is used when testing some data against a string, without the result to be printed ("--`q`uiet").

Let's suppose we want to test if a package is not installed. In our example, the package `trash-cli` is installed.

The first version could be[¹](#footnote01):

```sh
bash -c '
set -o pipefail

if ! dpkg --get-selections | grep -P "trash-cli\t+install"; then
  echo "Package not installed"
fi
'
trash-cli         install
```

The string `Package not installed` will *not* be printed as expected, however, `trash-cli         install` will - it's the output of the `grep` command.

Therefore, one needs to filter grep's output:

```sh
bash -c '
set -o pipefail

if ! dpkg --get-selections | grep -P "trash-cli\t+install" > /dev/null; then
  echo "Package not installed"
fi
'
```

All good! No more noise.

Now, the problem is that some smartpants (like me 😬) will find out the `-q/--quiet` option in the grep manpages, which supposedly yields the same result:

```sh
bash -c '
set -o pipefail

if ! dpkg --get-selections | grep -qP "trash-cli\t+install"; then
  echo "Package not installed"
fi
'
Package not installed
```

D'oh!!

What happened? [This](https://stackoverflow.com/a/19120674) happened. In simple terms, `grep -q` exits early, causing `dpkg` to raise an error.

For those who really want to use `grep -q` (I recognize the appeal of not using `> /dev/null`), the "here-string" operator (`<<<`) will do the trick:

```sh
bash -c '
set -o pipefail

if ! grep -qP "trash-cli\t+install" <<< "$(dpkg --get-selections)"; then
  echo "Package not installed"
fi
'
```

All good! No more pipe, no more problems, and smartpants are satisfied 😄

### First step: Handling dates, cycling the data

One may occasionally want to process timestamps.

With the aid of the utility `date`, and the Bash arithmetic expansion (`$(( <expression> ))`), we can do this easily.

Let's suppose the input:

```
$ trash-list
2019-12-19 22:06:09 /path/to/test abc.png
2019-12-04 23:16:48 /path/to/xorgxrdp-0.2.11.tar.gz
2019-12-25 00:15:27 /path/to/probe-data.json.bak
2019-12-26 19:13:43 /path/to/subiquity_notes.md
2019-12-04 23:16:48 /path/to/xrdp-0.9.11.tar.gz
2019-12-25 00:31:20 /path/to/issue_subiquity.txt
2019-12-25 20:57:49 /path/to/ubuntu-mate-18.04.3-desktop-amd64.iso
2019-12-25 00:31:20 /path/to/probe-data.json
```

We want to print, say, the files older than 15 days before today (01/01/2010). We also want to sort the output, for good UX 😉

In order to work with timestamps, we need to convert them to integers. Let's see an example:

```sh
$ timestamp=$(echo "2019-12-19 22:06:09 /path/to/test abc.png" | awk '{print $1 " " $2 }') # 2019-12-19 22:06:09
$ echo $(date -d "$timestamp" +"%s")
1576789569
```

There you go. The `awk` command prints the first two tokens (date and time).

Now, let's write a basic cycle, which prints the sorted output:

```sh
$ trash_content=$(trash-list | sort)
$ while IFS= read -r line; do
  echo "$line"
done <<< "$trash_content"
# full list...
```

The `while` expression you see above is a common pattern for iterating data (in this case, the output of `trash-list | sort`) line by line.

The `IFS=` expression disables the built-in field separator, whose effect, in this context, is to preserve leading and trailing whitespace.

The `-r` option of `read` doesn't interpret backslashes in the data (e.g. `\n`).

The two technicalities above are *not* required for this dataset, but I write them here for completeness' sake[²](#footnote02).

Next bit: extracting a filename. We have several options!

### Splitting a string via Perl

We want the tokens from index 2 (base 0) to the last; Awk doesn't have nice syntax for this, so we use Perl (❤️):

```sh
$ echo "2019-12-19 22:06:09 /path/to/test abc.png" | perl -lane 'print "@F[2..$#F]"'
/path/to/test abc.png
```

This reads "print the entries of the array `@F`, from the index 2 to the size of the array", in other words, "read from index 2 to the end"[³](#footnote03).

### Splitting a string via `cut`

We can also use `cut`:

```sh
$ echo "2019-12-19 22:06:09 /path/to/test abc.png" | cut -d ' ' -f 3-
/path/to/test abc.png
```

Read as: use as delimiter space (`-d ' '`), and extract the fields from 3 onwards (`3-`)

Note how `cut` uses a base 1 indexing (therefore, we select from index 3 onwards).

For files with a fixed structure, we can also index by character:

```sh
$ echo "2019-12-19 22:06:09 /path/to/test abc.png" | cut -c 21-
/path/to/test abc.png
```

Read as: index by `c`haracters, from the number 21 onwards (`-c 21-`).

### Dates, arithmetic, and putting all together

The last bit is the arithmetic:

```sh
if (( trash_date_in_seconds < time_now_in_seconds - threshold_seconds )); then
  echo "File before threshold: $filename"
fi
```

The double round brackets denote delimit an arithmetic expression; note how variables don't require the `$`.

If we need to assign the result of an arithmetic expression to a variable, this is the syntax:

```sh
myvar1=12
myvar2=$(( myvar1 + 2 + 3)) # 17
```

Now we can put all together!

```sh
# Result of `trash_content=$(trash-list | sort)`
#
$ trash_content="2019-12-19 22:06:09 /path/to/test abc.png
2019-12-04 23:16:48 /path/to/xorgxrdp-0.2.11.tar.gz
2019-12-25 00:15:27 /path/to/probe-data.json.bak
2019-12-26 19:13:43 /path/to/subiquity_notes.md
2019-12-04 23:16:48 /path/to/xrdp-0.9.11.tar.gz
2019-12-25 00:31:20 /path/to/issue_subiquity.txt
2019-12-25 20:57:49 /path/to/ubuntu-mate-18.04.3-desktop-amd64.iso
2019-12-25 00:31:20 /path/to/probe-data.json"

$ threshold_seconds=$(( 15 * 24 * 60 * 60 ))
$ time_now_in_seconds=1577919970 #  2 Jan 00:06:10 CET 2020

$ while IFS= read -r line || [[ -n "$line" ]]; do
  trashing_timestamp=$(echo "$line" | awk '{print $1 " " $2 }') # 2019-12-19 22:06:09
  trashing_timestamp_in_seconds=$(date -d "$trashing_timestamp" +"%s")

  if (( trashing_timestamp_in_seconds < time_now_in_seconds - threshold_seconds )); then
    filename=$(echo "$line" | perl -lane 'print "@F[2..$#F]"')
    echo "File in threshold: $filename"
  fi
done <<< "$trash_content"
File before threshold: /path/to/xorgxrdp-0.2.11.tar.gz
File before threshold: /path/to/xrdp-0.9.11.tar.gz
```

## Conclusion

Although we've witnessed an ugly quirk (`grep -q`), all the concepts introduced in this article, from Bash functionalities to Unix tools, fit smoothly to produce solid, readable and flexible scripts.

Happy scripting!

## Footnotes

<a name="footnote01">¹</a>: I'm using an inappropriately simplified version of the pattern, for simplicity purposes; see the full script for the exact expression.
<a name="footnote02">²</a>: This is not a rigorous interpretation, but good enough in this context.
<a name="footnote03">³</a>: I've omitted also another technicality, `|| [[ -n "$line" ]]`, which may be excessive in this context.
