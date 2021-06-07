---
layout: post
title: Conveniently handling non-master development/default branches in Git(/Hub)
tags: [awk,git,github,linux,quick,shell_scripting,sysadmin]
---

Those who work on many open source projects will surely find irritating to handle the different naming of the development/default branch.

In this short article, I'll show how conveniently handle it, and as usual, I'll sprinkle it with a bit of Linux tooling.

Content:

- [Conventions and general information](/Conveniently-Handling-non-master-development-default-branches-in-git-hub#conventions-and-general-information)
- [Finding the default branch](/Conveniently-Handling-non-master-development-default-branches-in-git-hub#finding-the-default-branch)
  - [Offline version](/Conveniently-Handling-non-master-development-default-branches-in-git-hub#offline-version)
  - [Online version](/Conveniently-Handling-non-master-development-default-branches-in-git-hub#online-version)
- [Integrating with git aliases](/Conveniently-Handling-non-master-development-default-branches-in-git-hub#integrating-with-git-aliases)
- [Handling repositories with a development branch that is non-default](/Conveniently-Handling-non-master-development-default-branches-in-git-hub#handling-repositories-with-a-development-branch-that-is-non-default)
- [Conclusion](/Conveniently-Handling-non-master-development-default-branches-in-git-hub#conclusion)

## Conventions and general information

I'll assume that the remote name is `origin`. If this isn't the case, just search and replace the value.

This article is based on a [StackOverflow post](https://stackoverflow.com/questions/28666357/git-how-to-get-default-branch).  
There are [edge cases](https://stackoverflow.com/questions/28666357/git-how-to-get-default-branch#comment95550167_44750379); for those, just use the manual configuration strategy (see [section below](#handling-repositories-with-a-development-branch-that-is-non-default)).

## Finding the default branch

There are two (main) ways of finding the default branch in a git repository; one offline, and one online.

### Offline version

The offline version is less safe, since it won't detect changes, and it won't handle a few edge cases, but we can still use it for the vast majority of the cases:

```sh
$ git rev-parse --abbrev-ref origin/HEAD
origin/master
```

Now, there are different approaches to extracting the branch name. The smallest and still sensible (IMO) is via awk:

```
$ git rev-parse --abbrev-ref origin/HEAD | awk -F/ '{print $NF}'
master
```

What we're doing here is very simple:

- `-F/`: sets the separator (which default to space), to `/`;
- `print $NF`: print the last token.

That was easy 😄

### Online version

For completion, this is the online version; while more robust, it's not convenient to use with aliases, due to the relatively slow speed:

```sh
$ git remote show origin
* remote origin
  Fetch URL: git@github.com:saveriomiroddi/saveriomiroddi.github.io.git
  Push  URL: git@github.com:saveriomiroddi/saveriomiroddi.github.io.git
  HEAD branch: master
  ... other information ...
```

This outputs much more information. Again, awk comes handy:

```sh
git remote show origin | awk '/^  HEAD branch:/ {print $NF}'
```

The logic here is also simple:

- We filter in the lines matching a condition, here defined by a regex (`/regex/`)
  - The line must start (`^` metacharacter) with `  HEAD branch:`
- If condition is true, evaluate the block
  - Again, we print the last token (`$NF`)

Nice!

## Integrating with git aliases

Let's say we want an alias that displays, from a branch, the commits that are not in the development branch.

Traditionally, we'd use:

```sh
$ git cherry -v --abbrev=10 master
- 47a1f20690 Boing: Add `fastrand` dependency
+ 524ed12d99 Boing: Complete Ball
+ 0d1995feb4 Boing: Complete Bat
+ 93d9cd6647 Boing: Complete Game#update()
+ 3bfa3863fc Boing: Correct misinterpreted sound playback functionality
+ 5a0935e9db Boing: Add AudioEntity trait
+ 17b5e7a9c1 Boing: Add GraphicEntity trait
+ ee9ee13bd5 Boing: Implement GraphicEntity for Ball, Bat and Impact
+ f6eeecb974 Boing: Post-implementation removals
```

However, now we can't assume the `master` name. Let's solve this.

```sh
git config --global alias.devbr "\!git rev-parse --abbrev-ref origin/HEAD | awk -F/ '{print \$NF}'"
```

This will set a global alias, `devbr`, which prints the default branch. To note:

- the `!` prefix, which tells git that this is a full shell command, rather than a git one;
- the `!` and `$NF` escaping, which is required, since the outer quotes are double ones! without escaping, those tokens will be interpreted.

Now, we can write an alias for the cherry command:

```sh
git config --global alias.chm '!git cherry -v --abbrev=10 "$(git devbr)"'
```

Done. No more fears of non-`master` branches!

```sh
$ git chm
- 47a1f20690 Boing: Add `fastrand` dependency
+ 524ed12d99 Boing: Complete Ball
+ 0d1995feb4 Boing: Complete Bat
+ 93d9cd6647 Boing: Complete Game#update()
+ 3bfa3863fc Boing: Correct misinterpreted sound playback functionality
+ 5a0935e9db Boing: Add AudioEntity trait
+ 17b5e7a9c1 Boing: Add GraphicEntity trait
+ ee9ee13bd5 Boing: Implement GraphicEntity for Ball, Bat and Impact
+ f6eeecb974 Boing: Post-implementation removals
```

## Handling repositories with a development branch that is non-default

Some repositories have a development branch different from the default one.

For example, [ggez](https://github.com/ggez/ggez) uses `devel` as development branch, and `master` as default branch.

In this case, we can just manually configure the name, and store it somewhere. Where?

Interestingly, git allows to store arbitrary configuration values. Let's use that!:

```sh
git config custom.development-branch devel
```

This will add to the repository configuration (since we didn't specify `--global`), a `custom` group, with the key/value pair `development-branch`/`devel`. See the config change:

```sh
$ tail -n 2 .git/config
[custom]
	development-branch = devel
```

The group and key names are arbitrary.

Now, in order to generalize this, we have a bit of a problem; we need to use the config value if exist, otherwise, find it. This is still easy to solve! Let's try it first:

```sh
$ git config --get custom.development-branch || git rev-parse --abbrev-ref origin/HEAD | awk -F/ '{print $NF}'
devel
```

The logic is simple; it's based on the fact that if `config --get` will not find a value, it will exit with a non-success value:

```sh
$ git config --get this.is-not-found
$ echo $?
1
```

In Bash boolean logic, this evaluates to false; since we use a disjunction ("or" boolean operator = `||`), the second command will be executed.

Let's replace the previous `devbr` alias:

```sh
$ git config --global alias.devbr "\!git config custom.development-branch || git rev-parse --abbrev-ref origin/HEAD | awk -F/ '{print \$NF}'"
```

And... there we go!:

```sh
$ git devbr
devel
```

The cool thing is that other aliases/commands relying on the `devbr` alias will now work accordingly, e.g.:

```sh
$ git checkout upstream/upgrade-glutin-oldschool-ext
HEAD is now at a42082a Heck you Windows.
$ git chm
+ efe0d12a7a Make sure window.make_current() is called.
+ bd95362714 Update graphics setting example
+ a1097816cb Rename `graphics::image` to disambiguate
+ a42082a95f Heck you Windows.
```

## Conclusion

We've used the basic, convenient functionalities of standard tools - git, awk and bash - in order to automate, cleanly, workflows that would otherwise be manual and tedious.

Although this is a trivial example, it shows the Power Of The Unix Spirit™. Enjoy fiddling with Linux tools! 😎
