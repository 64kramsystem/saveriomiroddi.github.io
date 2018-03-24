---
layout: post
title: Remotely running asynchronous commands/scripts via GNU Screen
tags: [shell_scripting,sysadmin]
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
- the help implicitly assumes that the filename is `screen_session_execut.sh`, but the name is arbitrary;
- the script needs executable permissions;
- a mail transfer agent (agents like postfix can be installed via package manager, and generally work out of the box).

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

if [[ $# -lt 2 ]] || [[ $1 =~ ^[0-9] ]]; then
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

screen -r "$session_name" -X stuff "\
bash $command_file > $log_file 2>&1

if [[ \$? -eq 0 ]]; then
  cat $log_file | mail -s 'Session $session_name successful!' $email_recipient
else
  cat $log_file | mail -s 'Session $session_name failed' $email_recipient
fi

shred -u $command_file $log_file

exit 0
"
```

## Script explanation

The first (cool) concept is bash regex matching:

```sh
if [[ $# -lt 2 ]] || [[ $1 =~ ^[0-9] ]]; then
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

Now we actually execute the script, followed by email sending and session exit:

```sh
screen -r "$session_name" -X stuff "\
bash $command_file > $log_file 2>&1

if [[ \$? -eq 0 ]]; then
  cat $log_file | mail -s 'Session $session_name successful!' $email_recipient
else
  cat $log_file | mail -s 'Session $session_name failed' $email_recipient
fi

shred -u $command_file $log_file

exit
"
```

This is accomplished by using the `stuff` command, which is an awkward name for sending a string to the stdin of the screen window.

A **crucial** mistake not to make when using `stuff` is to append a newline at the end of the string, otherwise the command won't be executed; for example this:

```sh
screen -r "$session_name" -X stuff "bash $command_file > $log_file 2>&1"
```

will not execute the bash command.

One interesting design choice is to log the script execution via simple redirection to a file (`> $log_file 2>&1`).

GNU Screen does support logging, which can be enabled via `logfile <filename>` + `log on` + `log off`, however, in this context, it's very troublesome to use for a couple of reasons:

1. it can't be precisely synced with the window internal shell commands, so that, for example, if starting after the paste, the paste itself may still show in the log;
2. we can't turn it off via `colon` command, as it will terminate the logging immediately, so it needs to be queued after the user command as nested screen command, which leads to awkward nested quoting, and it doesn't seem to stop the logging anyway.

The rest is maintenance:

```sh
shred -u $command_file $log_file
exit 0
```

The utility `shred` is used to avoid leaving sensitive informations on the disk, however, all the related storage problems apply (eg. SSD, logged filesystems etc.), so this is not intended to be used in cases of security-critical contexts.

A general consideration is that it's possible to perform the whole operation without using a remote-residing script, however this requires some trickery (notably escaping, which makes the scripting messy), therefore it's simpler to use the above solution.

## Conclusion

GNU Screen is an old-school, but still very valid, and it's a very helpful tool for system administration tasks.

## References

- [GNU Screen commands reference](http://aperiodic.net/screen/commands:start)
