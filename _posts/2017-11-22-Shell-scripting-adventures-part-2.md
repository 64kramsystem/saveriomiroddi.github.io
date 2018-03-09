---
layout: post
title: Shell scripting adventures (Part 2, Text processing extravaganza)
tags: [shell_scripting,sysadmin,text_processing,perl,awk]
last_modified_at: 2018-03-09 18:15:00
---

This is the Part 2 (of 3) of the shell scripting adventures.

The following subjects are described in this part:

- [Awk/sed/perl considerations](/Shell-scripting-adventures-part-2#awksedperl-considerations)
- [Perl text processing](/Shell-scripting-adventures-part-2#perl-text-processing)
  - [Regex modifiers](/Shell-scripting-adventures-part-2#regex-modifiers)
  - [Replace multiple lines](/Shell-scripting-adventures-part-2#replace-multiple-lines)
    - [`m` modifier](/Shell-scripting-adventures-part-2#m-modifier)
    - [`s` modifier](/Shell-scripting-adventures-part-2#s-modifier)
  - [Isolating ambiguous group references](/Shell-scripting-adventures-part-2#isolating-ambiguous-group-references)
  - [Printing a matching group (of matching lines)](/Shell-scripting-adventures-part-2#printing-a-matching-group-of-matching-lines)
- [Awk text processing](/Shell-scripting-adventures-part-2#awk-text-processing)
- [Progress bars processing with awk (and stdbuf)](/Shell-scripting-adventures-part-2#progress-bars-processing-with-awk-and-stdbuf)
  - [Processing single-line progress outputs](/Shell-scripting-adventures-part-2#processing-single-line-progress-outputs)
  - [Working around the buffering](/Shell-scripting-adventures-part-2#working-around-the-buffering)
  - [Streams processing](/Shell-scripting-adventures-part-2#streams-processing)
  - [Putting things together](/Shell-scripting-adventures-part-2#putting-things-together)

The examples are taken from my [RPi VPN Router project installation script](https://github.com/saveriomiroddi/rpi_vpn_router/blob/master/install_vpn_router.sh).

Previous/following chapters:

- [Introduction]({% post_url 2017-11-02-Shell-scripting-adventures-introduction %})
- [Part 1]({% post_url 2017-11-08-Shell-scripting-adventures-part-1 %})
- [Part 3]({% post_url 2017-12-23-Shell-scripting-adventures-part-3 %})

## Awk/sed/perl considerations

Awk, sed and perl are very common utilities for text processing.

I personally don't like to use many tools for doing similar jobs (at least, basic jobs), so my personal choice is to use each of them with very specific patterns.

There are two important things to consider:

1. perl (or other scripting languages) can do everything the other two do, although not with the same compactness;
2. compactness is not a constructive goal (to say the least); the perspective to look at the following examples is to think of them, and know them, as patterns - of course, (relatively) advanced text processing patterns.

I will expose here the ones that I find generally useful.

## Perl text processing

These are the most commonly used perl patterns for text processing:

```sh
echo mytext | perl -pe 's/<search>/<replace/<modifiers>'
perl -i -pe 's/<search>/<replace/<modifiers>' file1 [file2...]
```

`-pe` is composed of two common parameters (in scripting languages, e.g. Ruby):

- `-p`: for each line of the input, executes the script, and prints the processed line
- `-e`: executes the script provided as argument (opposed to executing the code in a file)

An alternative to `-p` is `-n`, which cycles without printing. This is also explored in a subsequent section.

`-i` will modify files in-place, as seen in the second form.

Everybody loves regexes ;-), so I'll skip them, and focus on a few interesting concepts.

### Regex modifiers

Modifiers will change the way the search and replace act.

The most common is `g`, which is *very important*: it will perform multiple replacements per iterated line - the default is to replace only once.

The other two modifiers discussed in the next sections are `s` and `m`.

### Replace multiple lines

This is something I kept forgetting (and other people, apparently, too) - this typically causes hairpulling because the first intuition is that something's wrong in the regex.

In order to replace multiple line text, one must specify "slurping" the text, that is, to process it as a single string:

```sh
$ echo "first_line,A
> second_line,A
> third_line,B" | perl -0777 -pe 's/A\n/Z\n/g'
first_line,Z
second_line,Z
third_line,B
```

The cryptic `-0777` will allow us to match multiple lines; don't forget the `g` modifier, for matching both instances!

#### `m` modifier

A crucial concept to keep in mind when slurping is the start/end of line modifier `m`.
`m` is needed for matching start/end of lines with `^`/`$`, otherwise, they'll match the start/end of the file!

```sh
$ echo "first_line,A
> second_line,A" | perl -0777 -pe 's/A$/Z/g'
first_line,A
second_line,Z
```

If we want to match `A`s at the end of line, we need to use the `m` modifier:

```sh
$ echo "first_line,A
> second_line,A" | perl -0777 -pe 's/A$/Z/gm'
first_line,Z
second_line,Z
```

#### `s` modifier

The other concepts to bear in mind is that Perl won't match newlines with the regex symbol `.`. In order to do that, we need the `s` modifier:

```sh
$ echo "first_line,A
> second_line,A" | perl -0777 -pe 's/A./A\n\n/'
first_line,A
second_line,A
```

Nothing chnaged!

Using the modifier:

```sh
$ echo "first_line,A
> second_line,A" | perl -0777 -pe 's/A./A\n\n/s'
first_line,

second_line,A
```

Oh yeah!

### Isolating ambiguous group references

Sometimes a group reference is ambiguous:

```sh
$ echo 'I love commodore 6' | perl -pe 's/(6)/$14/'
I love commodore
```

Wrong! This happens because Perl interprets `$14` as 14th group, rather than `$1` followed by a `4` character.

In order to make the reference unambiguous, we use curly braces:

```sh
$ echo 'I love commodore 6' | perl -pe 's/(6)/${1}4/'
I love commodore 64
```

### Printing a matching group (of matching lines)

This is really cool, and very common.

Sometimes we want to print only a part of a matching expression/line. For example, from this text:

```
I love pizza
I love Commodore 64
I dislike seafood
```

we want to:

1. filter the lines with the things that I love
2. print only the things that I love, without "I love"

```sh
$ echo "I love pizza
> I love Commodore 64
> I dislike seafood" | perl -ne 'print "$1\n" if /I love (.*?)/'
pizza
Commodore 64
```

The Perl statements are evident for programmers; the notable detail is the usage of `-ne` instead of `-pe`.

The difference is that `-n` won't automatically print the output of the statement; in this case in fact, it's easier to extract the group, and manually print it, rather than performing a complex replacement.

For more information about `-n` and `-p`, see [this page](https://www.perl.com/pub/2004/08/09/commandline.html).

## Awk text processing

Awk's most common usage is to print single tokens of a line:

```sh
$ echo A BC DEF | awk '{print $2}'
BC

$ echo A BC DEF | awk '{print $NF}'         # print the last token
DEF

$ echo A BC DEF | awk '{print $1 "/" $2 }'  # print other strings
A/BC
```

We can specify other delimiters:

```sh
$ echo A:BC:DEF | awk -F: '{print $2}'
BC
```

We can also perform (printf-style) formatting and operations:

```sh

$ echo "100
> 200" | awk '{printf "%i\n", $1 / 4}'
25
50
```

This is the awk way of printing a token of matching lines:

```sh
$ echo "I love pizza
> I love Commodore64
> I dislike seafood" | awk '/love/ {print $3}'
pizza
Commodore 64
```

Note that, while more compact than Perl, we can't print a capturing group (in fact, we use a single word for `Commodore64`).

## Progress bars processing with awk (and stdbuf)

Sometimes, we want to process progress bars. Although this may seem masochistic, there is actually a legitimate case, and it's to process the output to send it to a separate program for displaying in a different way.

Suppose you want to display the `dd` progress in a nice window.

The `whiptail` program can display fancy [for terminal people] text windows; with a certain configuration, it takes numbers in stdin, representing the percentage of completion.  
For simplicity, in this section we just perform the text processing, so that we transform the `dd` output into a sequence of progress numbers.

This is a sample of dd progress:

```sh
$ dd if=/dev/zero status=progress of=/dev/null
3573420032 bytes (3,6 GB, 3,3 GiB) copied, 2 s, 1,8 GB/s
```

There are a few problems to know:

1. `dd` displays the progress on a single line, by cyclically overwriting the existing text; since it never prints a new line, how do we capture each individual cycle output?
2. *severe hair pulling warning:* pipe streams are buffered; single characters will **not** be piped until a certain amount is pushed (or the EOF is reached)
3. how to process the streams, and which ones?

### Processing single-line progress outputs

First, we need to detail the problem.

From a technfical perspective, single-line progress outputs are accomplished by using the "carriage return character" (`\r`), which returns to the beginning of the line.

So, now we know what to do: to tell awk to process the string received once it gets a `\r` (rather than waiting for a newline (`n`)).

Regarding the how, the record separator variable comes to the rescue.

In awk, the record separator is represented by the variable `RS`; we set it using the `-v` option:

```sh
$ awk -v RS='\r' '<mycommand>'
```

### Working around the buffering

For the pipe buffering problem, we use a tool called `stdbuf`:

```sh
$ program_with_tiny_outputs | stdbuf -o0 text_processing_program
```

The `-o0` simply tells to adjust the output to use a 0 bytes buffer, that is, no buffering.

### Streams processing

`dd` will use two streams:

- `stdout`, for sending the data
- `stderr`, for displaying the progress

Text processing programs receive data in their `stdin` from the outputting program's `stdout`.

So we need to find how to:

- take the `dd` `stdout` output and direct it to a file
- take the `dd` `stderr` output, convert it to a `stdout`
- send the last `stdout` mentioned to the `stdin` of `awk`

This is the pattern:

```sh
$ (dd status=progress if=/dev/zero bs=1G count=100 > /dev/null) 2>&1 | awk '<mycommand>'
```

The crux is `2>&1`. What this does is to redirect `stderr` (stream 2) to `stdout` (stream 1).

Now, the question is, won't we mix `dd`'s stdout and stderr into stdout?

Nope! This is because from this group:

```sh
(dd status=progress if=/dev/zero bs=1G count=100 > /dev/null)
```

there is not `stdout` output, because it's sent to `/dev/null`.

### Putting things together

Although the statement looks ugly, it makes sense with the understanding of the above concepts:

```sh
$ (dd status=progress if=/dev/zero bs=1GB count=100 > /dev/null) 2>&1 | \
> stdbuf -o0 awk -v RS='\r' '/copied/ { printf "%i\n", $1 / 1000000000 }'
10
22
35
47
59
71
83
96
```

The only minor additional detail is that we need to filter in the lines including 'copied'; `dd` also output other ones, which we want to discard.
