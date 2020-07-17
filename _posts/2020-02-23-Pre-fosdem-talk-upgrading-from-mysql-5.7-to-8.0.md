---
layout: post
title: PreFOSDEM talk&#58; Upgrading from MySQL 5.7 to MySQL 8.0
tags: [databases,innodb,linux,mysql,shell_scripting,sysadmin]
category: mysql
---

In this post I'll expand on the subject of my MySQL pre-FOSDEM talk: what dbadmins need to know and do, when upgrading from MySQL 5.7 to 8.0.

I've already published [two]({% post_url 2019-03-25-An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset %}) [posts]({% post_url 2019-07-09-Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations %}) on two specific issues; in this article, I'll give the complete picture.

As usual, I'll use this post to introduce tooling concepts that may be useful in generic system administration.

The presentation code is hosted on a [GitHub repository](https://github.com/saveriomiroddi/prefosdem-2020-presentation) (including the [the source files](https://github.com/saveriomiroddi/prefosdem-2020-presentation/tree/master/sources) and the output slides [in PDF format](https://github.com/saveriomiroddi/prefosdem-2020-presentation/blob/master/slides/slides.pdf)), and on [Slideshare](https://www.slideshare.net/SaverioM/friends-let-real-friends-use-mysql-80).

Contents:

- [Summary of issues, and scope](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#summary-of-issues-and-scope)
- [Requirements](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#requirements)
- [The new default character set/collation: utf8mb4/utf8mb4_0900_ai_ci](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#the-new-default-character-setcollation-utf8mb4utf8mb4_0900_ai_ci)
  - [Summary](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#summary)
  - [Tooling: MySQL RLIKE](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#tooling-mysql-rlike)
  - [How the charset parameters work](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#how-the-charset-parameters-work)
  - [String, and comparison, properties](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#string-and-comparison-properties)
  - [Collation coercion, and issues `general` <> `0900_ai`](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#collation-coercion-and-issues-general--0900_ai)
    - [Comparisons utf8_general_ci column <> literals](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#comparisons-utf8_general_ci-column--literals)
    - [Comparisons utf8_general_ci column <> columns](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#comparisons-utf8_general_ci-column--columns)
    - [Summary of the migration path](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#summary-of-the-migration-path)
  - [The new collation doesn't pad anymore](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#the-new-collation-doesnt-pad-anymore)
  - [Triggers](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#triggers)
    - [Sort-of-related suggestion](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#sort-of-related-suggestion)
  - [Behavior with indexes](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#behavior-with-indexes)
  - [Consequences of the increase in (potential) size of char columns](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#consequences-of-the-increase-in-potential-size-of-char-columns)
- [Information schema statistics caching](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#information-schema-statistics-caching)
- [GROUP BY not sorted anymore by default (+tooling)](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#group-by-not-sorted-anymore-by-default-tooling)
- [Schema migration tools support](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#schema-migration-tools-support)
- [Obsolete Mac Homebrew default collation](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#obsolete-mac-homebrew-default-collation)
  - [Modify the formula, and recompile the binaries](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#modify-the-formula-and-recompile-the-binaries)
  - [Ignore the client encoding on handshake](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#ignore-the-client-encoding-on-handshake)
- [Good practice for (major/minor) upgrades: comparing the system variables](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#good-practice-for-majorminor-upgrades-comparing-the-system-variables)
- [Conclusion](/Pre-fosdem-talk-upgrading-from-mysql-5.7-to-8.0#conclusion)

## Summary of issues, and scope

The following are the basic issues to handle when migrating:

- the new charset/collation `utf8mb4`/`utf8mb4_0900_ai_ci`;
- the trailing whitespace is handled differently;
- GROUP BY is not sorted anymore by default;
- the information schema is now cached (by default);
- incompatibility with schema migration tools.

Of course, the larger the scale, the more aspects will need to be considered; for example, large-scale write-bound systems may need to handle:

- changes in dirty page cleaning parameters and design;
- (new) data dictionary contention;
- and so on.

In this article, I'll only deal with what can be reasonably considered the lowest common denominator of all the migrations.

## Requirements

All the SQL examples are executed on MySQL 8.0.

## The new default character set/collation: `utf8mb4`/`utf8mb4_0900_ai_ci`

### Summary

References:

- [An in depth DBA's guide to migrating a MySQL database from the `utf8` to the `utf8mb4` charset]({% post_url 2019-03-25-An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset %})
- [MySQL 8.0 Collations: The devil is in the details.](https://mysqlserverteam.com/mysql-8-0-collations-the-devil-is-in-the-details)
- [New collations in MySQL 8.0.0](http://mysqlserverteam.com/new-collations-in-mysql-8-0-0)


MySQL introduces a new collation - `utf8mb4_0900_ai_ci`. Why?

Basically, it's an improved version of the `general_ci` version - it supports Unicode 9.0, it irons out a few issues, and it's faster.

The collation `utf8(mb4)_general_ci` wasn't entirely correct; a typical example is `Å`:

```sql
-- Å = U+212B
SELECT "sÅverio" = "saverio" COLLATE utf8mb4_general_ci;
-- +--------+
-- | result |
-- +--------+
-- |      0 |
-- +--------+

SELECT "sÅverio" = "saverio"; -- Default (COLLATE utf8mb4_0900_ai_ci);
-- +--------+
-- | result |
-- +--------+
-- |      1 |
-- +--------+
```

From this, you can also guess what `ai_ci` means: `a`ccent `i`nsensitive/`c`ase `i`nsensitive.

So, what's the problem?

Legacy.

Technically, `utf8mb4` has been available in MySQL for a long time. At least a part of the industry started the migration long before, and publicly documented the process.

However, by that time, only `utf8mb4_general_ci` was available. Therefore, a vast amount of documentation around suggests to move to such collation.

While this is not an issue per se, is it a big issue when considering that the two collations are incompatible.

### Tooling: MySQL RLIKE

For people who like (and frequently use) them, regular expressions are a fundamental tool.

In particular when performing administration tasks (using them in an application for data matching is a different topic), they can streamline some queries, avoiding lengthy concatenations of conditions.

In particular, I find it practical as a sophisticated `SHOW <object>` supplement.

`SHOW <object>`, in MySQL, supports `LIKE`, however, it's fairly limited in functionality, for example:

```sql
SHOW GLOBAL VARIABLES LIKE 'character_set%'
-- +--------------------------+-------------------------------------------------------------------------+
-- | Variable_name            | Value                                                                   |
-- +--------------------------+-------------------------------------------------------------------------+
-- | character_set_client     | utf8mb4                                                                 |
-- | character_set_connection | utf8mb4                                                                 |
-- | character_set_database   | utf8mb4                                                                 |
-- | character_set_filesystem | binary                                                                  |
-- | character_set_results    | utf8mb4                                                                 |
-- | character_set_server     | utf8mb4                                                                 |
-- | character_set_system     | utf8                                                                    |
-- | character_sets_dir       | /home/saverio/local/mysql-8.0.19-linux-glibc2.12-x86_64/share/charsets/ |
-- +--------------------------+-------------------------------------------------------------------------+
```

Let's turbocharge it!

Let's get all the meaningful charset-related variables, but not one more, in a single swoop:

```sql
SHOW GLOBAL VARIABLES WHERE Variable_name RLIKE '^(character_set|collation)_' AND Variable_name NOT RLIKE 'system|data';
-- +--------------------------+--------------------+
-- | Variable_name            | Value              |
-- +--------------------------+--------------------+
-- | character_set_client     | utf8mb4            |
-- | character_set_connection | utf8mb4            |
-- | character_set_results    | utf8mb4            |
-- | character_set_server     | utf8mb4            |
-- | collation_connection     | utf8mb4_general_ci |
-- | collation_server         | utf8mb4_general_ci |
-- +--------------------------+--------------------+
```

Nice. The first regex reads: "string starting with (`^`) either `character_set` or `collation`", and followed by `_`. Note that if we don't group `character_set` and `collation` (via `(`...`)`), the `^` metacharacter applies only to the first.

### How the charset parameters work

Character set and collation are a _very_ big deal, because changing them in this case requires to literally (in a literal sense 😉) rebuild the entire database - all the records (and related indexes) including strings will need to be rebuilt.

In order to understand the concepts, let's have a look at the MySQL server settings again; I'll reorder and explain them.

Literals sent by the client are assumed to be in the following charset:

- `character_set_client` (default: `utf8mb4`)

after, they're converted and processed by the server, to:

- `character_set_connection` (default: `utf8mb4`)
- `collation_connection` (default: `utf8mb4_0900_ai_ci`)

The above settings are crucial, as literals are a foundation for exchanging data with the server. For example, when an ORM inserts data in a database, it creates an `INSERT` with a set of literals.

When the database system sends the results, it sends them in the following charset:

- `character_set_results` (default: `utf8mb4`)

Literals are not the only foundation. Database objects are the other side of the coin. Base defaults for database objects (e.g. the databases) use:

- `character_set_server` (default: `utf8mb4`)
- `collation_server` (default: `utf8mb4_0900_ai_ci`)

### String, and comparison, properties

Some developers would define a string as a stream of bytes; this is not _entirely_ correct.

To be exact, a string is a stream of bytes _associated to a character set_.

Now, this concept applies to strings in isolation. How about operations on sets of strings, e.g. comparisons?

In a similar way, we need another concept: the "collation".

A collation is a set of rules that defines how strings are sorted, which is required to perform comparisons.

In a database system, a collation is associated to objects and literal, both through system and specific defaults: a column, for example, will have its own collation, while a literal will use the default, if not specified.

But when comparing two strings with different collations, how is it decided which collation to use?

Enter the "Collation coercibility".

### Collation coercion, and issues `general` <> `0900_ai`

Reference: [Collation Coercibility in Expressions](https://dev.mysql.com/doc/refman/8.0/en/charset-collation-coercibility.html)

Coercibility is a property of collations, which defines the priority of collations in the context of a comparison.

MySQL has seven coercibility values:

> 0: An explicit COLLATE clause (not coercible at all)
> 1: The concatenation of two strings with different collations
> 2: The collation of a column or a stored routine parameter or local variable
> 3: A “system constant” (the string returned by functions such as USER() or VERSION())
> 4: The collation of a literal
> 5: The collation of a numeric or temporal value
> 6: NULL or an expression that is derived from NULL

it's not necessary to know them by heart, since their ordering makes sense, but it's important to know how the main ones work in the context of a migration:

- how columns will compare against literals;
- how columns will compare against each other.

What we want to know is what happens in the workflow of a migration, in particular, if we:

- start migrating the charset/collation defaults;
- then, we slowly migrate the columns.

#### Comparisons utf8_general_ci column <> literals

Let's create a table with all the related collations:

```sql
CREATE TABLE chartest (
  c3_gen CHAR(1) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci,
  c4_gen CHAR(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  c4_900 CHAR(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
);

INSERT INTO chartest VALUES('ä', 'ä', 'ä');
```

Note how we insert characters in the Basic Multilingual Plane) (`BMP`, essentially, the one supported by `utf8mb3`) - we're simulating a database where we only changed the defaults, not the data.

Let's compare with BMP `utf8mb4`:

```sql
SELECT c3_gen = 'ä' `result` FROM chartest;
-- +--------+
-- | result |
-- +--------+
-- |      1 |
-- +--------+
```

Nice; it works. Coercion values:

- column:           2  # => wins
- literal implicit: 4

More critical: we compare against a character in the Supplementary Multilingual Plane (`SMP`, essentially, one added by `utf8mb4`), with explicit collation:

```sql
SELECT c3_gen = '🍕' COLLATE utf8mb4_0900_ai_ci `result` FROM chartest;
-- +--------+
-- | result |
-- +--------+
-- |      0 |
-- +--------+
```

Coercion values:

- column:           2
- literal explicit: 0  # => wins

MySQL converts the first value and uses the explicit collation.

Most critical: compare against a character in the SMP, without implicit collation:

```sql
SELECT c3_gen = '🍕' `result` FROM chartest;
ERROR 1267 (HY000): Illegal mix of collations (utf8_general_ci,IMPLICIT) and (utf8mb4_general_ci,COERCIBLE) for operation '='
```

WAT!!

Weird?

Well, this is because:

- column:           2  # => wins
- literal implicit: 4

MySQL tries to coerce the charset/collation to the column's one, and fails!

This gives a clear indication to the migration: _do not_ allow SMP characters in the system, until the entire dataset has been migrated.

#### Comparisons utf8_general_ci column <> columns

Now, let's see what happens between columns!

```sql
SELECT COUNT(*) FROM chartest a JOIN chartest b ON a.c3_gen = b.c4_gen;
-- +----------+
-- | COUNT(*) |
-- +----------+
-- |        1 |
-- +----------+

SELECT COUNT(*) FROM chartest a JOIN chartest b ON a.c3_gen = b.c4_900;
-- +----------+
-- | COUNT(*) |
-- +----------+
-- |        1 |
-- +----------+

SELECT COUNT(*) FROM chartest a JOIN chartest b ON a.c4_gen = b.c4_900;
ERROR 1267 (HY000): Illegal mix of collations (utf8mb4_general_ci,IMPLICIT) and (utf8mb4_0900_ai_ci,IMPLICIT) for operation '='
```

Ouch. BIG OUCH!

Why?

This is what happens to people who migrated, referring to obsolete documentation, to `utf8mb4_general_ci` - they can't easily migrate to the new collation.

#### Summary of the migration path

The migration path outlined:

- update the defaults to the new charset/collation;
- don't allow SMP characters in the application;
- gradually convert the tables/columns;
- now allow everything you want 😄.

is viable for production systems.

### The new collation doesn't pad anymore

There's another unexpected property of the new collation.

Let's simulate MySQL 5.7:

```sql
-- Not exact, but close enough
--
SELECT '' = _utf8' ' COLLATE utf8_general_ci;
-- +---------------------------------------+
-- | '' = _utf8' ' COLLATE utf8_general_ci |
-- +---------------------------------------+
-- |                                     1 |
-- +---------------------------------------+
```

How does this work on MySQL 8.0?:

```sql
-- Current (8.0):
--
SELECT '' = ' ';
-- +----------+
-- | '' = ' ' |
-- +----------+
-- |        0 |
-- +----------+
```

Ouch!

Where does this behavior come from? Let's get some more info from the collations (with a regular expression, of course 😉):

```sql
SHOW COLLATION WHERE Collation RLIKE 'utf8mb4_general_ci|utf8mb4_0900_ai_ci';
-- +--------------------+---------+-----+---------+----------+---------+---------------+
-- | Collation          | Charset | Id  | Default | Compiled | Sortlen | Pad_attribute |
-- +--------------------+---------+-----+---------+----------+---------+---------------+
-- | utf8mb4_0900_ai_ci | utf8mb4 | 255 | Yes     | Yes      |       0 | NO PAD        |
-- | utf8mb4_general_ci | utf8mb4 |  45 |         | Yes      |       1 | PAD SPACE     |
-- +--------------------+---------+-----+---------+----------+---------+---------------+
```

Hmmmm 🤔. Let's have a look at the formal rules from the SQL (2003) standard (section 8.2):

> 3) The comparison of two character strings is determined as follows:
>
> a) Let CS be the collation [...]
>
> b) <u>If the length in characters of X is not equal to the length in characters of Y, then the shorter string is
>    effectively replaced, for the purposes of comparison, with a copy of itself that has been extended to
>    the length of the longer string by concatenation on the right of one or more pad characters</u>, where the
>    pad character is chosen based on CS. <u>If CS has the NO PAD characteristic, then the pad character is
>    an implementation-dependent character</u> different from any character in the character set of X and Y
>    that collates less than any string under CS. Otherwise, the pad character is a space.

In other words: the new collation does **not** pad.

This is not a big deal. Just, before migrating, trim the data, and make 100% sure that new instances are not introduced by the application before the migration is completed.

### Triggers

Triggers are fairly easy to handle, as they can be dropped/rebuilt with the new settings - just make sure to consider comparisons _inside_ the trigger body.

Sample of a trigger (edited):

```sql
SHOW CREATE TRIGGER enqueue_comments_update_instance_event\G

-- SQL Original Statement:
CREATE TRIGGER `enqueue_comments_update_instance_event`
AFTER UPDATE ON `comments`
FOR EACH ROW
trigger_body: BEGIN
  SET @changed_fields := NULL;

  IF NOT (OLD.description <=> NEW.description COLLATE utf8_bin AND CHAR_LENGTH(OLD.description) <=> CHAR_LENGTH(NEW.description)) THEN
    SET @changed_fields := CONCAT_WS(',', @changed_fields, 'description');
  END IF;

  IF @changed_fields IS NOT NULL THEN
    SET @old_values := NULL;
    SET @new_values := NULL;

    INSERT INTO instance_events(created_at, instance_type, instance_id, operation, changed_fields, old_values, new_values)
    VALUES(NOW(), 'Comment', NEW.id, 'UPDATE', @changed_fields, @old_values, @new_values);
  END IF;
END
--   character_set_client: utf8mb4
--   collation_connection: utf8mb4_0900_ai_ci
--     Database Collation: utf8mb4_0900_ai_ci
```

As you see, a trigger has associated charset/collation settings. This is because, differently from a statement, it's not sent by a client, so it needs to keep its own settings.

In the trigger above, dropping/recreating in the context of a system with the new default works, however, it's not enough - there's a comparison in the body!

Conclusion: don't forget to look inside the triggers. Or better, make sure you have a solid test suite 😉.

#### Sort-of-related suggestion

We've been long time users of MySQL triggers. They make a wonderful callback system.

When a system grows, it's increasingly hard (tipping into the unmaintainable) to maintain application-level callbacks. Triggers will _never_ miss any database update, and with a logic like the above, a queue processor can process the database changes.

### Behavior with indexes

Now that we've examined the compatibility, let's examine the performance aspect.

Indexes are still usable cross-charset, due to automatic conversion performed by MySQL. The point to be aware of is that the values are converted after being read from the index.

Let's create test tables:

```sql
CREATE TABLE indextest3 (
  c3 CHAR(1) CHARACTER SET utf8,
  KEY (c3)
);

INSERT INTO indextest3 VALUES ('a'), ('b'), ('c'), ('d'), ('e'), ('f'), ('g'), ('h'), ('i'), ('j'), ('k'), ('l'), ('m');

CREATE TABLE indextest4 (
  c4 CHAR(1) CHARACTER SET utf8mb4,
  KEY (c4)
);

INSERT INTO indextest4 SELECT * FROM indextest3;
```

Querying against a constant yields interesting results:

```sql
EXPLAIN FORMAT=TREE SELECT COUNT(*) FROM indextest4 WHERE c4 = _utf8'n'\G
-- -> Aggregate: count(0)
--     -> Filter: (indextest4.c4 = 'n')  (cost=0.35 rows=1)
--         -> Index lookup on indextest4 using c4 (c4='n')  (cost=0.35 rows=1)
```

MySQL recognizes that `n` is a valid utf8mb4 character, and matches it directly.

Against a column with index:

```sql
EXPLAIN SELECT COUNT(*) FROM indextest3 JOIN indextest4 ON c3 = c4;
-- +----+-------------+------------+------------+-------+---------------+------+---------+------+------+----------+--------------------------+
-- | id | select_type | table      | partitions | type  | possible_keys | key  | key_len | ref  | rows | filtered | Extra                    |
-- +----+-------------+------------+------------+-------+---------------+------+---------+------+------+----------+--------------------------+
-- |  1 | SIMPLE      | indextest3 | NULL       | index | NULL          | c3   | 4       | NULL |   13 |   100.00 | Using index              |
-- |  1 | SIMPLE      | indextest4 | NULL       | ref   | c4            | c4   | 5       | func |    1 |   100.00 | Using where; Using index |
-- +----+-------------+------------+------------+-------+---------------+------+---------+------+------+----------+--------------------------+

EXPLAIN FORMAT=TREE SELECT COUNT(*) FROM indextest3 JOIN indextest4 ON c3 = c4\G
--  -> Aggregate: count(0)
--     -> Nested loop inner join  (cost=6.10 rows=13)
--         -> Index scan on indextest3 using c3  (cost=1.55 rows=13)
--         -> Filter: (convert(indextest3.c3 using utf8mb4) = indextest4.c4)  (cost=0.26 rows=1)
--             -> Index lookup on indextest4 using c4 (c4=convert(indextest3.c3 using utf8mb4))  (cost=0.26 rows=1)
```

MySQL is using the index, so all good. However, what's the `func`? 

It simply tell us that the value used against the index is the result of a function. In this case, MySQL is converting the charset for us (`convert(indextest3.c3 using utf8mb4)`).

This is another crucial consideration for a migration - indexes will still be effective. Of course, (very) complex queries will need to be carefully examined, but there are the grounds for a smooth transition.

### Consequences of the increase in (potential) size of char columns

Reference: [The CHAR and VARCHAR Types](https://dev.mysql.com/doc/refman/8.0/en/char.html)

One concept to be aware of, although unlikely to hit real-world application, is that utf8mb4 characters will take up to 33% more.

In storage terms, databases need to know what's the maximum limit of the data they handle. This means that even if a string will take the same space both in `utf8mb3` and `utf8mb4`, MySQL needs to know what's the maximum space it can take.

The InnoDB index limit is 3072 bytes in MySQL 8.0; generally speaking, this is large enough not to care.

Remember!:

- `[VAR]CHAR(n)` refers to the number of characters; therefore, the maximum requirement is `4 * n` bytes, but
- `TEXT` fields refer to the number of bytes.

## Information schema statistics caching

Reference: [The INFORMATION_SCHEMA STATISTICS Table](https://dev.mysql.com/doc/refman/8.0/en/statistics-table.html)

Up to MySQL 5.7, `information_schema` statistics are updated real-time. In MySQL 8.0, statistics are cached, and updated only every 24 hours (by default).

In web applications, this affects only very specific use cases, but it's important to know if one's application is subject to this new behavior (our application was).

Let's see the effects of this:

```sql
CREATE TABLE ainc (id INT AUTO_INCREMENT PRIMARY KEY);

-- On the first query, the statistics are generated.
--
SELECT TABLE_NAME, AUTO_INCREMENT FROM information_schema.tables WHERE table_name = 'ainc';
-- +------------+----------------+
-- | TABLE_NAME | AUTO_INCREMENT |
-- +------------+----------------+
-- | ainc       |           NULL |
-- +------------+----------------+

INSERT INTO ainc VALUES ();

SELECT TABLE_NAME, AUTO_INCREMENT FROM information_schema.tables WHERE table_name = 'ainc';
-- +------------+----------------+
-- | TABLE_NAME | AUTO_INCREMENT |
-- +------------+----------------+
-- | ainc       |           NULL |
-- +------------+----------------+
```

Ouch! The cached values are returned.

How about `SHOW CREATE TABLE`?

```sql
SHOW CREATE TABLE ainc\G
-- CREATE TABLE `ainc` (
--   `id` int NOT NULL AUTO_INCREMENT,
--   PRIMARY KEY (`id`)
-- ) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

This command is always up to date.

How to update the statistics? By using `ANALYZE TABLE`:

```sql
ANALYZE TABLE ainc;

SELECT TABLE_NAME, AUTO_INCREMENT FROM information_schema.tables WHERE table_name = 'ainc';
-- +------------+----------------+
-- | TABLE_NAME | AUTO_INCREMENT |
-- +------------+----------------+
-- | ainc       |              2 |
-- +------------+----------------+
```

There you go. Let's find out the related setting:

```sql
SHOW GLOBAL VARIABLES LIKE '%stat%exp%';
-- +---------------------------------+-------+
-- | Variable_name                   | Value |
-- +---------------------------------+-------+
-- | information_schema_stats_expiry | 86400 |
-- +---------------------------------+-------+
```

Developers who absolutely need to revert to the pre-8.0 behavior can set this value to 0.

## GROUP BY not sorted anymore by default (+tooling)

Up to MySQL 5.7, `GROUP BY`'s result was sorted.

This was unnecessary - optimization-seeking developers used `ORDER BY NULL` in order to spare the sort, however, accidentally or not, some relied on it.

Those who relied on it are unfortunately required to scan the codebase. There isn't a one-size-fits-all solution, and in this case, writing an automated solution may not be worth the time of manually inspecting the occurrences, however, this doesn't prevent the Unix tools to help 😄

Let's simulate a coding standard where `ORDER BY` is always on the line after `GROUP BY`, if present:

```sh
cat > /tmp/test_groupby_1 << SQL
  GROUP BY col1
  -- ends here

  GROUP BY col2
  ORDER BY col2

  GROUP BY col3
  -- ends here

  GROUP BY col4
SQL

cat > /tmp/test_groupby_2 << SQL

  GROUP BY col5
  ORDER BY col5
SQL
```

A basic version would be a simple grep scan with `1` line `A`fter each `GROUP BY` match:

```sh
$ grep -A 1 'GROUP BY' /tmp/test_groupby_*
/tmp/test_groupby_1:  GROUP BY col1
/tmp/test_groupby_1-  -- ends here
--
/tmp/test_groupby_1:  GROUP BY col2
/tmp/test_groupby_1-  ORDER BY col2
--
/tmp/test_groupby_1:  GROUP BY col3
/tmp/test_groupby_1-  -- ends here
--
/tmp/test_groupby_1:  GROUP BY col4
--
/tmp/test_groupby_2:  GROUP BY col5
/tmp/test_groupby_2-  ORDER BY col5
```

However, with some basic scripting, we can display only the `GROUP BY`s matching the criteria:

```sh
# First, we make Perl speak english: `-MEnglish`, which enables `$ARG` (among the other things).
#
# The logic is simple: we print the current line if the previous line matched /GROUP BY/, and the
# current doesn't match /ORDER BY/; after, we store the current line as `$previous`.
#
perl -MEnglish -ne 'print "$ARGV: $previous $ARG" if $previous =~ /GROUP BY/ && !/ORDER BY/; $previous = $ARG' /tmp/test_groupby_*

# As next step, we automatically open all the files matching the criteria, in an editor:
#
# - `-l`: adds the newline automatically;
# - `$ARGV`: is the filename (which we print instead of the match);
# - `unique`: if a file has more matches, the filename will be printed more than once - with
#    `unique`, we remove duplicates; this is optional though, as editors open each file(name) only
#    once;
# - `xargs`: send the filenames as parameters to the command (in this case, `code`, from Visual Studio
#    Code).
#
perl -MEnglish -lne 'print $ARGV if $previous =~ /GROUP BY/ && !/ORDER BY/; $previous = $ARG' /tmp/test_groupby_* | uniq | xargs code
```

There is another approach: an inverted regular expression match:

```sh
# Match lines with `GROUP BY`, followed by a line _not_ matching `ORDER BY`.
# Reference: https://stackoverflow.com/a/406408.
#
grep -zP 'GROUP BY .+\n((?!ORDER BY ).)*\n' /tmp/test_groupby_*
```

This is, however, freaky, and as regular expressions in general, has a high risk of hairpulling (of course, this is up to the developer's judgement). It will be the subject of a future article, though, because I find it is a very interesting case.

## Schema migration tools incompatibility

This is an easily missed problem! Some tools may not support MySQL 8.0.

There's a known [showstopper bug](https://github.com/github/gh-ost/issues/687) on the latest Gh-ost release, which prevents operations from succeeding on MySQL 8.0.

As a workaround, one case use trigger-based tools, like [`pt-online-schema-change`](https://www.percona.com/downloads/percona-toolkit/LATEST/) v3.1.1 or v3.0.x (but **v3.1.0 is broken!**) or [Facebook's OnlineSchemaChange](https://github.com/facebookincubator/OnlineSchemaChange).

## Obsolete Mac Homebrew default collation

When MySQL is installed via Homebrew (as of January 2020), the default collation is `utf8mb4_general_ci`.

There are a couple of solution to this problem.

### Modify the formula, and recompile the binaries

A simple thing to do is to correct the Homebrew formula, and recompile the binaries.

For illustrative purposes, as part of this solution, I use the so-called "flip-flop" operator, which is something frowned upon... by people not using it 😉. As one can observe in fact, for the target use cases, it's very convenient.

```sh
# Find out the formula location
#
$ mysql_formula_filename=$(brew formula mysql)

# Out of curiosity, let's print the relevant section.
#
# Flip-flop operator (`<condition> .. <condition>`): it matches *everything* between lines matching two conditions, in this case:
#
# - start: a line matching `/args = /`;
# - end: a line matching `/\]/` (a closing square bracket, which needs to be escaped, since it's a regex metacharacter).
#
$ perl -ne 'print if /args = / .. /\]/' "$(mysql_formula_filename)"
   args = %W[
     -DFORCE_INSOURCE_BUILD=1
     -DCOMPILATION_COMMENT=Homebrew
     -DDEFAULT_CHARSET=utf8mb4
     -DDEFAULT_COLLATION=utf8mb4_general_ci
     -DINSTALL_DOCDIR=share/doc/#{name}
     -DINSTALL_INCLUDEDIR=include/mysql
     -DINSTALL_INFODIR=share/info
     -DINSTALL_MANDIR=share/man
     -DINSTALL_MYSQLSHAREDIR=share/mysql
     -DINSTALL_PLUGINDIR=lib/plugin
     -DMYSQL_DATADIR=#{datadir}
     -DSYSCONFDIR=#{etc}
     -DWITH_BOOST=boost
     -DWITH_EDITLINE=system
     -DWITH_SSL=yes
     -DWITH_PROTOBUF=system
     -DWITH_UNIT_TESTS=OFF
     -DENABLED_LOCAL_INFILE=1
     -DWITH_INNODB_MEMCACHED=ON
   ]

# Fix it!
#
$ perl -i.bak -ne 'print unless /CHARSET|COLLATION/' "$(mysql_formula_filename)"

# Now recompile and install the formula
#
$ brew install --build-from-source mysql
```

### Ignore the client encoding on handshake

An alternative solution is for the server to ignore the client encoding on handshake.

When configured this way, the server will impose on the clients the the default character set/collation.

In order to apply this solution, add `character-set-client-handshake = OFF` to the server configuration.

## Good practice for (major/minor) upgrades: comparing the system variables

A very good practice when performing (major/minor) upgrades is to compare the system variables, in order to spot differences that may have an impact.

The [MySQL Parameters website](https://mysql-params.tmtms.net) gives a visual overview of the differences between versions.

For example, the URL https://mysql-params.tmtms.net/mysqld/?vers=5.7.29,8.0.19&diff=true shows the differences between the system variables of v5.7.29 and v8.0.19.

## Conclusion

The migration to MySQL 8.0 at Ticketsolve has been one of the smoothest, historically speaking.

This is a bit of a paradox, because we never had to rewrite our entire database for an upgrade, however, with sufficient knowledge of what to expect, we didn't hit any significant bump (in particular, nothing unexpected in the optimizer department, which is usually critical).

Considering the main issues and their migration requirements:

- the new charset/collation defaults are not mandatory, and the migration can be performed ahead of time and in stages;
- the trailing whitespace just requires the data to be checked and cleaned;
- the GROUP BY clauses can be inspected and updated ahead of time;
- the information schema caching is regulated by a setting;
- Gh-ost may be missed, but in worst case, there are valid comparable tools.

the conclusion is that the preparation work can be entirely done before the upgrade, and subsequently perform it with reasonable expectations of low risk.

Happy migration 😄
