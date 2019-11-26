---
layout: post
title: There&#8217;s more than one way to skin a Perl (fun with Perl text processing)
tags: [awk,shell_scripting,perl,text_processing]
---

While researching a MySQL subject, I needed to process the MySQL server status variables (output), in order to extract and process some.

A computed value in particular (the max checkpoint age) required more elaborate processing.

This post explains a few Perl text processing functionalities (optionally aided by Awk), through many approaches to solving the problem.

Contents:

- [Input data, problem, and clarifications](/Theres-more-than-one-way-to-skin-a-perl#input-data-problem-and-clarifications)
- [The approaches](/Theres-more-than-one-way-to-skin-a-perl#the-approaches)
  - [Slurp mode, with single regex](/Theres-more-than-one-way-to-skin-a-perl#slurp-mode-with-single-regex)
  - [Slurp mode, with global match](/Theres-more-than-one-way-to-skin-a-perl#slurp-mode-with-global-match)
  - [Conditional line matching](/Theres-more-than-one-way-to-skin-a-perl#conditional-line-matching)
  - [Two-passes processing, with single-line intermediate output](/Theres-more-than-one-way-to-skin-a-perl#two-passes-processing-with-single-line-intermediate-output)
  - [Two-passes processing, with readline in the second pass](/Theres-more-than-one-way-to-skin-a-perl#two-passes-processing-with-readline-in-the-second-pass)
- [Conclusion: should cryptic (Perl) scripts be avoided in a team context?](/Theres-more-than-one-way-to-skin-a-perl#conclusion-should-cryptic-perl-scripts-be-avoided-in-a-team-context)

## Input data, problem, and clarifications

The text used is a substring of the `SHOW ENGINE InnoDB STATUS` MySQL command output:

```sh
mysql_output="\
---
LOG
---
Log sequence number          2290877017735
Log buffer assigned up to    2290877017735
Log buffer completed up to   2290877017278
Log written up to            2290877017278
Log flushed up to            2290877017278
Added dirty pages up to      2290877017278
Pages flushed up to          2290873314762
Last checkpoint at           2290873314762
199341832 log i/o's done, 37.56 log i/o's/second
"
```

In order to compute the max checkpoint age, we need to perform the subtraction `Last checkpoint at` - `Log sequence number` (on the respective values).

The requirement is that the command must be performed entirely via commandline. Dynamic languages, though, can typically execute code specified as parameter of the interpreter, so, in a way, this is not a strict requirement.

The desirable properties are:

- small number of commands;
- simple logic;
- compactness;
- as little as possible imperative logic (e.g. flow control).

Note that the regular expressions used are "rigorous enough"; for example, we assume that there is no risk that `^Log sequence number` matches two lines (the beginning of line metacharacter is even optional, but it's (arguably) a nice-to-see).

## The approaches

### Slurp mode, with single regex

This approach:

- reads the files as a single string (`-0777`);
- uses a single regex to capture the required values, via regex capturing groups;
- then performs the subtraction on the captured values.

Command:

```sh
echo "$mysql_output" | perl -0777 -ne '/^Log sequence number\s+(\d+).*^Last checkpoint at\s+(\d+)/sm && print "Checkpoint_age ".($1 - $2)."\n"'
```

All in all, this is a fairly straightforward, readable, approach.

Notes:

- the strings concatenation operator is `.`;
- in slurp mode:
  - we need to use the `s` regex modifier in order to match newlines with `.`
  - and `m` to match the beginning/end of lines with `^`/`$` - since the whole input is a single string, without this modifier, these metachars will refer to the whole input.

### Slurp mode, with global match

This approach:

- reads the files as a single string (`-0777`);
- uses a global regex, returning the capturing groups in an array;
- then performs the subtraction on the captured values.

```sh
echo "$mysql_output" | perl -0777 -ne '@v = /^(Log sequence number|Last checkpoint at)\s+(\d+)/gsm; print "Checkpoint_age ".(@v[1] - @v[3])."\n"'
```

A slightly more sophisticated approach than the previous; it simplifies the matching logic, because it defines the specification of a single line, with multiple "keys" in an disjunctive (or) condition.

Notes:

- array variables are specified with the `@` prefix;
- the regex is made global via `g` - without this, the match is performed only once (we need to match two lines, instead).

### Conditional line matching

This approach:

- sets two conditionals for the two desired lines:
  - on the first condition met, it sets a variable with the values;
  - on the second condition met, it performs the subtraction.

```sh
echo "$mysql_output" |
  perl -lane '$v = $F[3] if /^Log sequence number/; print "Checkpoint_age ".($v - $F[3]) if /^Last checkpoint at/'
```

All in all, this is a trivial and not particularly smart, but of course viable, approach.

Notes:

- the `-a` option splits the input string into the `$F` array, in a similar way to Awk's built-in variables `$<n>`, but with more flexibility.

One thing to keep in mind is that `-n` executes the statements for each line of the input. This doesn't affect our use case, but it's important to be always aware of it when applying more elaborate logic.

### Two-passes processing, with single-line intermediate output

This approach:

- preselects the lines/values, via awk/perl;
- outputs them on a single line;
- computes the result.

There are a few way to accomplish this:

```sh
echo $(echo "$mysql_output" | awk '/^(Log sequence number|Last checkpoint at)/ { print $4 }') |
  perl -lane 'print "Checkpoint_age ".($F[0] - $F[1])'

echo "$mysql_output" | awk 'BEGIN { ORS=" " }; /^(Log sequence number|Last checkpoint at)/ { print $4 }' |
  perl -lane 'print "Checkpoint_age ".($F[0] - $F[1])'

echo "$mysql_output" | perl -lane 'BEGIN { $\=" " }; /^(Log sequence number|Last checkpoint at)/ && print $F[3]' |
  perl -lane 'print "Checkpoint_age ".($F[0] - $F[1])'
```

Here we process the data in two passes.

Sometimes, when applying complex logic, performing two passes - preselection and computation - makes the overall expression much cleaner, because it avoids embedding conditionals (in the second pass, in this case).

The nice twist in this case is that we output the first pass on a single line, so that the second command doesn't need to work with multiple lines.

Notes:

- in the first version, we take advantage of the fact that when a variable has newlines, and it's not quoted, Bash will print the lines as a single string separated by spaces; this is not good practice in general, but it's an interesting use in this case;
- the `ORS` awk (special) variable stays for "Output record separator"l
- the `$\` is Perl's [Output record separator](https://perldoc.perl.org/perlvar.html#%24OUTPUT_RECORD_SEPARATOR); here the short form is used purely for the lulz, however, there are more readable equivalents: `$OUTPUT_RECORD_SEPARATOR` and `$ORS`.

### Two-passes processing, with readline in the second pass

This approach:

- preselects the lines/values, via awk/perl;
- manually reads the input lines and computes the result.

```sh
echo "$mysql_output" | awk '/^(Log sequence number|Last checkpoint at)/ { print $4 }' |
  perl -le 'print "Checkpoint_age ".(readline() - readline())'
```

Here we don't use a single-line intermediate output, so we adopt a more imperative approach. This still reads nicely, because the input is very compact (it includes only one value per line).

Notes:

- we don't make the interpreter automatically read and cycle the lines (`-n`/`-p`); instead, we manually read each via `readline()`.

## Conclusion: should cryptic (Perl) scripts be avoided in a team context?

In this post I've examined arguably cryptic scripts; conventional wisdom, however, dictates that cryptic scripts, at least in a team context, should never be used.

Should they be rejected without exception? I don't agree with this philosophy; I think there are intelligent ways of using them as building blocks of shared knowledge.

For example, in our snippets dictionary, we have:

```sh
# Aggregate the first capturing group values, keyed by the second.
perl -ne '
$totals{$2} += $1 if /Completed in ([\d+.]+)ms - (\w+)/;
END {for $key (keys %totals) {print "$key $totals{$key}\n"}}
' production.log
```

With a script like this, it's not required at all to known Perl and/or understand the script; anybody with regular expression knowledge can adjust the expression.

Of course this doesn't imply that this style is the only and/or preferable, but I think it's good to have this option, without excluding it a priori.
