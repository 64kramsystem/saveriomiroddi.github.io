---
layout: post
title: An in depth DBA's guide to migrating a MySQL database from the `utf8` to the `utf8mb4` charset
tags: [databases,mysql,sysadmin]
---

We're in the process of upgrading our MySQL databases from v5.7 to v8.0; since one of the differences in v8.0 is that the default encoding changed from `utf8` to `utf8mb4`, and we had the conversion in plan anyway, we anticipated it and performed it as preliminary step for the upgrade.

This post describes in depth the overall experience, including tooling and pitfalls, and related subjects.

Contents:

- [Introduction](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#introduction)
- [Migration plan: overview and considerations](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#migration-plan-overview-and-considerations)
  - [Free step: connection configurations](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#free-step-connection-configurations)
    - [How do charset settings affect database operations?](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#how-do-charset-settings-affect-database-operations)
  - [Step 2: Preparing the the `ALTER` statements](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#step-2-preparing-the-the-alter-statements)
    - [Issue: Column/index size limits](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#issue-columnindex-size-limits)
    - [Issue: Triggers/Functions](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#issue-triggersfunctions)
    - [Issue: Optimization problems with joins between columns with heterogeneous charsets](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#issue-optimization-problems-with-joins-between-columns-with-heterogeneous-charsets)
  - [Step 3: Altering the schema and tables](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#step-3-altering-the-schema-and-tables)
  - [Warnings](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#warnings)
    - [Other schemas](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#other-schemas)
    - [Always run `ANALYZE TABLE`](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#always-run-analyze-table)
    - [Don't rush the `DROP TABLE`](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#dont-rush-the-drop-table)
- [Notes about Mathias Bynens' post on the same subject](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#notes-about-mathias-bynens-post-on-the-same-subject)
- [Conclusion](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#conclusion)
- [Footnotes](/An-in-depth-dbas-guide-to-migrating-a-mysql-database-from-the-utf8-to-the-utf8mb4-charset#footnotes)

## Introduction

`utf8mb4` is the MySQL encoding that fully covers the UTF-8 standard. Up to MySQL 5.7, the default encoding is `utf8`; the name is somewhat misleading, as this is a variant with a maximum width of 3 bytes.

Although there's no practical purpose nowadays in using 3-bytes rather than 4-bytes UTF-8, in old MySQL version, this choice was made [for performance reasons](https://mysqlserverteam.com/mysql-8-0-when-to-use-utf8mb3-over-utf8mb4).

From a practical perspective, not all the applications will benefit from the extra byte of width, whose most common use cases include [emojis and mathematical letters](https://stackoverflow.com/questions/5567249/what-are-the-most-common-non-bmp-unicode-characters-in-actual-use), however, conforming to standards is a routine task in software engineering.

Since `utf8mb4` is a superset of `utf8`, the conversion is relatively painless, however, it's crucial to be aware of the implications of the procedure.

## Migration plan: overview and considerations

It's impossible to make a general plan, due to the different requirements of any use case; high traffic applications may for example require that no locking should be involved (ie. no `ALTER TABLE`), while low traffic/size applications may just do with a few `ALTER TABLE`s.

However, I'll trace a granular set of steps that should cover the vast majority of the cases; GitHub's gh-ost is used, therefore, there's no table locking during the data conversion step.

The setup is assumed to be single-master; there are generally sophisticated multi-master strategies for schema updates, however, they are outside the scope of this article.

The only migration constraint set is that until the end of the migration, the user should not allow 4-byte characters into the database; this will gives us the certainty that any implicit conversion performed between before the end of the migration will succeed.

Users can certainly lift this constraint, however, they must thoroughly analyze the application data flows, in order to be 100% sure that `utf8mb4` strings including 4-byte characters won't mingle with `utf8` strings, as this will cause errors.

### Free step: connection configurations

The character set [from now on abbreviated as `charset`] and collation of a given string or database object (ultimately, a column), and the operation performed, are determined by one or more settings/properties at different levels:

1. connection (set by the database client, which in turn can be set by the application framework) settings;
1. database server settings;
1. trigger settings;
1. database -> table -> column properties;

For example:

- when creating a database, the charset is defaulted to the one set in the database server configuration,
- when creating a trigger, the connection will determine the charset,

and so on.

Additionally, MySQL server attempts to use a compatible combination charset+collation for incompatible charsets, overriding the configuration/settings.

In order to view the connection and database server settings, we can use this handy query:

```sql
SHOW VARIABLES WHERE Variable_name RLIKE '^(character_set|collation)_' AND Variable_name NOT RLIKE '_(database|filesystem|system)$';
```

some settings are skipped, as they're unrelated or deprecated.

This is a table of the relevant entries, with the respective values to set:

| Setting                    | New value            | Notes                                                         | Set by `SET NAMES` |
|----------------------------|----------------------|---------------------------------------------------------------|--------------------|
| `character_set_client`     | `utf8mb4`            | data sent by the client                                       |         ✓          |
| `character_set_connection` | `utf8mb4`            | server converts client data into this charset for processing  |         ✓          |
| `collation_connection`     | `utf8mb4_general_ci` | server uses this collation for processing                     |         ✓          |
| `character_set_results`    | `utf8mb4`            | data and metadata sent by the server                          |         ✓          |
| `character_set_server`     | `utf8mb4`            | default (and fallback) charset for objects                    |                    |
| `collation_server`         | `utf8mb4_general_ci` | default (and fallback) collation for objects                  |                    |

`SET NAMES <charset>` is a MySQL command that will set all the client-related charset and collation configuration values.

Such command is also typically invoked when the encoding is configured by the application framework; in the case of Rails, we'll configure the `encoding` setting in `database.yml`:

```yml
# Typical structure
login:
  encoding: utf8mb4
  # ...
```

In Django, we add the following to `settings.py`:

```py
# Typical structure
DATABASES = {
  'default': {
    'OPTIONS': {'charset': 'utf8mb4'},
    # ...
  }
}
```

The changes above will cause the following statement to be issued on the first connection:

```sql
SET NAMES utf8mb4 # Rails also sets other variables here.
```

This step can be performed at the beginning or the end of the migration; the reason is explained in the next subsection.

#### How do charset settings affect database operations?

During the migration, with either `utf8` or `utf8mb4` connection settings, we'll find data belonging to the other charset. Is this a problem?

First, an introduction to the the [charset/collation settings](https://dev.mysql.com/doc/refman/5.7/en/charset-connection.html) is required.

Over the course of a database connection, the data (flow) is processed in several steps:

- client data sent: it's assumed to be in the format defined by `character_set_client`
- server processing: converted to the format defined by `character_set_connection` (and compared using the `character_set_connection`)
- server results: sent in the format defined by `character_set_results`

All the above settings (unless explicitly set) are set automatically, according to the `character_set_client` settings, so we can really think of all of them as a single entity.

So, the core question is: for client data in a given format (`utf8` or `utf8mb4`), will processing (comparison or storage) always succeed?

Fortunately, in our context, the answer is always yes.

When it comes to storage, the matter is pretty simple; MySQL will take care of "converting" the format. We're safe here because by using 3-byte characters, we can convert without any problem from and to the other charset.

However, in this context, strings manipulation is not only about storage - comparison is the other aspect to consider. It's time to introduce the concept of collation and the related rules.

Strings are compared according to a "collation", which defines how the data is sorted and compared. Each charset has a default collation, which in MySQL is the case-insensitive one (`utf8_general_ci` and `utf8mb4_general_ci`).

Now, when collating strings of mixed type, will the operation succeed? The answer is... no, but yes!

The reason for the no is that, unlike storage, we can't use a collation for two different charsets. However, MySQL comes to the rescue.

MySQL has a set of [coercibility rules](https://dev.mysql.com/doc/refman/5.7/en/charset-collation-coercibility.html)), which determine which collation to use in a given operation (or if an error should be raised).

The rules are quite a few, however, they're consistently defined, so they're easy to understand.

We'll see a few relevant examples, where we'll also introduce a few interesting SQL clauses:

- we define a default collation for a column;
- we use an ["introducer"](https://dev.mysql.com/doc/refman/5.7/en/charset-introducer.html) on a string literal;
- we override the default collation of a string literal.

First example:

```sql
CREATE TEMPORARY TABLE test_table (
  utf8col CHAR(1) CHARACTER SET utf8 COLLATE utf8_bin
)
SELECT _utf8'ä' `utf8col`;

SELECT utf8col < _utf8mb4'🍕' COLLATE utf8mb4_bin `result` FROM test_table;
# +--------+
# | result |
# +--------+
# |      1 |
# +--------+
```

The relevant rules are:

1. `An explicit COLLATE clause has a coercibility of 0 (not coercible at all)`
1. `The collation of a column or a stored routine parameter or local variable has a coercibility of 2`

which rule the collation as `utf8mb4_bin`. Shouldn't the `utf8col` value fail, due to being an `utf8` value, which is not handled by the winning collation?

No! MySQL will automatically convert the value, making it compatible. This is equivalent to:

```sql
SELECT _utf8mb4'ä' < _utf8mb4'🍕' COLLATE utf8mb4_bin `result` FROM test_table;
```

Second example:

```sql
SET NAMES utf8mb4;

CREATE TEMPORARY TABLE test_table (
  utf8col CHAR(1) CHARACTER SET utf8 COLLATE utf8_bin
)
SELECT _utf8'ä' `utf8col`;

SELECT utf8col < 'ë' `result` FROM test_table;
# +--------+
# | result |
# +--------+
# |      1 |
# +--------+
```

The relevant rules are:

1. `The collation of a column or a stored routine parameter or local variable has a coercibility of 2`
1. `The collation of a literal has a coercibility of 4`

The collation will be `utf8_bin`. Since `ë` can be converted, there's no problem.

Equivalent statement:

```sql
SELECT _utf8'ä' COLLATE utf8_bin < _utf8mb4'ë' `result` FROM test_table;
```

Final example:

```sql
CREATE TEMPORARY TABLE test_table (
  utf8col CHAR(1) CHARACTER SET utf8 COLLATE utf8_bin
)
SELECT _utf8'ä' `utf8col`;

SELECT utf8col < _utf8mb4'🍕' `result` FROM test_table;
ERROR 1267 (HY000): Illegal mix of collations (utf8_bin,IMPLICIT) and (utf8mb4_general_ci,COERCIBLE) for operation '<'
```

Error! What happened here?

The relevant rules and chosen collation are the same as the previous example, however, in this case, the pizza emoji (`🍕`) can't be converted to `utf8`, therefore, the operation fails.

The conclusion is that as long as we use `utf8` characters only during the migration, we'll have no problem, as the only relevant case is the second example.

### Step 2: Preparing the the `ALTER` statements

In this step we'll prepare all the `ALTER` statements that will change the schema/table metadata, and the data.

The operations are performed on a development database with the same structure as production.

First, we convert the database default charset (both production and development):

```sql
ALTER SCHEMA production_schema CHARACTER SET=utf8mb4;
```

data is not changed - only the metadata.

Then, we convert all the table charset to `utf8mb4`:

```sh
mysqldump "$updating_schema" |
  perl -ne 'print "ALTER TABLE $1 CHARACTER SET utf8mb4;\n" if /CREATE TABLE (.*) /' |
  mysql "$updating_schema"
```

again, data is not changed. This operation will cause all the columns that don't match the new charset (supposedly, all the existing character columns), to show the former (`utf8`) charset in their definition:

```sql
# before (simplified)

CREATE TABLE mytable (
  intcol INT,
  strcol CHAR(1),
  strcol2 CHAR(1)
);

# after

CREATE TEMPORARY TABLE mytable (
  intcol INT,
  strcol CHAR(1) CHARACTER SET utf8,
  strcol2 CHAR(1) CHARACTER SET utf8
) DEFAULT CHARSET=utf8mb4;
```

This allows us to write a straight conversion command:

```sh
mysqldump --no-data --skip-triggers "$updating_schema" |
  egrep '^CREATE TABLE|CHARACTER SET utf8\b' |
  perl -0777 -pe 's/(CREATE TABLE [^\n]+ \(\n)+CREATE/CREATE/g' | # remove tables without entries
  perl -0777 -pe 's/,?\n(CREATE|$)/;\n$1/g'  |                    # change comma of each last column def to semicolon (or add it)
  perl -pe 's/(CHARACTER SET utf8\b)/$1mb4/' |                    # change charset
  perl -pe 's/  `/  MODIFY `/' |                                  # add `MODIFY`
  perl -pe 's/^CREATE TABLE (.*) \(/ALTER TABLE $1/'              # convert `CREATE TABLE ... (` to `ALTER TABLE`
```

The output will consist of all the required `ALTER TABLES`, for example:

```sql
ALTER TABLE `mytable`
  MODIFY `strcol` char(1) CHARACTER SET utf8mb4 DEFAULT NULL,
  MODIFY `strcol2` char(1) CHARACTER SET utf8mb4 DEFAULT NULL;
```

#### Issue: Column/index size limits

A database engine needs to know the maximum length of the stored data, in this case, text, because the data structures are subject to limits.

In relation to the utf8 migration, the two related limits are:

- the maximum length of a character column;
- the number of prefix characters stored in an index.

In practice, something that may happen is that a table defined as such:

```sql
CREATE TABLE mytable (
  longcol varchar(21844) CHARACTER SET utf8
);
```

will cause an error when converting to utf8mb4:

```sql
ALTER TABLE mytable MODIFY longcol varchar(21844) CHARACTER SET utf8mb4;
ERROR 1074 (42000): Column length too big for column 'longcol' (max = 16383); use BLOB or TEXT instead
```

because of MySQL restriction of 65535 (2^16 - 1) bytes on the combined size of all the columns:

- utf8:    21844 * 3 = 65532
- utf8mb4: 21844 * 4 = 87376 # too much
- utf8mb4: 16383 * 4 = 65532

The same limit applies to index prefixes, although in this case there are two limits, 767 and 3072, depending on the row format and the long prefix option.

The restriction specifications can be found in the [MySQL manual](https://dev.mysql.com/doc/refman/5.7/en/innodb-restrictions.html#innodb-maximums-minimums).

If reducing the column width is not an option, the column will need to be converted to a `TEXT` data type.

Note that using very long character columns should be carefully evaluated. Advanced DBAs know the implications, however it's worth mentioning that in relation to the topic of internal temporary tables, character columns larger than 512 characters cause on-disk tables to be used; large object columns (`BLOB`/`TEXT`) don't have this problem from version 8.0.3 onwards (see [MySQL manual](https://dev.mysql.com/doc/refman/8.0/en/internal-temporary-tables.html)).  
Therefore, large object columns are suitable for a larger amount of use cases than they were in the past.

#### Issue: Triggers/Functions

Triggers and functions also require review.

Since they are executed outside the context of a connection, they carry their charset settings:

```sql
SHOW TRIGGERS\G
# [...]
# character_set_client: utf8
# collation_connection: utf8_general_ci
#   Database Collation: utf8_general_ci
```

On one hand, those properties can be executed at any point of the migration, as they act exactly as described in the [connection configurations section](#the-flexible-step-connection-configurations).

On the other hand, we need to take care of explicit `COLLATE` clauses involving columns being converted, if present.

Suppose we have this statement:

```sql
  SET @column_updated := OLD.strcol <=> NEW.strcol COLLATE utf8_bin;
```

If we migrate the column to `utf8`, as soon as the `ALTER TABLE` completes, any operation associated to the trigger (eg. `INSERT`) will **always** fail, because the `utf8_bin` collation is not compatible with the new `utf8mb4` charset.

The solution is fairly simple - the trigger needs to be dropped before the `ALTER TABLE`, and recreated after. This of course, can be a serious challenge for high-traffic websites.

#### Issue: Optimization problems with joins between columns with heterogeneous charsets

Inevitably, some tables will be converted before others; even assuming parallel conversion, it's not possible (without locking) to synchronize the end of the conversion of a set of given tables.

This creates a problem for a specific case: JOINs between columns of heterogeneous charsets - in practice, between a `utf8` column and an `utf8mb4` one.

In theory, this shouldn't be a problem in itself. Let's see what MySQL does in this case; let's create a couple of tables:

```sql
CREATE TABLE utf8_table (
  mb3col CHAR(1) CHARACTER SET utf8,
  KEY `mb3idx` (mb3col)
);

INSERT INTO utf8_table
VALUES ('a'), ('b'), ('c'), ('d'), ('e'), ('f'), ('g'), ('h'), ('i'), ('j'), ('k'), ('l'), ('m'),
       ('n'), ('o'), ('p'), ('q'), ('r'), ('s'), ('t'), ('u'), ('v'), ('w'), ('x'), ('y'), ('z');

CREATE TABLE utf8mb4_table (
  mb4col CHAR(1) CHARACTER SET utf8mb4,
  KEY `mb4idx` (mb4col)
);

INSERT INTO utf8mb4_table
VALUES ('a'), ('b'), ('c'), ('d'), ('e'), ('f'), ('g'), ('h'), ('i'), ('j'), ('k'), ('l'), ('m'),
       ('n'), ('o'), ('p'), ('q'), ('r'), ('s'), ('t'), ('u'), ('v'), ('w'), ('x'), ('y'), ('z'),
       ('🍕');
```

First, let's see what happen for simple index scans.

```sql
EXPLAIN SELECT COUNT(*) FROM utf8mb4_table WHERE mb4col = _utf8'n';
# +----+-------------+---------------+------------+------+---------------+--------+---------+-------+------+----------+-------------+
# | id | select_type | table         | partitions | type | possible_keys | key    | key_len | ref   | rows | filtered | Extra       |
# +----+-------------+---------------+------------+------+---------------+--------+---------+-------+------+----------+-------------+
# |  1 | SIMPLE      | utf8mb4_table | NULL       | ref  | mb4idx        | mb4idx | 5       | const |    1 |   100.00 | Using index |
# +----+-------------+---------------+------------+------+---------------+--------+---------+-------+------+----------+-------------+

SHOW WARNINGS\G
# [...]
# Message: /* select#1 */ select count(0) AS `COUNT(*)` from `ticketsolve_development`.`utf8mb4_table` where (`ticketsolve_development`.`utf8mb4_table`.`mb4col` = 'n')
```

Interestingly, it seems that MySQL converts the data before it reaches the optimizer; this is valuable knowledge, because with the current constraint(s), we can rely on the indexes as much as before the migration start.

What happens with JOINs? In theory, everything should be fine:

```sql
EXPLAIN SELECT COUNT(*) FROM utf8_table JOIN utf8mb4_table ON mb3col = mb4col;
# +----+-------------+---------------+------------+-------+---------------+--------+---------+------+------+----------+--------------------------+
# | id | select_type | table         | partitions | type  | possible_keys | key    | key_len | ref  | rows | filtered | Extra                    |
# +----+-------------+---------------+------------+-------+---------------+--------+---------+------+------+----------+--------------------------+
# |  1 | SIMPLE      | utf8_table    | NULL       | index | NULL          | mb3idx | 4       | NULL |   26 |   100.00 | Using index              |
# |  1 | SIMPLE      | utf8mb4_table | NULL       | ref   | mb4idx        | mb4idx | 5       | func |    1 |   100.00 | Using where; Using index |
# +----+-------------+---------------+------------+-------+---------------+--------+---------+------+------+----------+--------------------------+
```

What's `func`?

```sql
SHOW WARNINGS\G
# Message: /* select#1 */ select count(0) AS `COUNT(*)` from `ticketsolve_development`.`utf8_table` join `ticketsolve_development`.`utf8mb4_table` where (convert(`ticketsolve_development`.`utf8_table`.`mb3col` using utf8mb4) = `ticketsolve_development`.`utf8mb4_table`.`mb4col`)
```

Very interesting; we see what MySQL does in this case: it iterates `utf8_table.mb3col` (specifically, it iterates the index `mb3idx`), and for each value, it converts it to `utf8mb4`, so that it can be sought it in the `utf8mb4_table.mb4idx` index.

This works perfectly fine; unfortunately, this condition troubled the query optimizer in our production systems. Specifically, the optimizer did not use the index of the right table. The analysis follows.

Existing data structures, and the query:

```sql
CREATE TABLE b (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `lock_uuid` char(36) DEFAULT NULL CHARACTER SET utf8mb4 DEFAULT NULL,
  -- other columns and indexes
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_table_b_on_lock_uuid` (`lock_uuid`)
);

CREATE TABLE sa (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `b_id` int(11) DEFAULT NULL,
  `lock_uuid` char(36) CHARACTER SET utf8 DEFAULT NULL,
  -- other columns and indexes
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_table_sa_on_lock_uuid` (`lock_uuid`),
  KEY `index_table_sa_on_b_id` (`b_id`)
);

UPDATE b JOIN sa USING (lock_uuid)
SET sa.lock_uuid = NULL, sa.b_id = b.id --, other column updates
WHERE b.lock_uuid IN (
  '8329cedc-6b33-4789-8716-0e689f11e7e4' -- 400 UUIDs in total
);
```

These are two query explanations:

```
# Healthy
+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+----------------------------------------+-------+----------+--------------------------+
| id | select_type | table | partitions | type  | possible_keys                           | key                                     | key_len | ref                                    | rows  | filtered | Extra                    |
+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+----------------------------------------+-------+----------+--------------------------+
|  1 | SIMPLE      | b     | NULL       | range | index_table_b_on_lock_uuid              | index_table_b_on_lock_uuid              | 109     | NULL                                   |   400 |   100.00 | Using where; Using index |
|  1 | UPDATE      | sa    | NULL       | ref   | index_table_sa_on_lock_uuid             | index_table_sa_on_lock_uuid             | 109     | production_db.b.lock_uuid              | 14622 |   100.00 | NULL                     |
+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+----------------------------------------+-------+----------+--------------------------+

# Unhealthy
+----+-------------+-------+------------+-------+---------------------------------+---------------------------------+---------+------+---------+----------+--------------------------+
| id | select_type | table | partitions | type  | possible_keys                   | key                             | key_len | ref  | rows    | filtered | Extra                    |
+----+-------------+-------+------------+-------+---------------------------------+---------------------------------+---------+------+---------+----------+--------------------------+
|  1 | SIMPLE      | b     | NULL       | range | index_table_b_on_lock_uuid      | index_table_b_on_lock_uuid      | 145     | NULL |     400 |   100.00 | Using where; Using index |
|  1 | UPDATE      | sa    | NULL       | ALL   | NULL                            | NULL                            | NULL    | NULL | 1672654 |   100.00 | Using where              |
+----+-------------+-------+------------+-------+---------------------------------+---------------------------------+---------+------+---------+----------+--------------------------+
```

as you can see, the index on the right table (`sa`) is not used, requiring a full table scan for each iteration of the left table.

MySQL's behavior has also been confusing. On one instance, the queries weren't optimized for around a minute, then they started to be properly optimized; on the other instance though, the poor optimization has been stable (until we patched the app, to use a different query).

There are different approaches to this problem. `FORCE INDEX` is a very typical one:

```sql
EXPLAIN
UPDATE b JOIN sa FORCE INDEX (index_table_sa_on_lock_uuid) USING (lock_uuid)
SET sa.lock_uuid = NULL, sa.b_id = b.id --, other column updates
WHERE sa.lock_uuid IN (
  '8329cedc-6b33-4789-8716-0e689f11e7e4' -- 400 UUIDs in total
);

+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+------+---------+----------+--------------------------+
| id | select_type | table | partitions | type  | possible_keys                           | key                                     | key_len | ref  | rows    | filtered | Extra                    |
+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+------+---------+----------+--------------------------+
|  1 | UPDATE      | sa    | NULL       | range | index_table_sa_on_lock_uuid             | index_table_sa_on_lock_uuid             | 109     | NULL |     400 |   100.00 | Using where              |
|  1 | SIMPLE      | b     | NULL       | ref   | index_table_b_on_lock_uuid              | index_table_b_on_lock_uuid              | 145     | func | 3217879 |   100.00 | Using where; Using index |
+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+------+---------+----------+--------------------------+
```

the result is somewhat unexpected, as `sa` is placed by the query optimizer as left table, while the reference, healthy, query plan, would place it as right table.  
This is fine, though: the indexes are correctly used, leading to an efficient query plan.

Another alternative is to force the reversal of the tables sides via `STRAIGHT_JOIN`:

```sql
EXPLAIN
UPDATE sa
       STRAIGHT_JOIN b ON b.lock_uuid = sa.lock_uuid
SET sa.lock_uuid = NULL, sa.b_id = b.id, --, other columns updates
WHERE b.lock_uuid IN (
  '8329cedc-6b33-4789-8716-0e689f11e7e4' -- 400 UUIDs in total
);

# +----+-------------+-------+------------+------+---------------------------------+---------------------------------+---------+------+---------+----------+--------------------------+
# | id | select_type | table | partitions | type | possible_keys                   | key                             | key_len | ref  | rows    | filtered | Extra                    |
# +----+-------------+-------+------------+------+---------------------------------+---------------------------------+---------+------+---------+----------+--------------------------+
# |  1 | UPDATE      | sa    | NULL       | ALL  | NULL                            | NULL                            | NULL    | NULL | 1672654 |   100.00 | NULL                     |
# |  1 | SIMPLE      | b     | NULL       | ref  | index_table_b_on_lock_uuid      | index_table_b_on_lock_uuid      | 145     | func | 2776589 |   100.00 | Using where; Using index |
# +----+-------------+-------+------------+------+---------------------------------+---------------------------------+---------+------+---------+----------+--------------------------+
```

this was mostly an experiment, to see how MySQL would react. The query plan is indeed better - considerably - than the unhealthy one, as the index on right table is used; however, a full table scan is performed on the left table, which is quite suboptimal, although, again, not catastrophically so.

Another experiment was to force the expected charset conversion:

```sql
EXPLAIN
UPDATE sa
       JOIN b ON sa.lock_uuid = CONVERT(b.lock_uuid USING utf8)
SET sa.lock_uuid = NULL, sa.b_id = b.id, --, other columns updates
WHERE b.lock_uuid IN (
  '8329cedc-6b33-4789-8716-0e689f11e7e4' -- 400 UUIDs in total
);

+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+------+--------+----------+-------------+
| id | select_type | table | partitions | type  | possible_keys                           | key                                     | key_len | ref  | rows   | filtered | Extra       |
+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+------+--------+----------+-------------+
|  1 | SIMPLE      | b     | NULL       | range | index_table_b_on_lock_uuid              | index_table_b_on_lock_uuid              | 145     | NULL |    400 |   100.00 | Using where |
|  1 | UPDATE      | sa    | NULL       | ref   | index_table_sa_on_lock_uuid             | index_table_sa_on_lock_uuid             | 109     | func | 451013 |   100.00 | Using where |
+----+-------------+-------+------------+-------+-----------------------------------------+-----------------------------------------+---------+------+--------+----------+-------------+
```

this worked as well; the query plan is equal to the healthy one, although the optimizer has difficulties predicting the number of rows matching in the right table index.

It's not 100% clear at this stage what caused the problem - the accident involved specific conditions and a certain load, which we couldn't reproduce exactly.

There are a few theories (the experiments are tests themselves), however, none of them would give an exact explanation; causes that likely concurred are:

- data (charset/type) conversion in JOINs (`func` ref) makes difficult (or impossible) for the optimizer to estimate the right table matching rows;
- the particular data distribution of the columns: a few non-NULL values in between millions of NULL values; this is formally a high cardinality, but it proved problematic in out experience already, possibly because the InnoDB random dives may not find the non-NULL values[1](#footnote01);
- queries sneaking in between the end of a data table conversion and the ANALYZE TABLE execution.

This section does not intend to suggest a specific strategy; rather, the takeaway if an app performs JOINs in cross-charset conditions, the queries will need to be reworked and tested extremely carefully.

### Step 3: Altering the schema and tables

Now we can proceed to alter the production schema.

The schema encoding can be changed without any worry, as it's not a locking operation (up to v5.7, database properties are stored in a separate file, `db.opt`).

The table changes are the "big deal": we need to perform them without locking, and with an awareness of the implications.

In order to avoid table locking, we use [gh-ost](https://github.com/github/gh-ost), which is easy to use and well-documented.

Generally speaking, each `ALTER TABLE` of the list generated in [the previous step](#step-2-preparing-the-the-alter-statements) must be converted to a `gh-ost` command and executed.

For example, this DDL statement:

```sql
ALTER TABLE `mytable`
  MODIFY `strcol` char(1) CHARACTER SET utf8mb4 DEFAULT NULL,
  MODIFY `strcol2` char(1) CHARACTER SET utf8mb4 DEFAULT NULL;
```

needs to be performed as [simplified form]:

```sh
gh-ost --database="$production_schema" --table="mytable" --alter="
  CHARACTER SET utf8mb4,
  MODIFY `strcol` char(1) CHARACTER SET utf8mb4 DEFAULT NULL,
  MODIFY `strcol2` char(1) CHARACTER SET utf8mb4 DEFAULT NULL
"
```

This is a fairly simple procedure. Don't forget to run `ANALYZE TABLE` on each table after it's been rebuilt.

The problem that some users will have is triggers; gh-ost doesn't support tables with triggers, so an alternative procedure needs to be applied by high-traffic websites using this functionality.

### Warnings

Little gotchas to be aware of!

#### Other schemas

Don't forget to convert the other schemas as well!

In particular, if you're on AWS, the schema `tmp` will need to be converted. Forgetting to do so may cause errors if this database is used for temporary data operations that involve the main production database.

#### Always run `ANALYZE TABLE`

It's crucial to always run an `ANALYZE TABLE` for each table rebuilt. Gh-ost builds tables via successive insert, and it's good (MySQL) DBA practice to:

> run ANALYZE TABLE after loading substantial data into an InnoDB table, or creating a new index for one

See the [MySQL manual](https://dev.mysql.com/doc/refman/5.7/en/analyze-table.html) for more informations.

#### Don't rush the `DROP TABLE`

Gh-ost doesn't delete the old table after replacing it - it only renames it. Be very careful when deleting it; a straight `DROP TABLE` may flood the server with I/O.

Internally, we have a script for dropping large tables that first drops the indexes one by one, then deletes the records in chunks, and only at the end drops the (now empty) table.

## Notes about Mathias Bynens' post on the same subject

There's [a popular post about the same subject](https://mathiasbynens.be/notes/mysql-utf8mb4#utf8-to-utf8mb4), by a V8 developer (Mathias Bynens).

A couple of concepts are worth considering:

> \# For each table<br>
> REPAIR TABLE table_name;<br>
> OPTIMIZE TABLE table_name;

From this, it can be deduced that the author uses MyISAM, as InnoDB doesn't support `REPAIR TABLE` (see the [MySQL manual](https://dev.mysql.com/doc/refman/5.7/en/repair-table.html)).

> make sure to repair and optimize all databases and tables [...] ran into some weird bugs where UPDATE statements didn’t have any effect, even though no errors were thrown

this is very likely a bug, and based on the previous point, it may be MyISAM related (or related to `ALTER TABLE`). MyISAM has been essentially abandoned for a long time, and we've experienced buggy behaviors as well (although not in the context of charsets), so it wouldn't be a surprise; the post is also very old (2012).

We're entirely on InnoDB, and we didn't experience any issue when changing the charset via `ALTER TABLE` (small tables in our model have been done this way). It's also worth considering that gh-ost alters tables by creating an empty table and slowly filling it, which is different from issuing an `ALTER TABLE`.

If somebody still wanted to do a rebuild of the table, note that `OPTIMIZE TABLE` performs a full rebuild followed by `ANALYZE TABLE`, so it's not required to run the latter statement separately.

## Conclusion

Considering that migrating a database to `utf8mb4` implies literally rebuilding the entire database's data, it's been a ride with relatively few bumps.

The core issue is handling JOINs between columns being migrated; it may not be a trivial matter, but it's possible to get deterministic behavior with a thorough analysis.

Projects planning to move to MySQL 8.0 are encouraged to perform this step ahead, to shift as many possible changes related to the upgrade ahead of the upgrade itself.

All in all, migrating to `utf8mb4` is a very significant change, but knowing where to look at, it's possible to perform it smoothly.

## Footnotes

<a name="footnote01">¹</a> Very likely, partial indexes are a fit solution to this problem, but they're not supported by MySQL.
