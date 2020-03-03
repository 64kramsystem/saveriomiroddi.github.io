---
layout: post
title: Running shell commands in parallel, via GNU Parallel
tags: [concurrency,linux,shell_scripting,sysadmin]
---

Sometimes, either in scripts or direct commands, there is a series of repetitive, similar, commands, which could be executed in parallel.

Bash offers means for very basic parallelization (`&` and `wait`), however, they're not very practical for generic solutions.

In this article, I'll explain how to use GNU Parallel, which makes parallelization trivial, and, as usual, introduce some other useful shell concepts.

Contents:

- [Using Bash built-in commands](/Running-shell-commands-in-parallel-via-gnu-parallel#using-bash-built-in-commands)
  - [Conclusion](/Running-shell-commands-in-parallel-via-gnu-parallel#conclusion)
- [Enter the stage: GNU Parallel](/Running-shell-commands-in-parallel-via-gnu-parallel#enter-the-stage-gnu-parallel)
  - [Important to known: CPU count, from a Linux perspective](/Running-shell-commands-in-parallel-via-gnu-parallel#important-to-known-cpu-count-from-a-linux-perspective)
  - [Base example: untarring multiple archives in parallel](/Running-shell-commands-in-parallel-via-gnu-parallel#base-example-untarring-multiple-archives-in-parallel)
  - [Using positional parameters](/Running-shell-commands-in-parallel-via-gnu-parallel#using-positional-parameters)
  - [Running multiple commands from a file](/Running-shell-commands-in-parallel-via-gnu-parallel#running-multiple-commands-from-a-file)
- [Escaping strings in Bash](/Running-shell-commands-in-parallel-via-gnu-parallel#escaping-strings-in-bash)
- [Sending the content of a file to a process](/Running-shell-commands-in-parallel-via-gnu-parallel#sending-the-content-of-a-file-to-a-process)
- [`$XDG_RUNTIME_DIR`](/Running-shell-commands-in-parallel-via-gnu-parallel#xdg_runtime_dir)
- [Conclusion](/Running-shell-commands-in-parallel-via-gnu-parallel#conclusion-1)
- [Post-conclusion](/Running-shell-commands-in-parallel-via-gnu-parallel#post-conclusion)

## Using Bash built-in commands

Bash allows commands to be run in the background, by appending `&` to the end of the command:

```sh
$ sleep 60 &
$ sleep 60 &
$ sleep 60 &
```

The above command will launch three `sleep`ing processes in the background. We can observer them via `jobs`:

```sh
$ jobs
[1]   Running                 sleep 60 &
[2]-  Running                 sleep 60 &
[3]+  Running                 sleep 60 &
```

There are special symbols:

- `+`: default job (to whom the commands `fg` and `bg` apply to)
- `-`: job that becomes the new default job in case the current one terminates

They are not relevant to this context, but it's always good to know 😉

In the context of parallelization, what we typically need is a mean to wait on all commands to complete. In Bash, we accomplish this via `wait`.

In the simplest form, without any parameters, `wait` waits for all the commands to complete:

```sh
$ wait
[1]   Done                    sleep 60
```

As you see, when the queue is consumed, the last job is printed.

The `&` operator makes it relatively easy to process value lists, for example, filenames.

Let's say you want to compress the WAV files from a CD you've ripped:

```sh
for f in *.wav; do
  # `${f%.wav}`: strip the `.wav` suffix from $f.
  #
  ffmpeg -i "$f" "${f%.wav}.m4a" &
done
wait
```

That's pretty much it!

### Conclusion

The `&`/`wait` solution actually works nicely. However, there are two problems:

1. there is no built-in control over the amount of processes run;
2. when using a list of values (e.g. filenames as in the example above), we could do with a more compact syntax.

This is where GNU Parallel comes into play 😉

## Enter the stage: GNU Parallel

GNU Parallel works, in the base form, with a trivial syntax: it receives the list of values/command via stdin, and executes them via a queue size equal to the number of "CPU".

### Important to know: CPU count, from a Linux perspective

A catch that it's important to know, and this is a general Linux concept, is that with `CPU`, Linux generally intends the minimal processing unit available.

A part of the CPUs nowadays (typically, but not necessarily, the midrange/high-end) employ [Simultaneous multithreading](https://en.wikipedia.org/wiki/Simultaneous_multithreading), whose a **simplistic** definition is that it "allows two threads to run in parallel on a single core".

Therefore, on the machine I'm running:

```
$ lscpu
CPU(s):              16
Thread(s) per core:  2
Core(s) per socket:  8
Model name:          AMD Ryzen 7 3800X 8-Core Processor
```

Linux lists 16 CPUs, as a result of 8 core x 2 threads.

Since the cores are still 8 (again, this is a simplistic view), some tasks benefit from SMT, but some don't.

Parallel will, *by default*, use all the threads available, so keep it in mind if something else is running in the system.

(Interestingly, the manual says `run one job per CPU core on each machine`, which is not technically correct.)

### Base example: untarring multiple archives in parallel

Let's simulate the case where a user wants to download and unpack multiple MySQL releases, in order to test them. No core should be wasted!

```sh
# We put the MySQL versions under `~/local/<mysql_version_dir>`.

$ mkdir ~/local
$ cd ~/local

# Let's use `&`/`wait` to download, because why not!

$ wget https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-5.7.29-linux-glibc2.12-x86_64.tar.gz &
Redirecting output to ‘wget-log’.
$ wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.19-linux-glibc2.12-x86_64.tar.xz &
Redirecting output to ‘wget-log.1’.
$ wait
[1]-  Done                    wget https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-5.7.29-linux-glibc2.12-x86_64.tar.gz
[2]+  Done                    wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.19-linux-glibc2.12-x86_64.tar.xz

# The download will generate the following files:

$ ls 1 *.tar.*
mysql-5.7.29-linux-glibc2.12-x86_64.tar.gz
mysql-8.0.19-linux-glibc2.12-x86_64.tar.xz
```

In the simplest form, Parallel takes a list of arguments (separated by newline) via stdin, and appends them to the command passed, creating one process for each concatenation of command and argument:

```sh
$ ls -1 *.tar.* | parallel tar xvf
```

will translate to:

```sh
$ tar xvf mysql-5.7.29-linux-glibc2.12-x86_64.tar.gz
$ tar xvf mysql-8.0.19-linux-glibc2.12-x86_64.tar.xz
```

running in parallel!

### Using positional parameters

In case the arguments are not the last, Parallel has a very simple syntax.

Let's suppose we want to do the reverse - zipping the directories!:

```sh
ls -ld mysql*/
# drwxrwxr-x 1 saverio saverio 1760 Jan 14 17:14 mysql-5.7.29-linux-glibc2.12-x86_64/
# drwxrwxr-x 1 saverio saverio 1680 Jan 25 21:30 mysql-8.0.19-linux-glibc2.12-x86_64/
```

(note the trick: we can list exclusively the directories by using the  `d` option of `ls`, along with a glob pattern terminating with `/`.)

The general form of the command we want to run is:

```sh
$ zip -r "<directory_name>.zip" "<directory_name>"
```

so that for each `<directory_name>`, we create a corresponding zip file.

We can easily use Parallel's positional parameters:

```sh
$ ls -1d mysql*/ | tr -d / | parallel zip -r {1}.zip {1}
```

(here we need some cleanup: `ls -d <pattern>*/` appends a slash, which we don't want, so we use `tr -d` to remove it.)

While we run this command, we can check what happens from another terminal; let's search all the `zip` processes:

```sh
$ pgrep -a zip
30146 zip -r mysql-5.7.29-linux-glibc2.12-x86_64/.zip mysql-5.7.29-linux-glibc2.12-x86_64/
30147 zip -r mysql-8.0.19-linux-glibc2.12-x86_64/.zip mysql-8.0.19-linux-glibc2.12-x86_64/
```

Task accomplished 🙂

### Running multiple commands from a file

Until now, we based Parallel usage on a certain structure:

1. we set up the command base part (e.g. `tar xvf`) as parameter to the `parallel` command, and pass the parameters from stdin;
1. we pass the command parameters directly.

Let's get more sophisticated.

Regarding point 1., Parallel builds each command invocation from the command base part (`tar xvf`) and each line of the data received via stdin (`mysql-5.7.29-linux-glibc2.12-x86_64.tar.gz`).  
If we don't pass anything, parallel just runs each line received as standalone command.

Regarding point 2., nobody prevents us from creating a file with commands, and sending it to Parallel 🙂

Let's suppose we build [a script for mass-encoding CD rips](https://github.com/saveriomiroddi/openscripts/blob/master/encode_to_m4a).

Now, what we can do is:

```sh
for input_file in "$input_directory"/*.wav; do
  echo "ffmpeg -i $(printf "%q" "$input_file") $(printf "%q" "${input_file%.wav}.m4a")" >> "$XDG_RUNTIME_DIR/parallel_commands_list.sh"
done

parallel < "$XDG_RUNTIME_DIR/parallel_commands_list.sh"
```

There you go! The base motivation for using Parallel here is queue limiting: using `&`/`wait` would simultaneously run a number of processes equal to the number of files, which, in case of large directories, would be undesirable.

I'll point out a few interesting shell concepts in the following sections.

## Escaping strings in Bash

We need to escape the commands in the list! In this we use a bash built-in command: `printf "%q" "$input_file"`.

Let's suppose that the commands file contains:

```
ffmpeg -i 01 - Track 01.wav 01 - Track 01.m4a
ffmpeg -i 01 - Track 01.wav 01 - Track 01.m4a
```

Where does the filenames end and start?

We could use quotes:

```
ffmpeg -i "01 - Track 01.wav" "01 - Track 01.m4a"
ffmpeg -i "01 - Track 01.wav" "01 - Track 01.m4a"
```

This solution works. The generating command is:

```sh
echo "ffmpeg -i \"$input_file\" \"${input_file%.wav}.m4a\"" # [...]
```

however, on a general basis, quotes nesting becomes quite confusing. Additionally, what if the input contains double quotes?

The built-in `printf` improves cases where there is nesting, and also handles input including quotes; the commands list becomes:

```sh
ffmpeg -i 01\ -\ Track\ 01.wav 01\ -\ Track\ 01.m4a
ffmpeg -i 02\ -\ Track\ 02.wav 02\ -\ Track\ 02.m4a
```

## Sending the content of a file to a process

A typical pattern to send the content of a file to a process is:

```sh
$ cat "<filename>" | parallel
```

In Bash, the operator `<` can do this more succinctly:

```sh
$ parallel < "<filename>"
```

Of course, usage of this construct is up to the judgment of the developer, but it's always good to know.

## `$XDG_RUNTIME_DIR`

The legacy, but still typical, way of storing temporary files is to use `/tmp`.

The modern way is to use the user-specific directory provided by systemd:

```
$ man pam_system
       $XDG_RUNTIME_DIR
           Path to a user-private user-writable directory that is bound to the user login time on
           the machine. It is automatically created the first time a user logs in and removed on
           the user's final logout. [...]
```

It generally translates to:

```
$ echo $XDG_RUNTIME_DIR
/run/user/1000
```

In this case (that is, for single-user environments), `1000` is the id of the first user.

The common tool `mktemp` does not use this directory, so modern invocations should consider this:

```sh
# Legacy invocation
#
$ mktemp
/tmp/tmp.RfJec8pjGd

# Modernized invocation
#
$ mktemp "$XDG_RUNTIME_DIR/tmp.XXXXXXXXXX"
/run/user/1000/tmp.AcSjj8BAmc
```

## Conclusion

Unix tools vs Knuth 1-0.

## Post-conclusion

I actually value theoretical/formal education significantly, but it's fun to make fun of it.
