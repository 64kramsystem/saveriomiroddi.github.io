---
layout: post
title: Debugging a live/stuck Ruby process with GDB, fully explained, plus many goodies!
tags: [c,debugging,linux,ruby,sysadmin]
---

Debugging a live/stuck Ruby process is a well-known subject.

The way it's generally exposed is simply a series of instructions and their outcome; given the expectation, this is fine of course, however, when I saw that a manual copy/paste operation was required, I decided to... step in (pun intended 😂).

This article adds only a few concepts, operatively speaking, but it clarifies all the concept involved, and employs neat approaches to accomplish the task. I will also employ several goodies available to Linux systems.

Contents:

- [Premises](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#premises)
- [A brief overview of debugging a process, and ptrace](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#a-brief-overview-of-debugging-a-process-and-ptrace)
- [Using pgrep](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#using-pgrep)
- [A brief overview of file descriptors](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#a-brief-overview-of-file-descriptors)
- [Putting together Ruby and GDB (with fancy grep!)](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#putting-together-ruby-and-gdb-with-fancy-grep)
- [Basic GDB usage](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#basic-gdb-usage)
- [The procedure](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#the-procedure)
  - [The procedure, neater!](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#the-procedure-neater)
- [Safety of messing with file descriptors](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#safety-of-messing-with-file-descriptors)
- [Other GDB/Ruby tools](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#other-gdbruby-tools)
  - [Evaluating Ruby statements](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#evaluating-ruby-statements)
  - [An alternative option to redirecting stdout/stderr](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#an-alternative-option-to-redirecting-stdoutstderr)
  - [Other interesting sources](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#other-interesting-sources)
- [Conclusion](/Debugging-a-live-stuck-ruby-process-with-gdb-fully-explained-plus-many-goodies#conclusion)

## Table of contents

## Premises

In the following sections I will use the terms "process" and "program". A process is the executed instance of a program; I use the terms respectively when I refer to the context of in-memory execution as opposite to the static structure of a binary.

Since we'll work from multiple terminals, I'll use the convention `<terminal>:$ <command>`, where `<terminal>` is `ruby`, where Ruby test scripts run, and `<debug>`, where we perform investigations.

Each Ruby script should run until a new one is introduced; all the commands in the debug terminal therefore use the last Ruby script exposed in the article.

The procedure provided in this article is guaranteed to run on Real Operating Systems™, which in turn, is not guaranteed to include systems advertised with people throwing hammers at screens.

## A brief overview of debugging a process, and ptrace

From a systems perspective, debugging a process is a collaboration of two services:

- the operating system debugging API(s), and
- the debugger.

Both are required because the debugging API(s) are very simple. This is an appropriate design because debugging itself requires specialized processing that is not meaningful in the context of a kernel.

The debugging APIs design varies depending on the operating system. Windows and Linux have very different philosophies:

- Windows uses a minimal amount of calls, at the core, to manage the debugging events, and leaving the other functionality, like reading a process' memory, to the standard APIs;
- Linux instead uses a system call, [ptrace](https://en.wikipedia.org/wiki/Ptrace), that has much more functionality, even allowing the manipulation of a process' file descriptors.

This is however, one side of the coin. The debugger, which in Linux is (typically) GDB, has a lot of work to do, as it needs to known how the program is structured, in order to interact with it.

A representative functionality is function call, as there are different so-called [calling conventions](https://en.wikipedia.org/wiki/Calling_convention). Aside the obvious concepts such as the function location, the debugger needs to know how to manage the parameters allocation:

- which parameter is pushed in the stack first? leftmost or rightmost?
- who resets the stack? the function callee or the function?
- are all the parameters pushed in the stack, or are some passed via CPU registers?

Therefore, debuggers need specific support for programs being debugged. GDB supports, among the others, C, C++ and Golang. Note that this does not mean that any other language is not supported; for example, Ruby is written in C, and while we can't invoke Ruby code directly, we can do it indirectly via the internal program functions.

## Using pgrep

When dealing with PIDs, `pgrep` is a convenience replacement to the typical `ps` invocations; in general terms, it avoids having to process the `ps` output.

Our `pgrep` invocation is:

```sh
ruby:$ ruby -e "sleep"

debug:$ pgrep --newest ruby
22127
```

which returns only the PID, so that we can directly use it in scripting.

We use the `--newest` options (short form: `-n`) to select the newest matching processes, in case we have multiple matching processes running (therefore, in the context of this article, we assume that we don't execute other extraneous Ruby processes after launching the target one).

## A brief overview of file descriptors

Operating systems interact with files via file handles, which are the abstract representation of a file (or, more generally, an I/O resource).

In Unix, they're called [file descriptors](https://en.wikipedia.org/wiki/File_descriptor).

If a process, say, writes to a log, there will be a file descriptor open. Let's inspect one:

```sh
ruby:$ ruby -e 'File.open("/tmp/test.log", "w") { sleep }'

debug:$ ls -l /proc/$(pgrep -n ruby)/fd
total 0
lrwx------ 1 myuser myuser 64 Sep 17 09:56 0 -> /dev/pts/5
lrwx------ 1 myuser myuser 64 Sep 17 09:56 1 -> /dev/pts/5
lrwx------ 1 myuser myuser 64 Sep 17 09:56 2 -> /dev/pts/5
lr-x------ 1 myuser myuser 64 Sep 17 09:56 3 -> 'pipe:[188892]'
l-wx------ 1 myuser myuser 64 Sep 17 09:56 4 -> 'pipe:[188892]'
lr-x------ 1 myuser myuser 64 Sep 17 09:56 5 -> 'pipe:[188893]'
lrwx------ 1 myuser myuser 64 Sep 17 09:56 6 -> /dev/pts/5
l-wx------ 1 myuser myuser 64 Sep 17 09:56 7 -> 'pipe:[188893]'
l-wx------ 1 myuser myuser 64 Sep 17 09:56 8 -> /tmp/test.log
```

The descriptors `0`, `1` and `2` are the standard POSIX descriptors for `stdin`, `stdout` and `stderr`; they're symlinked to the current terminal:

```sh
ruby:$ tty
/dev/pts/5
```

Curious readers may try to overwrite the symlinks:

```sh
debug:$ sudo ln -sf /dev/null /proc/$(pgrep -n ruby)/fd/1
ln: failed to create symbolic link '/proc/6179/fd/1': No such file or directory
```

This doesn't work; we'll need GDB/ptrace for that ☺️.

The reverse search - finding which processes use a certain file, is performed via `fuser`:

```sh
debug:$ fuser /tmp/test.log
/tmp/test.log:        6179
```

## Putting together Ruby and GDB (with fancy grep!)

As described in a previous section, we'll use GDB to inspect the Ruby process, and call the Linux system calls and Ruby functions that may help.

The system calls involved are:

> `int open(const char *pathname, int flags);`
> 
> Given a pathname for a file, open() returns a file descriptor [...]
> The file descriptor returned by a successful call will be the lowest-numbered file descriptor not currently open for the process.

and 

> `int close(int fd);`
> 
> Closes a file descriptor [...]

something important to notice is that if a file descriptor is `close`d, a subsequent call to `open` will return that file descriptor. Their application will be explained in the actual debug procedure.

The Ruby C function we'll use is `rb_backtrace()`. For fun, let's find the prototype and the implementation in the Ruby source code:

```sh
debug:$ git clone https://github.com/ruby/ruby.git /tmp/ruby

debug:$ grep -P '\brb_backtrace\(' --include="*.h" -r !$
/tmp/ruby/include/ruby/intern.h:void rb_backtrace(void);

debug:$ grep -Pzo '(?s)void\srb_backtrace\(.+?\n\}' --include="*.c" -r !$
./vm_backtrace.c:void
rb_backtrace(void)
{
    vm_backtrace_print(stderr);
}
```

here we notice that the backtrace is printed to stderr. Readers can follow down the chain out of curiosity.

A few notes about the grep goodies:

- `-P`: use only Real Regular Expressions™ (ie. the `P`erl format);
- `\b`: metachacter for word boundary; in this case, we don't want to match something like `print_rb_backtrace(`;
- `-z`: match multiple lines, by treating the input as a single string joined via null character;
- `-o`: print only the match (otherwise, when using `-z`, the entire file will be printed, because the match unit is the file, not the line);
- `(?s)`: match newlines with the dot (`.`) (see [Perl Compatible Regular Expressions "dotall" option](https://en.wikipedia.org/wiki/Perl_Compatible_Regular_Expressions#Features)).

finally, don't forget to use the non-greedy matcher (`.+?`), otherwise, the match will proceed until the last occurrent of `\n\}`!

## Basic GDB usage

The starting point for a GDB session is to attach to another process:

```sh
ruby:$ ruby -e '1.upto(Float::INFINITY) { |i| $stdout.puts "#{i}. out"; $stderr.puts "#{i}. err"; sleep 2 }'

# short form: `-p <pid>`
debug:$ sudo gdb program $(pgrep -n ruby)
```

which will halt the attached process.

One can continue via `continue` (shortcut: `c`), and halt with Ctrl+C:

```
(gdb) continue
Continuing.
# Ctrl+C pressed
Thread 1 "ruby" received signal SIGINT, Interrupt.
[...]
(gdb)
```

The most basic functionality we can use is probably `print` (shortcut: `p`):

```
(gdb) print "abc"
$1 = "abc"
(gdb) p 2 * 3
$2 = 6
```

something immediately noticeable is that the result is associated with symbols (`$`) with increasing numbers. They are the "convenience variables": for any operation (except when nothing is returned), the result is stored in a new instance, that be subsequently used:

```
(gdb) print $1
$3 = "abc"
```

since `print()` returns the value printed, the latter is assigned to a new convenience variable.

We can run a shell command via the `shell` command:

```
(gdb) shell ls -ld /tmp
drwxrwxrwt 17 root root 32768 Sep 18 10:38 /tmp
```

but the output can't be captured.

Calling functions is one of the most important functionalities:

```
(gdb) call (void) rb_backtrace()

# result, in the ruby terminal:
  from -e:1:in `<main>'
  from -e:1:in `upto'
  from -e:1:in `block in <main>'
  from -e:1:in `sleep'
```

there are two notable things:

1. in some cases we need to specify the function return type; as we've seen in the previous section, `rb_backtrace` has no return value (`void`), so we need to specify it;
1. the backtrace is printed in the ruby terminal! in the following section we'll take care of this 😉

Finally, GDB can execute a command specified from the commandline:

```sh
debug:$ sudo gdb --eval-command="p 123"
$1 = 1
(gdb) p $1
$2 = 1
```

note that the command is executed exactly like if it was by the user, so that the convenience variable is also instantiated, and can be used; this will come useful later.

## The procedure

Now we have all the basics required to perform the procedure.

We've seen how to print the backtrace of a process, however in daemons/background processes `stdout` and `stderr` are typically redirected, for example, to a log file; this implies that if we execute `rb_backtrace()`, it will go somewhere that is not immediately visible.

Therefore, our procedure will be:

1. find out the debug terminal device file;
1. attach to the Ruby process;
1. replace the stdout and stderr descriptors with the debug terminal;
1. have fun!

Let's start the debugging session:

```sh
debug:$ sudo gdb program $(pgrep -n ruby)
```

Now, remembering that:

- `rb_backtrace` prints to stderr;
- the `stderr` file descriptor is 2;
- we use `close()` and `open()` system calls to work with file descriptors, all we need to do is:

```
(gdb) shell tty
/dev/pts/0
(gdb) call close(2)               # close the current stderr file descriptor
$1 = 0
(gdb) call open("/dev/pts/0", 1)  # open a descriptor to the debug terminal, in O_WRONLY mode (1)
```

(note that we `open()` in `O_WRONLY` mode, since no reads are performed from stderr)

aaaand... action!:

```
(gdb) call (void) rb_backtrace()
  from -e:1:in `<main>'
  from -e:1:in `upto'
  from -e:1:in `block in <main>'
  from -e:1:in `sleep'
```

if we now continue:

```
(gdb) c
Continuing.
3. err
4. err
5. err
```

the `$stderr.puts()` call from the Ruby program now goes to the debug terminal, as expected.

If we wanted to redirect also the stdout calls, we just open/close the file descriptor 1.

### The procedure, neater!

The procedure works as expected, however, it requires something horrible: manual copy/paste (of the terminal device file pathname).

How to solve that?

Let's do some shell trickery. We know that:

- we can execute a GDB command on startup, and that the commandline option takes a regular string as value;
- the return value of this command is associated to a convenience variable that we can use in the GDB context;
- we can therefore interpolate the commandline option string in the shell!

So, we turn this:

```sh
debug:$ tty
/dev/pts/0
debug:$ sudo gdb --eval-command="p \"/dev/pts/0\""
$1 = "/dev/pts/0"
(gdb)
```

into this:

```sh
debug:$ sudo gdb --eval-command="p \"$(tty)\""
$1 = "/dev/pts/0"
(gdb)
```

and we can run a fully automatable sequence:

```sh
debug:$ sudo gdb --eval-command="p \"$(tty)\"" program $(pgrep -n ruby)
$1 = "/dev/pts/0"
(gdb) call close(2)
$2 = 0
(gdb) call open($1, 1)
$3 = 2
(gdb) call (void) rb_backtrace()
  from -e:1:in `<main>'
  from -e:1:in `upto'
  from -e:1:in `block in <main>'
  from -e:1:in `sleep'
```

## Safety of messing with file descriptors

While the procedure works fine, it's important to highlight that messing with file descriptors is **not** a safe operation. There are 4⁸ possible things that can go wrong, the simplest example being a buffer not flushed (a more extended discussion can be found on [Stack overflow](https://unix.stackexchange.com/q/491823)).

In this article, the contexts are:

- a test Ruby process;
- hypthetically, a hung application server.

even if case #2 is a production environment, a hung process is typically killed.

All in all, one needs to balance the risk of the procedure, with the worst case scenario of the given context.

Having said that, somebody anyway routinely use this strategy for [switching log files on the fly](https://www.redpill-linpro.com/sysadvent/2015/12/04/changing-a-process-file-descriptor-with-gdb.html) - this article gave the reader all the tools to fully understand it.

## Other GDB/Ruby tools

The GDB/Ruby potential is unlimited; in this section I'll briefly examine two concepts.

### Evaluating Ruby statements

The function `rb_backtrace()` is only one of the many available in the Ruby C API. We can for example print debug information and execute `eval()`; the related APIs are:

```c
void rb_p(VALUE obj);                                       // debug print within C code
VALUE rb_eval_string(const char*);                          // evaluate the given string in an isolated binding
VALUE rb_eval_string_protect(const char *str, int *pstate); // same as above, but store the return value in *pstate instead of raising an exception
```

Now, the [`VALUE` data type](https://silverhammermba.github.io/emberb/c/#value) is not available in this GDB context; additionally, the underlying data type is set at compile-time:

```sh
debug:$ git clone https://github.com/ruby/ruby.git /tmp/ruby
debug:$ grep -P 'typedef .*VALUE;' --before 1 --include="*.h" -r !$
./include/ruby/ruby.h-#if defined HAVE_UINTPTR_T && 0
./include/ruby/ruby.h:typedef uintptr_t VALUE;
--
./include/ruby/ruby.h-#elif SIZEOF_LONG == SIZEOF_VOIDP
./include/ruby/ruby.h:typedef unsigned long VALUE;
--
./include/ruby/ruby.h-#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
./include/ruby/ruby.h:typedef unsigned LONG_LONG VALUE;
```

Commonly, the underlying data type is `unsigned long`, an *at least* 32 bits in size integer type (running `configure` on my machine, it's resolved to 64 bits), therefore, we'll use that as return data type on `call`s:

```
(gdb) call (void) rb_p((unsigned long) rb_eval_string_protect("puts 1", (int*)0))
# will print the following to the stdout of the associated terminal 
123
nil
```

note that we discard the `pstate` variable, by passing a null pointer (`(int*)0`), therefore, ignoring errors.

### An alternative option to redirecting stdout/stderr

Using the `eval` API above, we can redirect stdout/stderr by reassigning `$stdout`/`$stderr` to a logfile:

```
(gdb) call (unsigned long) rb_eval_string("$stdout = File.open('/tmp/ruby.log', 'w'); $stdout.sync = true")
(gdb) call (unsigned long) rb_eval_string("$stdout.puts 'to the debug log!'")
```

This approach is referenced in some websites; while it does redirect the `$stdout` output, it causes the Ruby process to hang (on my machines), likely because it corrupts the interpreter internal state.

Note that Ruby makes available also the constants STDOUT/STDERR, pointing to the original device files. It's not possible to know if they have been overwritten by the target program; it's bad practice, but it's still possible.

### Other interesting sources

An interesting article, which uses GDB in depth to debug a Ruby issue is [Finding a Ruby bug with GDB](https://medium.com/@zanker/finding-a-ruby-bug-with-gdb-56d6b321bc86).

## Conclusion

In this article, I've taken a trivial concept that is often presented as a sequence to copy/paste, and extended the concepts (both in breadth and depth), and the tools employed; this subject is, in particular, rather cross-cutting, so there's plenty of things to dive in.

Enjoy debugging production! 😬
