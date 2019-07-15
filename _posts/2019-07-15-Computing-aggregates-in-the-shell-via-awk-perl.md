---
layout: post
title: Computing aggregates in the shell (via AWK/Perl)
tags: [awk,linux,perl,shell_scripting,text_processing]
---

Today we've had an emergency in production, which caused us to process log files.

An operation that comes very helpful in these situations is to quickly compute aggregates for values found in logs (or text files, in general).

This is possible, and actually easy, with the usual \*nix tools; in this post I'll explain three approaches to this problem.

Contents:

- [Premises](/Computing-aggregates-in-the-shell-via-awk-perl#premises)
- [The generic and flexible, but a bit clunky solution: Perl + SQLite](/Computing-aggregates-in-the-shell-via-awk-perl#the-generic-and-flexible-but-a-bit-clunky-solution-perl--sqlite)
- [The simple and elegant solution: GAWK or Perl](/Computing-aggregates-in-the-shell-via-awk-perl#the-simple-and-elegant-solution-gawk-or-perl)
- [Working around OS X](/Computing-aggregates-in-the-shell-via-awk-perl#working-around-os-x)
- [Bonus](/Computing-aggregates-in-the-shell-via-awk-perl#bonus)
- [Conclusion](/Computing-aggregates-in-the-shell-via-awk-perl#conclusion)

## Premises

We'll work on a simple file, `production.log`:

```
cat > production.log <<LOG
Sleeping.
Task 1. Completed in 520.35ms - Worker1
Task 2. Completed in 1999.77ms - Worker2
Sleeping
Task 3. Completed in 1000.27ms - Worker1
LOG
```

I've explained some Perl patterns in previous posts, so check them out if needed.

Quoting is not considered in this article, as it would complicate the examples; fortunately, in this context, log tokens rarely include quotes, and spaces are quite easy to deal with.

## The generic and flexible, but a bit clunky solution: Perl + SQLite

As a DBAdmin, one of the first things the pops into my mind is "SQL!"; as a programmer, I then think "SQLite!"; finally, as sysadmin, I think a lot of tools, among whom, "Perl! AWK!".

In general terms, it's straightforward and compact to transfer the data from a text file into a SQLite database, and process it. The attributes "straightforward and compact" are crucial, since especially under stress conditions, one doesn't want to lose focus.

Let's start from the end. We want to get this (spacing is purely for clarity):

```sql
CREATE TABLE log_values(key TEXT,value REAL);

INSERT INTO log_values VALUES ('Worker1', 520.35);
INSERT INTO log_values VALUES ('Worker2', 1999.77);
INSERT INTO log_values VALUES ('Worker1', 1000.27);

SELECT key, SUM(value) FROM log_values GROUP BY key;
```

Let's translate it into a shell script:

```sh
echo '
CREATE TABLE log_values(key TEXT, value REAL);

INSERT INTO log_values VALUES ("Worker1", 520.35);
INSERT INTO log_values VALUES ("Worker2", 1999.77);
INSERT INTO log_values VALUES ("Worker1", 1000.27);

SELECT key, SUM(value) FROM log_values GROUP BY key;
' | sqlite3
```

The notable thing here is that `sqlite3` client, when run without parameters, creates the database in-memory, which is a convenient default (assuming the workflow fits in memory), in particular, because we don't need to take care of temporary files.  
In case one wants to run on disk, just specify a filename after `sqlite3`.

If we have a look at the SQL statements, we identify three sections:

- the beginning
- the body
- the end

Let's focus on the body. In order to get the `INSERT`s from the source file, we'll use Perl:

```sh
cat production.log | perl -ne 'print "INSERT INTO log_values VALUES (\"$2\", $1)\n" if /Completed in ([0-9.]+)ms - (\w+)/'
```

In order to complete the SQL, we need to prepend `CREATE TABLE` and append `SELECT` to the output.

Let's write the full command, using Perl:

```sh
perl -ne '
  BEGIN { print "CREATE TABLE log_values(key TEXT, value REAL);" };
  print "INSERT INTO log_values VALUES (\"$2\", $1);" if /Completed in ([0-9.]+)ms - (\w+)/;
  END { print "SELECT key, SUM(value) FROM log_values GROUP BY key;" }
' production.log | sqlite3
```

That's not bad.

Formally speaking, there's some mental overhead, so this form is unsuitable for stress situations; however, there are significant advantages:

1. it's very portable, as Perl is standard;
1. we can apply any aggregate we want (anything SQL supports);
1. it can be easily scripted, as the parameters required are only the filename, the regex, and the aggregation function.

In order to make it usable in real word, one can either make it a ready snippet, or a deployed script.

The standard AWK doesn't support regex capturing groups (in this case, `([0-9.]+)` and `(\w+)`), so we dedicate separate sections to it.

## The simple and elegant solution: GAWK or Perl

When performing certain text operations, capturing groups are crucial for simplicity; the standard AWK doesn't support them, but GAWK (the GNU version) does.

The previous solution can be easily converted to pure GAWK, however, we'll try a different approach here - a strictly programmatic one.

Let's review the logic:

1. create an associative array (hash/map in other languages) of the type (key: sum);
2. for each line, extract the tokens and add the values to the array;
3. print the array.

Both AWK and Perl make this even simpler:

- we don't need to instantiate variables;
- the array values are automatically instantiated based on the operand type (eg. 0 for numeric) when the key is not present on lookup;
- we don't need to consider the data types.

I'll write both versions, then explain the core points:

```sh
gawk '
{if (match($0, /Completed in ([[:digit:].]+)ms - ([[:alnum:]]+)/, m)) totals[m[2]] += m[1]}
END {for (key in totals) {print key, totals[key]}}
' production.log

perl -ne '
$totals{$2} += $1 if /Completed in ([\d+.]+)ms - (\w+)/;
END {for $key (keys %totals) {print "$key $totals{$key}\n"}}
' production.log
```
The GAWK logic is:

- we store the capturing groups in the `m` array
  - the array is instantiated on the fly
- if there is a match, execute the block
  - `match()` returns 0 if there is no match, which AWK interprets as negative condition
- add the current total to the `totals` associative array according to the key
  - the assoc. array is instantiated on the fly according to the key
  - the value is automatically set to 0, if not present
- at the end of the input, iterate the `totals` and print them

The Perl version is very straightforward. Note that we can also use the iterator `while (($key, $value) = each(%totals))`.

The downsides are:

- GAWK
  - we need to use POSIX character classes, rather than metacharacters (ie. `\d` and `\w`)
  - GAWK is preinstalled on OS X
- Perl
  - the odd syntax (`array{key}`, `%totals`)

Both are satisfying solutions, as they are intuitive, and simple enough to be used in real-world without peeking at the web.

## Working around OS X

If, for whatever reason, we must use the standard AWK, we have a simple option - mixing it with Perl:

```sh
perl -ne 'print "$1 $2\n" if /Completed in ([\d+.]+)ms - (\w+)/' production.log | awk '{totals[$2] += $1} END {for (key in totals) {print key, totals[key]}}'
```

... we even made a oneliner!

## Bonus

In real world, we likely want to sort the results.

When using SQL(ite), just add an `ORDER BY` clause:

```sql
SELECT key, SUM(value) FROM log_values GROUP BY key ORDER BY SUM(value);
```

when scripting instead, just use the `sort` tool:

```sh
# sort [n]umeric values, using the [k]ey in the second position
gawk ... | sort -n -k 2
```

## Conclusion

(G)AWK and Perl are still formidable solutions for quick tasks: they can tackle simple and not-so-simple operations with compactness and intuitiveness.

Today's subject is in my opinion particularly handy when digging log files, especially in an emergency situation.
