---
layout: post
title: Cleaning email subject prefixes via regular expressions
tags: [regular_expressions,sysadmin]
---

Email subjects are prone to "prefix piling" (e.g. `Re: AW: Fwd: Subject`); this easily gets very annoying, requiring the user to manually edit the subject.

Some email client tools allow automated subject editing, which, with the right rules, solves the problem.

In this article I'll explain which regular expressions to use in order to solve the problem, along with the regular expression concepts required.

Content:

- [Requirements](/Cleaning-email-subject-prefixes-via-regular-expressions#requirements)
- [The problem](/Cleaning-email-subject-prefixes-via-regular-expressions#the-problem)
  - [Repetition metacharacters](/Cleaning-email-subject-prefixes-via-regular-expressions#repetition-metacharacters)
  - [Groups](/Cleaning-email-subject-prefixes-via-regular-expressions#groups)
  - [Beginning of string metacharacter](/Cleaning-email-subject-prefixes-via-regular-expressions#beginning-of-string-metacharacter)
  - [Lookarounds](/Cleaning-email-subject-prefixes-via-regular-expressions#lookarounds)
  - [Negative lookarounds](/Cleaning-email-subject-prefixes-via-regular-expressions#negative-lookarounds)
  - [The solution](/Cleaning-email-subject-prefixes-via-regular-expressions#the-solution)
  - [The null-character](/Cleaning-email-subject-prefixes-via-regular-expressions#the-null-character)
- [Conclusion](/Cleaning-email-subject-prefixes-via-regular-expressions#conclusion)

## Requirements

The regexes [regular expressions] presented are designed to be as compatible as possible (specifically, by not using lookbehind, which is not supported in all Javascript versions), and can be tested on pretty much any (mainstream) programming language.

The article assumes that the regex(es):

1. are applied after the client has added the prefix;
2. can only remove text, not replace it;
3. are applied cyclically, until there are no more changes.

The second point makes the solution more complex, but the purpose is to make the regex as compatible as possible with tools.

The double quotes around the patterns are not part of the patterns.

The regexes are not intended to cover all the corner cases (e.g. not to replace an abbreviation in the middle of a subject), but to be good enough to be used reliably.

I'll use the term "target" to refer to the part of a pattern we want to match and replace, as opposed to the other parts, which we don't want to replace.

## The problem

When users reply from systems configured with different languages, subject prefixes start to pile up; additionally, they can have uneven spacing.

Let's take as an example, a discussion between users with English and German systems:

    Re: Aw:  Re: Aw:This is the subject

### Repetition metacharacters

Let's start with two very basic regexes, and their respective result:

    Re: Aw:  Re: Aw:This is the subject

- `"Re: "` => `Aw:  Aw:This is the subject`
- `"Aw: "` => `Re:  Re: Aw:This is the subject`

We observe the first problem: the occurrences of `Aw:` are followed by an inconsistent number of spaces, respectively, two and zero.

Rather than additional regexes, we employ a so-called "metacharacter" - a character with a special function.

The star metacharacter (`*`) expresses repetition of zero or more occurrences; in this case:

    Re: Aw:  Re: Aw:This is the subject

- `"Aw: *"` => `Re: Re: This is the subject`

Excellent! Something very important to know is that metacharacters apply to the last character (or group - a concept explained in the next section), in this case, the space.

Before refining the regex further, it should be noted the existence of another metacharacter.

The plus metacharacter (`+`) expresses repetition of one or more occurrences. Let's try it:

    Re: Aw:  Re: Aw:This is the subject

- `"Aw: +"` => `Re: Re: Aw:This is the subject`

This doesn't work! Since the second `Aw:` occurrence is not followed by any space, it's not replaced.

The star and plus metacharacters are often used interchangeably. One of the most common regular expressions is indeed `.*`, which represents "any sequence, or no sequence"; in many cases, while this is a correct solution, it's not a rigorous one, as `.+` would be more rigorous, because it expresses that a sequence is always present.

### Groups

Now, we have two expressions that do the trick. Let's merge them into one!

A fundamental regex concept is "groups". Groups have several functions; the one we'll use is the logical disjunction (the OR condition).

The concept we want to express is: "either `Aw` or `Re` string, followed by a colon, and zero or more spaces":

    Re: Aw:  Re: Aw:This is the subject

- `"(Aw|Re): *"` => `This is the subject`

They're all gone! This is not what we want, because we need to preserve the first abbreviation, however, we're one step closer.

### Beginning of string metacharacter

Before building further on the existing regex, we'll need to understand another metacharacter: the "beginning of string", expressed by the the caret character (`^`).

Let's say we want to replace only the first abbreviation, and nothing else. The concept we want to express is: "the beginning of the string, followed by the abbreviation, colon, and spaces":

    Re: Aw:  Re: Aw:This is the subject

- `"^Re: *"` => `Aw:  Re: Aw:This is the subject`

You can see that only the first `Re:` has been removed, because it's at the beginning of the string.

The opposite metacharacter is the dollar (`$` character), which matches the end of the string:

    Re: Aw:  Re: Aw:This is the subject

- `"Re: *$"` => `Re: Aw:  Re: Aw:This is the subject`

Nothing is removed in this case, because there is no `Re: ` at the end of the string!

### Lookarounds

Lookaround is a very powerful functionality. It is generally confusing for beginners, but with the right guidance, it's clear.

There are two types of lookaround:

- lookbehind: expresses "match (or not) a certain pattern preceding the target"
- lookahead: expresses "match (or not) a certain pattern following the target"

The problem we have in this context is that lookbehind is not supported by all Javascript versions, so we can only use the lookahead.

Let's see how it works first. Suppose we want to remove `Aw:`, only when it's followed by `This`; let's express the concept simplistically:

    Re: Aw:  Re: Aw:This is the subject

- `"Aw:This"` => `Re: Aw:  Re:  is the subject`

Yikes! We don't want to remove the `This` - only the `Aw:`! However, since the pattern is `Aw:This`, it's entirely removed.

How do we tell the regex engine not to remove the `This`? With the lookahead!:

    Re: Aw:  Re: Aw:This is the subject

- `"Aw:(?=This)"` => `Re: Aw:  Re: This is the subject`

Hoorray! What the lookaround does is essentially, to match a certain sequence, but without (in regex terminology) "capturing" it.

For reference, the lookahead syntax is: `(?=PATTERN)`. It's definitely cryptic; there's no way around this 😳.

The opposite of the lookahead is the lookbehind, whose syntax is `(?<=PATTERN)`.

### Negative lookarounds

Lookarounds can also be used as negative match ("match a target if not preceded/followed by another pattern").

The syntax gets even more cryptic: `(?!PATTERN)` (negative lookahead) and `(?<!PATTERN)` (negative lookbehind).

Let's say we want to replace all the `Aw:` not followed by `This`:

    Re: Aw:  Re: Aw:This is the subject

- `"Aw:(?!This)"` => `Re:   Re: Aw:This is the subject`

There you go! Only the first `Aw:` is gone (ignore the spaces, in this example).

### The solution

Now we have all the pieces we need! The solution is tricky, but here it goes:

    Re: Aw:  Re: Aw:This is the subject

- `"(?!^)(Aw|Re): *"` => `Re: This is the subject`

Yay!

Everything fits, with only one oddity: we're using a negative lookahead... but ahead of what? There's nothing behind!

### The null-character

The answer is in another concept, the "null-character". In short (simplified), _before_ the beginning of the string there is a "null-character", which can be referenced by patterns.

Let's see how the `(?!^)Re: ` works in two different parts of the string.

First:

```
     Re: Aw: Re: Aw:This is the subject
    ↑
    We're here
```

We're _before_ the string starts, because we're matching the null-character.

The first part of the pattern is `?!^`; it expresses "matching a target when it's _not_ followed by the beginning of the string.

Is this location (null-character) followed by the beginning of the string? Yes! Therefore, we don't have a match.

The other part:

```
     Re: Aw: Re: Aw:This is the subject
            ↑
            We're here
```

Is this part of the string followed by the beginning of the string? No! Therefore, we follow up testing the match.

The second part of the pattern is `Re: `. Is it matching? Yes! There you go:

    Re: Aw:  Re: Aw:This is the subject

- `"(?!^)Re: "` => `Re: Aw:  Aw:This is the subject`

As you can see, we've removed only the second one.

## Conclusion

In this article I've explained all the concepts required to perform a rather sophisticated regular expression replacement, saving many precious keystrokes over a lifetime!

It's important to be aware that regexes are not meant to solve all the string problems, however, a good knowledge of regexes is a very effective tool.

Happy matching/substituting!
