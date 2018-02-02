---
layout: post
title: Git&colon; Cherry-picking a PR/merge request
tags: [git,github,gitlab]
---

GitLab offers a functionality for cherry picking a merge request (PR).

This functionality doesn't exist in GitHub, and in Git, either; it is useful in some cases.

In this article I'll explain some git fundamentals, and in the last section, how to cherry pick a PR/merge request.

Contents:

- [Disclaimer](/Git-cherry-picking-a-pr-merge-request#disclaimer)
- [What is a git merge](/Git-cherry-picking-a-pr-merge-request#what-is-a-git-merge)
- [Rebasing `onto` a new base](/Git-cherry-picking-a-pr-merge-request#rebasing-onto-a-new-base)
- [Finding the merge base](/Git-cherry-picking-a-pr-merge-request#finding-the-merge-base)
- [Cherry-picking a PR/merge request](/Git-cherry-picking-a-pr-merge-request#cherry-picking-a-prmerge-request)
- [Merging the PR](/Git-cherry-picking-a-pr-merge-request#merging-the-pr)
  - [Maintaining the PR exactly as it is](/Git-cherry-picking-a-pr-merge-request#maintaining-the-pr-exactly-as-it-is)
  - [Changing the PR branch history](/Git-cherry-picking-a-pr-merge-request#changing-the-pr-branch-history)
- [Conclusion](/Git-cherry-picking-a-pr-merge-request#conclusion)

## Disclaimer

Git offers many workflow, and there is disagreement about what is considered optimal.

The workflow(s) presented here are a sensitive subject for some. This post doesn't make any judgment: all the ideas are exposed purely for informational purposes - to be used as option, for those who deem them appropriate, or discarded, by those who don't.

## What is a git merge

In git, a merge is the act of joining together two branches, so that both of their histories will become part of the new, joined, branch.

This is an example:

```
  ╭──C─────╮     topic
  │        │
──*──A──B──*──>  master
```

In this case, after the merge, `master` will include all the commits: `B`, `B` and `C`.

There are two notable commits in the history above, both displayed as `*`:

- the merge base (on the  left): the most recent common ancestor [commit] of the two branches
- the merge commit (on the right): the commit that joins the two branches together

## Rebasing `onto` a new base

Suppose two developers are working on a branch:

```
──A────────>   master
  │
  ╰──B──C──>   dev1   (origin)
     │
     ╰──D──>   dev2   (local)
```

Developer 1 performs a force push (!) and changes the commit `B` to `B'`. This will be the new history:

```
──A─────────>   master
  │
  ├──B'──C──>   dev1   (origin)
  │
  ╰──B───D──>   dev2   (local)
```

Now we have a problem. When developer 2 will merge (or rebase) `dev1` with `dev2`, there will be a conflict; since `B` is still present in `dev2`, he will need to discard the changes of `B`, and retain the changes of `B'`.

In order to perform a conflict-free rebase, developer 2 needs to apply a different strategy, around the lines of "I'm only interested in my commit - `D` - just apply it on top of the new origin branch".

What he wants is ultimately this:

```
──A────────────>   master
  │
  ╰──B'──C─────>   dev1   (origin)
         │
         ╰──D──>   dev2   (local)
```


In git, this strategy is executed via `rebase --onto`; the format is:

```sh
$ git rebase --onto <new_base> <new_branch_parent>
```

Going back to the pre-rebase history:

```
──A─────────>   master
  │
  ├──B'──C──>   dev1   (origin)
  │
  ╰──B───D──>   dev2   (local)
```

the references are:

- new_base: `C`
- new_branch_parent: `B`, otherwise referenceable as `D~` (which means "parent of `D`")

so the command is

```sh
$ git rebase --onto C B
```

or, using a relative reference:

```sh
$ git rebase --onto C D~
```

This will yield the desired history, without conflicts:

```
──A─────────────>   master
  │
  ╰──B'──C──────>   dev1   (origin)
         │
         ╰──D'──>   dev2   (local)
```

Note how `D'` is different from `D`. The change applied will be the same, but the commit as a whole is now different, since it's parent of `C`, not parent of `B` anymore.

## Finding the merge base

A functionality very common during rebases of any type is finding the merge base.

Suppose we have a feature branch:

```
──?──B──────>   master
  │
  ╰──C───D──>   feature
```

we want to know what's the commit represented by `?`, which is the most recent common ancestor [commit] of the two branches.

The git command format is `merge-base branch1 branch2`; in this case:

```sh
git merge-base B D
```

will return `A`.

Keep this in mind for later.

## Cherry-picking a PR/merge request

What exactly do we mean with "cherry picking a PR/merge request", and why we would want that?

Let's see a case where we want to do this.

Suppose we have a `master`/`release` source control structure:

- `master` represents the *stable* history of a project development
- `release` represents the history of the releases

On our imaginary point in time, `master` is ahead of `release`, and needs to wait a certain day for being merged into `release`, and released.

A feature branch is branched from master, and it's developed and completed, and a GitHub PR is created. For external reasons, it becomes high priority, and needs to be released urgently, before the release date. This is a representative history:

```
──A──B──C────────>   master
  │     │
  │     ╰──D──E      feature (origin, PR)
  │
  ╰──────────────>   release
```

Ultimately, we want `A`, `D`, and `E` to be in the `release` branch.

Let's do the wrong thing, and merge, via command line, `feature` into `release`:

```
──A──B──C──────────>   master
  │     │
  │     ╰──D──E        feature (origin, PR)
  │            ╲
  ╰─────────────*──>   release
```

Yikes!! The `release` branch will now contain all the commits, including `B` and `C`.

This shows clearly what we want to do, and what cherry picking a merge is.

In informal terms, we want to "disconnect" a branch from mainline, and "attach" it on top of another, without carrying its previous history, in this case, `feature` on top of `release`.

More technically, we:

- find the merge base between `feature` and `master` (`C`)
- rebase `feature` onto `release`, starting from the above merge base

Lo and behold, this is our git command (with minor shell trickery), to be run from `feature`:

```sh
$ git rebase --onto release $(git merge-base master feature)
```

Note that:

- `$()` is shell syntax for running a command in a subshell, and replacing the construct with the result
- we can also use `HEAD` in place of `feature`, since we're assuming to be running from `feature`

this is the new history:

```
──A──B───C───>   master
  │
  ├──D'──E'      feature (local)
  │
  ╰──────────>   release
```

Note how, as explained before, `D` and `E` turned into `D'` and `E'`.

Now we can safely merge (via command line):

```
──A──B───C────>   master
  │
  ├──D'──E'       feature (local)
  │       ╲
  ╰────────*──>   release
```

and `release` will contain `A`, `D'` and `E'` only!

The `release` branch can now be pushed to the origin, and deployed.

## Merging the PR strategies

Now, there are a couple of things to close. How do we handle the fact that the local `feature` is now mismatching with the origin? And how do we handle master?

There are two strategies, depending on the git workflow used in the team

### Maintaining the PR exactly as it is

In this case, we delete the local `feature` branch, and merge the PR via GitHub (and delete `feature` on origin); this will be the history:

```
──A──B──C────────>   master
  │     │
  │     ╰──D──E      feature (was origin, PR)
  │
  ├──D'──E'          feature (was local)
  │       ╲
  ╰────────*─────>   release
```

A few days later, `master` has a new commit:

```
──A──B──C────F──>   master
```

On release day, we merge, yielding the final history:

```
──A──B──C────F──*─────>   master
  │     │      ╱ ╲
  │     ╰──D──E   ╲       feature (was origin, PR)
  │                ⧹
  ├──D'──E'        │      feature (was local)
  │       ╲        │
  ╰────────*───────*──>   release
```

Inevitably, we'll have both pairs `D/E` and `D'/E'` in `release`. Practically, this won't be problem, since git recognizes that the commits have already been applied to `release`.

### Changing the PR branch history

Alternatively, we force push the local `feature` branch, yielding:

```
──A──B───C────>   master
  │
  ├──D'──E'       feature (local and origin, PR)
  │       ╲
  ╰────────*──>   release
```

We merge the PR via GitHub (and delete the `feature` branch):

```
──A──B──C──*──>   master
  │       ╱
  ├──D'──E'       feature (local and origin, PR)
  │       ╲
  ╰────────*──>   release
```

Then a new commit, `F`, is added:

```
──A──B──C──*──F──>   master
```

And on release day, `master` is merged into `release`:

```
──A──B──C──*──F────>   master
  │       ╱    ╲
  ├──D'──E'     ⧹      feature (local and origin, PR)
  │       ╲     │
  ╰────────*────*──>   release
```

no more duplication, at the cost of having applied a force-push.

## Conclusion

Git is cool, but handle with care.
