---
layout: post
title: Remotely running asynchronous commands/scripts via GNU Screen
tags: [shell_scripting,sysadmin]
last_modified_at: 2018-06-05 12:01:00
---

In system administration, it's typical to perform long-running commands on remote hosts.

With GNU Screen and one supporting script, it's possible to efficiently perform such operations, by running them asynchronously and receiving an email at the end, all in a single command.

Contents:

- [Some GNU Screen concepts](/Remotely-running-asynchronous-commands-scripts-via-gnu-screen#some-gnu-screen-concepts)
- [Purpose and overview of the script](/Remotely-running-asynchronous-commands-scripts-via-gnu-screen#purpose-and-overview-of-the-script)
- [Script requirements](/Remotely-running-asynchronous-commands-scripts-via-gnu-screen#script-requirements)
- [Script source](/Remotely-running-asynchronous-commands-scripts-via-gnu-screen#script-source)
- [Script explanation](/Remotely-running-asynchronous-commands-scripts-via-gnu-screen#script-explanation)
- [Conclusion](/Remotely-running-asynchronous-commands-scripts-via-gnu-screen#conclusion)
- [References](/Remotely-running-asynchronous-commands-scripts-via-gnu-screen#references)

## Some GNU Screen concepts

Everybody who's done some system administration knows what GNU Screen is; it's typically used in order to give resume capabilities to an SSH session.

GNU Screen is a bit awkward in some areas, but still very flexible.

All the functionalities, called "commands", are invoked by a hotkey, followed by colon (`:`) and a descriptive name with parameters, e.g. `:hardcopy current.log`. There are hotkey combinations for many commands.

Crucially, it's also possible to send commands to an existing session via shell commands.

## Purpose and overview of the script

The purpose of the script is to run a command like the following:

```sh
$ ssh dbhost "screen_session_execute.sh alter_table user@mycompany.com" <<'CMD'
> mysql -e 'CREATE TABLE mytable.bak SELECT * FROM mytable'
> CMD
```

which, asynchronously (ie. returning immediately to the user):

- creates a screen session (named `alter_table`) on `dbhost`
- runs the long-running operation
- on completion, sends and email to `user@mycompany.com` with the log
- closes the screen session

## Script requirements

- the script needs to be on the remote host, available in the `$PATH` (if not in `$PATH`, the `ssh` command will need to have the full path);
- the help implicitly assumes that the filename is `screen_session_execute.sh`, but the name is arbitrary;
- the script needs executable permissions;
- a mail transfer agent (the script uses `mutt`, which supports attachments; in Ubuntu, it can be installed via `apt install mutt`).

## Script source

This is the script source; the explanation is in the following section.

```sh
#!/bin/bash

set -o errexit

help=$'Usage: screen_session_execute.sh <session_name> <email_recipient> <heredoc_command>

Executes the command in a detached screen session, then sends the log to the email recipient, and closes the session.

The session name can\'t start with a number!

Example:

    screen_session_execute.sh alter_table user@mycompany.com <<\'CMD\'
    mysql -e "CREATE TABLE mydb._mytable_bak SELECT * FROM mydb.mytable"
    CMD
'

if [[ $# -ne 2 ]] || [[ "$1" = "-h" ]] || [[ "$1" = "--help" ]] || [[ $1 =~ ^[0-9] ]]; then
  echo "$help"
  exit 1
fi

session_name="$1"
command_file="session_$session_name.sh"
log_file="session_$session_name.log"
email_recipient="$2"

cat > "$command_file"

screen -dmS "$session_name"

screen -r "$session_name" -X readbuf "$command_file"
screen -r "$session_name" -X paste .

while ! screen -ls "$session_name" | grep -q tached; do sleep 0.1; done

screen -r "$session_name" -X stuff "\
bash $command_file > $log_file 2>&1

xz -2k $log_file
"

screen -r "$session_name" -X stuff "\
if [[ \$? -eq 0 ]]; then
  mail_title='Session $session_name successful!'
else
  mail_title='Session $session_name failed'
fi

cat <(echo \$'Last 20 lines of the log:\n') <(tail -n 20 $log_file) | mutt -e 'set copy=no' -a $log_file.xz -s 'Session $session_name successful!' -- $email_recipient
"

screen -r "$session_name" -X stuff "\
shred -u $command_file $log_file $log_file.xz

exit 0
"
```

## Script explanation

The first (cool) concept is bash regex matching:

```sh
if [[ $# -ne 2 ]] || [[ "$1" = "-h" ]] || [[ "$1" = "--help" ]] || [[ $1 =~ ^[0-9] ]]; then
```

Since screen doesn't behave as expected when using session names starting with numbers, we exit with an error in such cases; bash supports regular expression in modern versions, so this task is very conveniently implemented.

Here we start the session:

```sh
screen -dmS "$session_name"
```

Now, we send the script/command to the screen session:

```sh
cat > "$command_file"
#...
screen -r "$session_name" -X readbuf "$command_file"
screen -r "$session_name" -X paste .
```

which redirects the output we send in heredoc format (`<<'CMD'`) to the remote terminal input.

The `readbuf` + `paste .` screen commands respectively copy the file content to the "paste buffer", then paste the buffer content (from the "register .") to the stdin of the screen window.

It's possible to avoid using a file with some trickery, but this is the simplest solution.

We need to workaround an issue with Screen: it may not make the session immediately available, so we wait for it:

```sh
while ! screen -ls "$session_name" | grep -q tached; do sleep 0.1; done
```

`tached` matches both `Attached` and `Detached`, the two screen statuses. In this context, the only state is detached, but we capture both for safety.  
Note that the pattern matching employed is simplistic, however, it works fine in this context.

Now we actually execute the script, followed by email sending and session exit.

```sh
screen -r "$session_name" -X stuff "\
bash $command_file > $log_file 2>&1

xz -2k $log_file
"
```

This is accomplished by using the `stuff` command, which is an awkward name for sending a string to the stdin of the screen window.  
Such command has a limited buffer, so we split in multiple strings. Annoyingly, if a large string is sent, the command will fail silently.

A **crucial** mistake not to make when using `stuff` is to append a newline at the end of the string, otherwise the command won't be executed; for example this:

```sh
screen -r "$session_name" -X stuff "bash $command_file > $log_file 2>&1"
```

will not execute the bash command.

One interesting design choice is to log the script execution via simple redirection to a file (`> $log_file 2>&1`).

GNU Screen does support logging, which can be enabled via `logfile <filename>` + `log on` + `log off`, however, in this context, it's very troublesome to use for a couple of reasons:

1. it can't be precisely synced with the window internal shell commands, so that, for example, if starting after the paste, the paste itself may still show in the log;
2. we can't turn it off via `colon` command, as it will terminate the logging immediately, so it needs to be queued after the user command as nested screen command, which leads to awkward nested quoting, and it doesn't seem to stop the logging anyway.

There are many options for sending an email in Linux via terminal.  

In order to send attachments, we use Mutt; the standard `mail` package in Ubuntu maps to `bsd-mailx`, which works OK, but has no direct attachment support.  Mutt can be installed in Ubuntu via `apt install mutt`.

```sh
screen -r "$session_name" -X stuff "\
if [[ \$? -eq 0 ]]; then
  mail_title='Session $session_name successful!'
else
  mail_title='Session $session_name failed'
fi

cat <(echo \$'Last 20 lines of the log:\n') <(tail -n 20 $log_file) | mutt -e 'set copy=no' -a $log_file.xz -s 'Session $session_name successful!' -- $email_recipient
"
```

An interesting bit is the `<()` syntax - the so-called [Process substitution](http://www.gnu.org/software/bash/manual/html_node/Process-Substitution.html#Process-Substitution). In short, it creates a file with the output of the inner command.

In this case, it allows to concatenate the output two commands, as if it would be:

```sh
cat file1 file2 | mutt....
```

A note about Mutt is that the `-e set 'copy=no'` disables the creation of `$HOME/sent` file, which is not useful in this context.

The end of the script is maintenance:

```sh
screen -r "$session_name" -X stuff "\
shred -u $command_file $log_file $log_file.xz

exit
"
```

The utility `shred` is used to avoid leaving sensitive informations on the disk, however, all the related storage problems apply (eg. SSD, logged filesystems etc.), so this is not intended to be used in cases of security-critical contexts.

A general consideration is that it's possible to perform the whole operation without using a remote-residing script, however this requires some trickery (notably escaping, which makes the scripting messy), therefore it's simpler to use the above solution.

## Conclusion

GNU Screen is an old-school, but still very valid, and it's a very helpful tool for system administration tasks.

## References

- [GNU Screen commands reference](http://aperiodic.net/screen/commands:start)

## Edits

- _2018-06-05_: use Mutt for handling attachments; minor improvements to the Screen handling
