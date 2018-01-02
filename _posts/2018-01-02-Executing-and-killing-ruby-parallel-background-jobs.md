---
layout: post
title: Executing and killing ruby parallel/background jobs
tags: [concurrency,ruby,linux,sysadmin]
---

In a [project of mine](https://github.com/saveriomiroddi/pm-spotlight/), I'm implementing a feature that runs a background job in order to perform a search; in particular, it needs to support stopping at any time.

There is a variety of strategies to do this in Ruby. In this article I will expose what is the exact outcome of the common strategies, examining how this affects the underlying operating system.

The analysis is targeted to POSIX operating systems, although, at least part of it applies to Windows machines as well.

Contents:

- [Brief introduction to Ruby concurrency](/Executing-and-killing-ruby-parallel-background-jobs#brief-introduction-to-ruby-concurrency)
- [Technical context and preliminary notes](/Executing-and-killing-ruby-parallel-background-jobs#technical-context-and-preliminary-notes)
- [Problem statement](/Executing-and-killing-ruby-parallel-background-jobs#problem-statement)
- [Effect of the common strategies on a Linux operating systems](/Executing-and-killing-ruby-parallel-background-jobs#effect-of-the-common-strategies-on-a-linux-operating-systems)
  - [Threads, and `Thread#kill`](/Executing-and-killing-ruby-parallel-background-jobs#threads-and-threadkill)
  - [`Kernel#fork`](/Executing-and-killing-ruby-parallel-background-jobs#kernelfork)
  - [Dealing with zombie processes: `Process.detach`](/Executing-and-killing-ruby-parallel-background-jobs#dealing-with-zombie-processes-processdetach)
  - [`Kernel#spawn`](/Executing-and-killing-ruby-parallel-background-jobs/#kernelspawn)
- [Introduction to process groups and their usage](/Executing-and-killing-ruby-parallel-background-jobs#introduction-to-process-groups-and-their-usage)
  - [Non-working usage of process groups](/Executing-and-killing-ruby-parallel-background-jobs#non-working-usage-of-process-groups)
  - [Working implementation, using `setsid`](/Executing-and-killing-ruby-parallel-background-jobs#working-implementation-using-setsid)
- [Conclusion](/Executing-and-killing-ruby-parallel-background-jobs#conclusion)

## Brief introduction to Ruby concurrency

Ruby concurrency is a largely documented subject; I will recap a few critical points:

- the reference Ruby implementation (MRI) can't execute threads in parallel, but can with processes;
- threads can still be used to achieve effective parallelism if they spend their time waiting on I/O;
- processes are supposed to be slower to instantiate and more resource consuming, but this applies generally to large-scale processing, and, as with any performance concept, the impact **must be always profiled before taking conclusions**.

## Technical context and preliminary notes

All the concepts in this article refer to the MRI interpreter.

The processes information is checked on an Ubuntu machine, using `ps x --forest`; only the relevant information is displayed (the bash/upstart processes are displayed for completeness).

The examples are simplified forms of concurrent programming. The statement `sleep 0.1` is used to give a reasonable certainty that forked processes did actually start; in a rigorously written concurrent program, this call would be replaced with thread notifications, as there is no absolute guarantee that this amount of time (or any, for that matter) will be enough.

## Problem statement

The requirements are:

- to run a file search in background (backed by the the Linux `find` shell command);
- to gather results from a completed search;
- to have the ability to stop the search at any moment, predictably and cleanly, and possibly, with minimal engineering.

## Effect of the common strategies on a Linux operating systems

In this first part, I will expose the most common strategy Ruby provides for performing background jobs (in general).

The code is executed in an `irb` session inside a Bash shell.

### Threads, and `Thread#kill`

Threads in Ruby (MRI) are convenient as a lightweight framework to perform operations which are blocked by I/O.

Threading suffer in the area of management, though; while killing them is possible, the effects are unspecified.  
Java has for example deprecated threads killing long ago, declaring it's not possible to perform cleanup deterministically.

Ruby threads don't play well with subshells, for example:

```ruby
irb> thread = Thread.new { `sleep 10` }
irb> thread.terminate # => #<Thread:0x00000000be6798@(irb):3 dead>
```

The thread will be killed from a Ruby perspective, but the subshell will still run:

```
14937 pts/9    Ss     0:00  |   \_ -bash
18837 pts/9    Sl+    0:00  |   |   \_ irb
18841 pts/9    S+     0:00  |   |       \_ sleep 10
```

After that, a zombie process will also remain (notice `defunct` and `Z+`):

```
14937 pts/9    Ss     0:00  |   \_ -bash
18837 pts/9    Sl+    0:00  |   |   \_ irb
18841 pts/9    Z+     0:00  |   |       \_ [sleep] <defunct>
```

(more on zombie processes later)

Threads are therefore not a good solution, at least, for the defined problem.

### `Kernel#fork`

`Kernel#fork` will fork the current process, and execute it.

The most common Ruby forking command is the block version; this is how the functionality is expressed:

```ruby
irb> child_pid = fork { `sleep 10` }
irb> sleep 0.1
irb> Process.kill('SIGHUP', child_pid)
```

We send a [SIGHUP](https://en.wikipedia.org/wiki/Signal_(IPC)#SIGHUP) signal.  
SIGHUP responses vary by program; in the case of `irb` and shell `sleep`/`find`, it will terminate the program, so it's appropriate for our purpose.

This is the process information, pre-kill:

```
14937 pts/9    Ss     0:00  |   \_ -bash
21085 pts/9    Sl+    0:00  |   |   \_ irb
21087 pts/9    Sl+    0:00  |   |       \_ irb
21090 pts/9    S+     0:00  |   |           \_ sleep 10
```

We can see that `irb` is forked, becoming a child of the top-level interpreter, and then, in turn, it generates a child of its own, with the subshell executing the `sleep` command.

This is the process information after the kill:

```
1836  ?        Ss     0:00 /sbin/upstart --user
14937 pts/9    Ss     0:00  |   \_ -bash
21085 pts/9    Sl+    0:00  |   |   \_ irb
21087 pts/9    Z+     0:00  |   |       \_ [ruby] <defunct>
21090 pts/9    S+     0:00  \_ sleep 10
```

Yikes! The job (`sleep`) still runs. What's happening?

It turns out that signals are not cascading, so the child `irb` (21087) receives the hangup signal, and terminates, but its child (21090) doesn't, and it's detached from it, still running in the background.

When a process is detached, it becomes a child of the root process (upstart or init), in this system, [upstart](https://en.wikipedia.org/wiki/Upstart).

So now we have two problems:

1. we still have a zombie process
2. we're still not terminating the background job

In the next section, we'll deal with those pesky zombie processes.

### Dealing with zombie processes: `Process.detach`

As we've seen, when a signal is sent to a process, it's its own task to handle its children; Ruby doesn't clean forked processes with subshells, though.

We can solve this problem by detaching the child process, which then becomes a child of the root process; this will take care of it:

child_pid = fork { `sleep 10` }
sleep 0.1
Process.detach(child_pid)
Process.kill('SIGHUP', child_pid)

After `fork`:

```
 1836 ?        Ss     0:00 /sbin/upstart --user
14937 pts/9    Ss     0:00  |   \_ -bash
23144 pts/9    Sl+    0:00  |   |   \_ irb
23156 pts/9    Sl+    0:00  |   |       \_ irb
23159 pts/9    S+     0:00  |   |           \_ sleep 10
```

After `kill`:

```
 1836 ?        Ss     0:00 /sbin/upstart --user
14937 pts/9    Ss     0:00  |   \_ -bash
23144 pts/9    Sl+    0:00  |   |   \_ irb
23156 pts/9    Z+     0:00  |   |       \_ [ruby] <defunct>
23159 pts/9    S+     0:00  \_ sleep 10
```

After `detach`:

```
 1836 ?        Ss     0:00 /sbin/upstart --user
14937 pts/9    Ss     0:00  |   \_ -bash
23144 pts/9    Sl+    0:00  |   |   \_ irb
23159 pts/9    S+     0:00  \_ sleep 10
```

The zombie process is now gone; upstart took care of it.

### `Kernel#spawn`

`Kernel#spawn`, introduced long ago in Ruby 1.9, performs two operations: `fork` and `exec`.

`exec` replaces the current process with the shell execution, effectively terminating the Ruby interpreter:

```ruby
irb> exec 'sleep 1'; puts 'Other operation'
```

The second statement won't be executed; the interpreter will exit after the `sleep` invocation. So why is this useful?

Sometimes people want to "fire and forget" jobs; `spawn` is the appropriate tool (for this requirement):

```ruby
irb> child_pid = spawn 'sleep 10'
```

This works, without exiting the interpreter, because `exec` will replace the subprocess. This is the `fork` + `exec` equivalent:

```ruby
irb> child_pid = fork { exec 'sleep 10' }
```

And this is the processes information:

```
14937 pts/9    Ss     0:00  |   \_ -bash
18837 pts/9    Sl+    0:00  |   |   \_ irb
19124 pts/9    S+     0:00  |   |       \_ sleep 10

```

Compare this with using ``fork { `sleep 10` }``:

```
14937 pts/9    Ss     0:00  |   \_ -bash
19161 pts/9    Sl+    0:00  |   |   \_ irb
19222 pts/9    Sl+    0:00  |   |       \_ irb
19225 pts/9    S+     0:00  |   |           \_ sleep 10
```

There is a very interesting advantage; since the forked `irb` process, using `spawn`, has been replaced with the subshell (`19124`), we don't have an intermediate process in the middle, and the signals go directly to the intended background job:

```ruby
irb> child_pid = spawn 'sleep 10'
irb> sleep 0.1
irb> Process.kill('SIGHUP', child_pid)
irb> Process.detach(child_pid)
```

Status at the end:

```
14937 pts/9    Ss     0:00  |   \_ -bash
21330 pts/9    Sl+    0:00  |   |   \_ irb
```

The `sleep` background job is now under our direct control!

Sadly, we can't use `spawn` to solve the defined problem, because we still want a child interpreter running in order to return the search result.

## Introduction to process groups and their usage

While we can theoretically manually track children of children, it's of course better to find a way to manage this automatically.

Fortunately, [Process groups](https://en.wikipedia.org/wiki/Process_group) come to the rescue:

> In a POSIX-conformant operating system, a process group denotes a collection of one or more processes. Among other things, a process group is used to control the distribution of a signal; when a signal is directed to a process group, the signal is delivered to each process that is a member of the group.
>
> When a process is forked, it inherits its PGID from its parent. The PGID changes when a process becomes a process group leader, then its PGID is copied from its PID. From then on, the new child processes it spawns, and their descendants, inherit that PGID (unless they start new process groups of their own).

By using process groups, we just deal with the forked process, and its child(ren) will receive the intended signal, too.

Note that in the next sections, the Ruby code is executed directly by a the interpreter, and not run in an interactive session.  
Also, importantly, since the example is concurrent, there are no strict guarantees of the execution order; the interest is in the (guaranteed) end result.

### Non-working usage of process groups

This example shows an example which prints all the information, and attempts to use the process groups strategy to terminate the background job:

```ruby
puts "Parent pid: #{Process.pid}. pgid: #{Process.getpgrp}"

child_pid = fork do
  puts "Child pid: #{Process.pid}, pgid: #{Process.getpgrp}"

  puts 'Child: long operation...'

  system 'sleep 10'
end

sleep 0.1

pgid = Process.getpgid(child_pid)

puts "Sending HUP to group #{pgid}..."

Process.kill('SIGHUP', -pgid)
Process.detach(child_pid)

puts 'Parent: exiting...'
```

The notable call is the negative number in `Process.kill('SIGHUP', -pgid)`; the POSIX meaning is that we want to send the signal to the process group, not to the given process.

This is the output:

```
Parent pid: 4887. pgid: 4887
Child pid: 4889, pgid: 4887
Child: long operation...
Sending HUP to group 4887...
Hangup
```

The parent doesn't get to the last statement. Why?

We can see from the logs, that when the fork happens, the child doesn't get a new process group id - it still remains in the parent process group, which makes sense as a default behavior.

Therefore, when we send the hangup to the child process group, since the parent is in the same group, it will terminate as well, not reaching the last statement.

What we need is to move the child process to its own process group.

### Working implementation, using `setsid`

Moving a process to its own group is performed by `setsid`; from the Linux [man page](https://linux.die.net/man/2/setsid):

> setsid() creates a new session if the calling process is not a process group leader. The calling process is the leader of the new session, the process group leader of the new process group, and has no controlling terminal. The process group ID and session ID of the calling process are set to the PID of the calling process. [...]

Ruby supports this directly through `Process.setsid`; let's see what happens:

```ruby
puts "Parent pid: #{Process.pid}. pgid: #{Process.getpgrp}"

child_pid = fork do
  puts "Child pid: #{Process.pid}, pgid: #{Process.getpgrp}"

  Process.setsid

  puts "Child new pgid: #{Process.getpgrp}"

  puts "Child: long operation..."

  system "sleep 10"
end

sleep 5 # for taking the process information

pgid = Process.getpgid(child_pid)

puts "Sending HUP to group #{pgid}..."

Process.kill('HUP', -pgid)

Process.detach(pgid)

puts "Parent: exiting..."

sleep 10
```

Output:

```
Parent pid: 30731. pgid: 30731
Child pid: 30733, pgid: 30731
Child new pgid: 30733
Child: long operation...
Sending HUP to group 30733...
Parent: exiting...
```

We can see on the third line that `Process.setsid` changed the forked process group id; the parent won't belong any more to it, so we're free to send signals without interrupting the parent process.

Processes information:

```
 1836 ?        Ss     0:00 /sbin/upstart --user
17512 pts/10   Ss     0:00  |   \_ -bash
30731 pts/10   Sl+    0:00  |   |   \_ ruby /tmp/test.rb
30733 ?        Ssl    0:00  |   |       \_ ruby /tmp/test.rb
30736 ?        S      0:00  |   |           \_ sleep 10
```

```
 1836 ?        Ss     0:00 /sbin/upstart --user
17512 pts/10   Ss     0:00  |   \_ -bash
30731 pts/10   Sl+    0:00  |   |   \_ ruby /tmp/test.rb
```

The background process is gone, and we still have the option of managing the child process as we wish (ie. both returning results and terminating).

## Conclusion

Although this article doesn't deal with thread-specific programming, instead with processes, it gives tools to handle with many cases, especially, system(-administration) related programming, where invoking subshells is common.

Using signals and process groups allows the programmer to have a precise and clean control over the lifecycle of a background job, which is crucial for concurrent programming.
