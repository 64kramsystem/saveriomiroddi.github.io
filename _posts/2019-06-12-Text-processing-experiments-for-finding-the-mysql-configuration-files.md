---
layout: post
title: Text processing experiments for finding the MySQL configuration files
tags: [linux,sysadmin,mysql,awk,perl,text_processing]
---

When it comes to configuring MySQL, a fundamental step is to find out which configuration files the MySQL server reads.

The operation itself is simple, however, if we want to script the operation, using text processing in a sharp way, it's not immediate what the best solution is.

In this post I'll explore the process of looking for a satisfying solution, going through grep, perl, and awk.

Contents:

- [Assumptions](/Text-processing-experiments-for-finding-the-mysql-configuration-files#assumptions)
- [Input data (finding the configuration files read by MySQL)](/Text-processing-experiments-for-finding-the-mysql-configuration-files#input-data-finding-the-configuration-files-read-by-mysql)
- [First step: grep+tail](/Text-processing-experiments-for-finding-the-mysql-configuration-files#first-step-greptail)
- [Second step: expanding the tilde](/Text-processing-experiments-for-finding-the-mysql-configuration-files#second-step-expanding-the-tilde)
- [Final step: awk's super powers](/Text-processing-experiments-for-finding-the-mysql-configuration-files#final-step-awks-super-powers)
- [Extra step: using the output](/Text-processing-experiments-for-finding-the-mysql-configuration-files#extra-step-using-the-output)
- [Conclusion](/Text-processing-experiments-for-finding-the-mysql-configuration-files#conclusion)

## Assumptions

For simplicity, we assume that the filenames returned by the `mysqld` commands, and the user home path, don't require quoting (e.g. have spaces).

## Input data (finding the configuration files read by MySQL)

Finding the configuration files is a simple operation:

```sh
$ mysqld --verbose --help
```

This yields a pages-long text, with all the command lines parameter and the server configuration; the relevant section is:

```
# ...
Default options are read from the following files in the given order:
/etc/my.cnf /etc/mysql/my.cnf /usr/local/mysql/etc/my.cnf ~/.my.cnf
# ...
```

## First step: grep+tail

A generic, manual, approach is to use grep to isolate the text:

```sh
$ mysqld --verbose --help | grep -A 1 "^Default options"
Default options are read from the following files in the given order:
/etc/my.cnf /etc/mysql/my.cnf /usr/local/mysql/etc/my.cnf ~/.my.cnf
```

Using the option `-A` (`--after-context`), we tell grep to print the given number of lines after the match.

Now we isolate the options line:

```sh
$ mysqld --verbose --help | grep -A 1 "^Default options" | tail -n 1
/etc/my.cnf /etc/mysql/my.cnf /usr/local/mysql/etc/my.cnf ~/.my.cnf
```

Standard approach - we use `tail -n 1` in order to print the last 1 line(s).

## Second step: expanding the tilde

There's a problem now; we need to expand the tilde (`~`).

Since the string `~/.my.cnf` is the output of a command, it's not expanded by the subshell; this simplified example fails:

```sh
$ ls -l $(echo '~/.my.cnf')
ls: cannot access '~/.my.cnf': No such file or directory
```

We'll try search/replace the tilde with the home path (`$HOME` in any shell) via Perl:

```sh
$ mysqld --verbose --help | grep -A 1 "^Default options" | tail -n 1 | perl -pe "s/~/$HOME/g"
Unknown regexp modifier "/h" at -e line 1, at end of line
syntax error at -e line 1, at EOF
Execution of -e aborted due to compilation errors.
```

Yikes! What happened?

The problem is that `$HOME`, in my case `/home/saverio`, contains backslashes, which are interpolated by the shell, and ultimately interpreted by Perl; this is the simplified example:

```sh
$ echo perl -pe "s/~/$HOME/g"
perl -pe s/~//home/saverio/g

$ echo | perl -pe 's/~//home/saverio/g'
Unknown regexp modifier "/h" at -e line 1, at end of line
Execution of -e aborted due to compilation errors.
```

which causes the error previously raised.

Perl can access environment variables - this comes to our rescue:

```sh
$ echo '~/.my.cnf' | perl -pe 's/~/$ENV{"HOME"}/'
/home/saverio/.my.cnf
```

We now have the building blocks of a fully functional command:

```sh
$ mysqld --verbose --help | grep -A 1 "^Default options" | tail -n 1 | perl -pe 's/~/$ENV{"HOME"}/g'
/etc/my.cnf /etc/mysql/my.cnf /usr/local/mysql/etc/my.cnf /home/saverio/.my.cnf
```

Don't forget the `/g` regex modifier! It tells Perl to replace all the occurrences of a pattern in each matching line, if there's more than one match (per line).

Our task is now accomplished. Can we do better?

## Final step: awk's super powers

While the last revision of the command works, it contains way too many commands. Does the GNU toolbox have better tools?

Let's see what awk offers.

Awk is a (Turing-complete!) programming language, dedicated to text-processing; hopefully, it includes built-in functions relevant to our task.

The ugliest part right now is to isolate the options string from the entire `mysqld` help. The logic required is:

- find a matching line
- print the line below

with grep, unfortunately we can't just print the line below without printing the matching line. But we can with awk!:

```sh
$ mysqld --verbose --help | awk '/^Default options/ { getline; print }'
/etc/my.cnf /etc/mysql/my.cnf /usr/local/mysql/etc/my.cnf ~/.my.cnf
```

Awk's language is fortunately fairly intuitive.  
We use pattern matching `/<pattern>/` to match the intended line, and for the matches we execute a block (`{ ... }`) that goes to the next line (`getline`) and then prints the current one (`print`).

Now, in the current revision, we still have two commands, `awk` and `perl`:

```sh
mysqld --verbose --help | awk '/^Default options/ { getline; print }' | perl -pe 's/~/$ENV{"HOME"}/g'
```

Let's merge them! We use awk's search and replace, and environment variables access:

```sh
$ mysqld --verbose --help | awk '/^Default options/ { getline; gsub("~", ENVIRON["HOME"]); print }'
/etc/my.cnf /etc/mysql/my.cnf /usr/local/mysql/etc/my.cnf /home/saverio/.my.cnf
```

Here we use the search and replace function (`gsub(source[, destination[, how]])`; `how` is not relevant to this article) and associative arrays applied to environment variables (`ENVIRON[<variable_name>]`).

Note that `gsub` is the global version of search/replace; it replaces all the occurrence in a string, like perl `/g` regex modifier.

## Extra step: using the output

As extra step, we want to use the output. Say, let's add a comment to the `[mysqld]` block:

```sh
$ perl -i -pe 's/^(\[mysqld\]\n)/# Server configuration group follows:\n$1/' $(mysqld --verbose --help | awk '/^Default options/ { getline; gsub("~", ENVIRON["HOME"]); print }') 2> /dev/null
```

We just ignore the errors (due to file(s) not found), by sending them to `/dev/null`.

## Conclusion

Long ago, I thought that one could improve text processing tools with a straight read of educational material. Nowadays, I find much more effective (and pleasant) instead, to try finding out, when I have the opportunity, which are the most effective tools to a accomplish a task.

In this article we've done an iterative search of the best text processing tools for the given use case; we've found that awk compactly, yet intuitively, satisfies the requirements, and we've explored a few, interesting and useful, features along the way.