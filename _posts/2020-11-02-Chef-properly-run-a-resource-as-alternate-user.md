---
layout: post
title: Chef&#58; Properly run a resource with alternate credentials (user/group)
tags: [chef,configuration_management,linux,sysadmin]
---

Chef users, more or less frequently, run a resource with alternate credentials (user/group). This is easily done by configuring the `user`/`group` property of the resource, however, this is only part of the picture.

Setting only those two attribute will, in some cases, cause the resource to run with unexpected environment values, leading to subtly broken system configurations.

In this article, I'll explain why and how to properly run a resource with alternate credentials.

Content:

- [The problem](/Chef-properly-run-a-resource-as-alternate-user#the-problem)
- [Reviewing the cause, and the issue details](/Chef-properly-run-a-resource-as-alternate-user#reviewing-the-cause-and-the-issue-details)
- [Solution](/Chef-properly-run-a-resource-as-alternate-user#solution)
- [Conclusion](/Chef-properly-run-a-resource-as-alternate-user#conclusion)

## The problem

Chef provides two common resource attributes: `user` and `group`, which, according to the manpage:

> Specify the `user`/`group` that a command will run as.

This is correct; let's write a resource to inspect it:

```ruby
execute 'test_user_switch' do
  command 'whoami'
  user    'otheruser'
  group   'otheruser'
end
```

when run, this resource will display `otheruser`.

However, let's add a requirement: that the invoked command relies on `$SHOME` to be set - some programs do (e.g. GnuPG):

```ruby
execute 'test_user_switch' do
  command 'cd && pwd'
  user    'otheruser'
  group   'otheruser'
end
```

This will cause an error!:

```
  * execute[test_user_switch] action run[2020-11-02T14:55:08+00:00] INFO: Processing execute[test_user_switch] action run (mybookbook::default line 1)

    [execute] sh: 1: cd: can't cd to /root

    ================================================================================
    Error executing action `run` on resource 'execute[test_user_switch]'
    ================================================================================
```

Why?

## Reviewing the cause, and the issue details

In Linux, switching user does _not_ automatically populate the environment. Let's check a couple of variables with a sample `sudo` command:

```sh
baseuser:$ sudo -u otheruser env | grep -P '^(USER|HOME)\b'
HOME=/home/baseuser
USER=otheruser
```

as we can see, the `USER` is switched as expected, but not HOME.

Now, let's login as `otheruser` (or switch via `sudo -iu`), then inspect the env:

```sh
otheruser:$ env

LS_COLORS=(long output...)
SSH_CONNECTION=1.2.3.4 57936 2.3.4.5 6789
LESSCLOSE=/usr/bin/lesspipe %s %s
LANG=C.UTF-8
XDG_SESSION_ID=76
USER=otheruser
PWD=/home/otheruser
HOME=/home/otheruser
SSH_CLIENT=1.2.3.4 57936 6789
XDG_DATA_DIRS=/usr/local/share:/usr/share:/var/lib/snapd/desktop
CUSTOM_ENV_VAR=my_value
SSH_TTY=/dev/pts/1
MAIL=/var/mail/otheruser
TERM=xterm-256color
SHELL=/bin/bash
SHLVL=1
LOGNAME=otheruser
XDG_RUNTIME_DIR=/run/user/1003
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
LESSOPEN=| /usr/bin/lesspipe %s
_=/usr/bin/env
```

then, the Chef attempted version:

```ruby
execute 'print_otheruser_env' do
  command 'env'
  user    'otheruser'
  group   'otheruser'
end

=begin
Output:

LS_COLORS=(long output...)
LESSCLOSE=/usr/bin/lesspipe %s %s
LANG=C.UTF-8
SUDO_GID=1001
USERNAME=root
SUDO_COMMAND=/bin/su
USER=root
PWD=/home/baseuser
HOME=/root
SUDO_USER=baseuser
SUDO_UID=1001
MAIL=/var/mail/root
SHELL=/bin/bash
TERM=xterm-256color
SHLVL=1
LOGNAME=root
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
LESSOPEN=| /usr/bin/lesspipe %s
_=/usr/bin/chef-client
=end
```

Let's review the most important variables:

| Variable       | Logged in value     | Chef-run value |
| -------------- | ------------------- | -------------- |
| HOME           | /home/otheruser     | /root          |
| LOGNAME        | otheruser           | root           |
| MAIL           | /var/mail/otheruser | /var/mail/root |
| CUSTOM_ENV_VAR | my_value            |                |
| PWD            | /home/otheruser     | /home/baseuser |
| USER           | otheruser           | root           |
| USERNAME       |                     | root           |

Those are very significant differences! By looking at this, one actually wonders how can resources work _without_ setting those values 😬.

Something notable is the variable `CUSTOM_ENV_VAR`: this is the simulation of a variable set in the `otheruser`'s `.bashrc`, and its role is to remind that it's crucial to consider additional variables, if they're required!

## Solution

Now that we know the details of the problem, in order to solidly execute a resource, we just set the required variables in the environment, via `set` property:

```ruby
execute 'correct_user_switch' do
  command 'cd && pwd'
  user    'otheruser'
  group   'otheruser'
  env({
    "HOME" => "/home/otheruser"
  })
end
```

The command will now run correctly:

```
  * execute[correct_user_switch] action run[2020-11-02T15:36:51+00:00] INFO: Processing execute[correct_user_switch] action run (mycookbook::default line 1)

    [execute] /home/otheruser
```

There isn't a predefined list of variables to set; depending on the style, some sysadmins may prefer to always set all the variables, while other ones may just set the strictly needed ones.

## Conclusion

We've investigated in detail the effects of a basic user switch, and the difference with one with a properly prepared environment. This caused quite an amount of hair pulling in the past, due to subtle interactions with the program executed, but now we know how to avoid this with ease.

Happy provisioning!
