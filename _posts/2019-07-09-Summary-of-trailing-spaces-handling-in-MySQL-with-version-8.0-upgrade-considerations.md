---
layout: post
title: Summary of trailing spaces handling in MySQL, with version 8.0 upgrade considerations
tags: [databases,mysql]
---

Fairly recently, we've upgraded to MySQL 8; it's been a relatively smooth transition, however, some minor differences needed to be handled. One of them is the behavior of trailing spaces.

Trailing spaces are a (not in a good way) surprising, but also widely covered argument. This article gives a short overview, and relates it to how this affects people upgrading to MySQL 8.0.

Contents:

- [Premises/Requirements](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#premisesrequirements)
- [Behavior in different contexts](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#behavior-in-different-contexts)
  - [Comparison (`=`) predicate (1)](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#comparison--predicate-1)
    - [Inspecting the collations](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#inspecting-the-collations)
  - [Comparison (`=`) predicate (2)](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#comparison--predicate-2)
  - [`LIKE` predicate](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#like-predicate)
  - [Unique indexes](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#unique-indexes)
  - [`DISTINCT` predicate](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#distinct-predicate)
  - [`GROUP BY` clause](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#group-by-clause)
- [Conclusion](/Summary-of-trailing-spaces-handling-in-MySQL-with-version-8.0-upgrade-considerations#conclusion)

## Premises/Requirements

In this article I'm going to analyze only the `VARCHAR` data type behavior, as I'd like to keep the article concise. Interested readers can find information in the links provided.

As of MySQL 8.0, `utf8` is an alias to `utf8mb3` (MySQL 5.7's underlying standard); using `utf8`/`utf8mb3` will generate warnings when running some statements on an 8.0 server, which can be ignored in the context of this article.

The reader needs to have an idea of what a [collation](https://dev.mysql.com/doc/refman/en/charset-general.html) is (in short: a set of rules for comparing strings).

The MySQL version used, and required to run the article content, is 8.0.

## Behavior in different contexts

### Comparison (`=`) predicate (1)

The comparison (`=`) predicate specification is defined independently of its context, therefore, it behaves the same both in the select list (`SELECT ...`) and the search condition (`WHERE ...`).

Let's start observing the MySQL 5.7 typical behavior:

```sql
CREATE TABLE test_comparison_ps (
  id INT PRIMARY KEY AUTO_INCREMENT,
  str VARCHAR(10) CHARSET utf8
);

INSERT INTO test_comparison_ps (str) VALUES(''), (' ');

SET NAMES utf8 COLLATE utf8_general_ci; # set the connection charset/collation

SELECT id, CONCAT('<', str, '>') `qstr`, str = '' , str = ' ' FROM test_comparison_ps;

# +----+------+----------+-----------+
# | id | qstr | str = '' | str = ' ' |
# +----+------+----------+-----------+
# |  1 | <>   |        1 |         1 |
# |  2 | < >  |        1 |         1 |
# +----+------+----------+-----------+
```

They're all equal! This matches the typical outlook that "MySQL removes all the trailing spaces".

But why so? Who's responsible?

#### Inspecting the collations

According to the SQL standard, trailing spaces are not removed on storage and retrieval. In MySQL, this is a responsibility of the storage engine, in this case InnoDB; from the related [manpage](https://dev.mysql.com/doc/refman/en/innodb-row-format.html#innodb-row-format-compact), we read:

> Trailing spaces are not truncated from VARCHAR columns.

It turns out, the responsible is the collation. In this case, `utf8_general_ci`, the default collation of the default MySQL 5.7 charset, does not pad the strings during comparison.

How do we know how comparisons behave in relateion to padding? Let's ask the information schema:

```sql
SELECT COLLATION_NAME, PAD_ATTRIBUTE FROM information_schema.collations WHERE COLLATION_NAME RLIKE 'utf8(mb4)?_(general|0900_ai)_ci';
/*
+--------------------+---------------+
| COLLATION_NAME     | PAD_ATTRIBUTE |
+--------------------+---------------+
| utf8_general_ci    | PAD SPACE     | # 5.7 default
| utf8mb4_general_ci | PAD SPACE     | # utf8mb4 default in MySQL 5.7
| utf8mb4_0900_ai_ci | NO PAD        | # 8.0 default
+--------------------+---------------+
*/
```

From the manpages [page 1](https://dev.mysql.com/doc/refman/en/charset-unicode-sets.html#charset-unicode-sets-pad-attributes) and [page 2](https://dev.mysql.com/doc/refman/en/charset-binary-collations.html#charset-binary-collations-trailing-space-comparisons):

> The pad attribute determines how trailing spaces are treated for comparison of nonbinary strings (CHAR, VARCHAR, and TEXT values):
>
> - For PAD SPACE collations, trailing spaces are insignificant in comparisons; strings are compared without regard to any trailing spaces.
> - NO PAD collations treat spaces at the end of strings like any other character.

The following are the formal rules from the SQL (2003) standard (section 8.2):

> 3) The comparison of two character strings is determined as follows:
>
> a) Let CS be the collation as determined by Subclause 9.13, “Collation determination”, for the declared
>    types of the two character strings.
>
> b) If the length in characters of X is not equal to the length in characters of Y, then the shorter string is
>    effectively replaced, for the purposes of comparison, with a copy of itself that has been extended to
>    the length of the longer string by concatenation on the right of one or more pad characters, where the
>    pad character is chosen based on CS. If CS has the NO PAD characteristic, then the pad character is
>    an implementation-dependent character different from any character in the character set of X and Y
>    that collates less than any string under CS. Otherwise, the pad character is a <space>.
>
> c) The result of the comparison of X and Y is given by the collation CS.
>
> d) Depending on the collation, two strings may compare as equal even if they are of different lengths or
>    contain different sequences of characters. When any of the operations MAX, MIN, and DISTINCT
>    reference a grouping column, and the UNION, EXCEPT, and INTERSECT operators refer to character
>    strings, the specific value selected by these operations from a set of such equal values is implementation-
>    dependent.

the crucial point is b).

### Comparison (`=`) predicate (2)

Now we can go back, and observe a different collation - `utf8mb4_0900_ai_ci`, MySQL 8.0 default:

```sql
CREATE TABLE test_comparison_np (
  id INT PRIMARY KEY AUTO_INCREMENT,
  str VARCHAR(10) CHARSET utf8mb4
);

INSERT INTO test_comparison_np (str) VALUES(''), (' ');

SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci; # behave like a standard MySQL 8.0 installation

SELECT id, CONCAT('<', str, '>') `qstr`, str = '' , str = ' ' FROM test_comparison_np;
/*
+----+------+----------+-----------+
| id | qstr | str = '' | str = ' ' |
+----+------+----------+-----------+
|  1 | <>   |        1 |         0 |
|  2 | < >  |        0 |         1 |
+----+------+----------+-----------+
*/
```

... so MySQL doesn't "remove all the trailing spaces" after all.

### `LIKE` predicate

Let's see how the `LIKE` predicate behaves:

```sql
CREATE TABLE test_like (
  id INT PRIMARY KEY AUTO_INCREMENT,
  str VARCHAR(10) CHARSET utf8
);

INSERT INTO test_like (str) VALUES(''), (' ');

SET NAMES utf8 COLLATE utf8_general_ci;

SELECT id, CONCAT('<', str, '>') `qstr`, str LIKE '' , str LIKE ' ' FROM test_like;
/*
+----+------+-------------+--------------+
| id | qstr | str LIKE '' | str LIKE ' ' |
+----+------+-------------+--------------+
|  1 | <>   |           1 |            0 |
|  2 | < >  |           0 |            1 |
+----+------+-------------+--------------+
*/
```

Yikes! `LIKE` does not perform padding, even on a `PAD SPACE` collation such as `utf8_general_ci`.

`LIKE` has some semantic differences from `=`, which are confusing (for example, when dealing with JSON), however, they're expected.

Therefore, as long as we keep in mind that `LIKE` differs from `=`, we are less likely to make mistakes.

### Unique indexes

Let's see how unique indexes behave:

```sql
CREATE TABLE test_unique_index (
  id INT PRIMARY KEY AUTO_INCREMENT,
  str_ps VARCHAR(10) CHARSET utf8 COLLATE utf8_general_ci,
  str_np VARCHAR(10) CHARSET utf8mb4 COLLATE utf8mb4_0900_ai_ci
);

INSERT INTO test_unique_index (str_ps, str_np) VALUES('', ''), (' ', ' ');

ALTER TABLE test_unique_index ADD UNIQUE (str_ps);

-- ERROR 1062 (23000): Duplicate entry '' for key 'str_ps'

ALTER TABLE test_unique_index ADD UNIQUE (str_np);

-- Query OK, 0 rows affected (0,02 sec)
```

Unique indexes behave like the comparison predicate; this makes sense, since comparison is the core operation they're associated to.

### `DISTINCT` predicate

Let's see the effects of the `DISTINCT` predicate:

```sql
CREATE TABLE test_distinct (
  id INT PRIMARY KEY AUTO_INCREMENT,
  str VARCHAR(10) CHARSET utf8
);

INSERT INTO test_distinct (str) VALUES(''), (' ');

SET NAMES utf8 COLLATE utf8_general_ci;

SELECT DISTINCT str FROM test_distinct;
/*
+------+
| str  |
+------+
|      | # ''
|      | # ' '
+------+
*/
```

Very confusing: `DISTINCT` does not perform padding.

This is something to keep in mind.

### `GROUP BY` clause

Finally, the `GROUP BY` clause:

```sql
CREATE TABLE group_by (
  id INT PRIMARY KEY AUTO_INCREMENT,
  str VARCHAR(10) CHARSET utf8
);

INSERT INTO group_by (str) VALUES(''), (' ');

SET NAMES utf8 COLLATE utf8_general_ci;

SELECT DISTINCT str FROM group_by;

/*
+------+
| str  |
+------+
|      | # ''
|      | # ' '
+------+
*/
```

Very confusing, again, although in a way, we could have expected this, since RDBMSs, in some cases, can process `DISTINCT` and `GROUP BY` the same way.

## Conclusion

All in all, the padding rules in MySQL are not *so* confusing, but one needs to be aware of them - and I haven't even explored the `CHAR` data type.

In my opinion, they're not worth the hassle, so MySQL 8.0's behavior is a very welcome simplification. Time to update the database! 😄
