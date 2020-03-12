---
layout: post
title: An introduction to Functional indexes in MySQL 8.0, and their gotchas
tags: [databases,indexes,mysql]
last_modified_at: 2020-03-12 12:33:00
---

Another interesting feature released with MySQL 8.0 is full support for functional indexes.

Although this is not a strictly new concept in the MySQL world (indexed generated columns provided the same functionality), I find it worth reviewing, through some applications, notes and considerations.

All in all, I'm not 100% bought into functional indexes (as opposed to indexed generated columns); I'll elaborate on this over the course of the article.

As a natural fit, generated columns are included in the article; additionally, some constructs are built on top of [my previous article]({% post_url _posts/2020-03-09-Generating-sequences-ranges-via-mysql-8.0-ctes %}), in relation to the subject of CTEs.

*Updated on 12/Mar/2020: Found another bug.*

Contents:

- [Terminology](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#terminology)
- [Generated columns, and their application on JSON data](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#generated-columns-and-their-application-on-json-data)
- [Functional indexes](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#functional-indexes)
- [JSON functional index gotchas](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#json-functional-index-gotchas)
  - [Expression exactness](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#expression-exactness)
  - [Inconsistent behavior between generated columns with index, and functional indexes](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#inconsistent-behavior-between-generated-columns-with-index-and-functional-indexes)
  - [Encoding inconsistency based on the index usage](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#encoding-inconsistency-based-on-the-index-usage)
- [An example of functional index with dates](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#an-example-of-functional-index-with-dates)
  - [Gotcha: JOINs don't use functional key parts](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#gotcha-joins-dont-use-functional-key-parts)
- [Bugs](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#bugs)
  - [Bug on `CREATE TABLE ... SELECT`](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#bug-on-create-table--select)
  - [Bug on `LOAD DATA INFILE`](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#bug-on-load-data-infile)
- [Conclusion](/An-introduction-to-functional-indexes-in-mysql-8.0-and-their-gotchas#conclusion)

## Terminology

In this article I'll use the term "Functional index" to the refer to indexes both with (8.0) and without (5.7) underlying generated columns.

Where I need to refer to the 8.0 version, I'll use the term "Functional key part" (even if it may not be entirely appropriate).

## Generated columns, and their application on JSON data

Before explaining the functional indexes, I'll give a brief introduction to generated columns, since the latter are built on top of the former.

A generated column is a column whose content is a function of another column.

Virtual generated columns - the default type - take no storage; the alternative type, "stored", actually store the data. In this article I'll refer exclusively to the virtual ones.

The syntax is simple: in the most minimal form, the definition is `<column_name> <data_type> AS (<function>)`.

This is a sample table:

```sql
CREATE TEMPORARY TABLE t_generated_column
(
  id               INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  parameters       JSON NOT NULL,
  parameter_serial CHAR(4) AS (parameters ->> '$.serial')
);

INSERT INTO t_generated_column (parameters)
VALUES
  ('{"serial": "foo0", "reserved": true}'),
  ('{"serial": "bar1", "reserved": false}'),
  ('{"serial": "baz2", "reserved": false}');
```

There are a few interesting concepts here.

First, the fact that a JSON column is used to store documents; we're using MySQL as rudimentary document storage.  
This is an interesting use case for generated columns (and likely, the original driver). On a complex enough application, at some point documents may be stored; if their usage is not sophisticated enough to require an external storage engine, MySQL can act as good enough tool for the job, in order to keep the system architecture as simple as possible.

The way the generated columns are defined, and work, is simple. In this case, the operator [`->>` (JSON inline path)](https://dev.mysql.com/doc/refman/5.7/en/json-search-functions.html#operator_json-inline-path) is used, which is a shorthand for `JSON_UNQUOTE(JSON_EXTRACT())`. By default, `JSON_EXTRACT` includes quotes in the result (for strings), which we don't require (in this context).

Finally, we can't specify a `NOT NULL` constraint on the generated column - attempting to do so will return a syntax error.

Let's have at look at how the data looks on `SELECT`ion:

```sql
SELECT * FROM t_generated_column;

-- +----+---------------------------------------+------------------+
-- | id | parameters                            | parameter_serial |
-- +----+---------------------------------------+------------------+
-- |  1 | {"serial": "foo0", "reserved": true}  | foo0             |
-- |  2 | {"serial": "bar1", "reserved": false} | bar1             |
-- |  3 | {"serial": "baz2", "reserved": false} | baz2             |
-- +----+---------------------------------------+------------------+
```

Nice!

## Functional indexes

Storing the data with the intention of unindexed access has definitely use cases, however, in applications where a significant part of the access to this data is performed at the DB layer, indexing will be crucial.

Generated columns can be indexed as any other column - in MySQL 5.7, this was the only way to build a functional index.

This is the previous table, with the index added and sample data:

```sql
CREATE TEMPORARY TABLE t_indexed_generated_column
(
  id               INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  parameters       JSON NOT NULL,
  parameter_serial CHAR(4) AS (parameters ->> '$.serial'),
  KEY (parameter_serial)
)
WITH RECURSIVE counter (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM counter WHERE n + 1 < 100000
)
SELECT /*+ SET_VAR(cte_max_recursion_depth = 1M) */
  CONCAT('{"serial": "', HEX(RANDOM_BYTES(2)), '"}') `parameters`
FROM counter;

ANALYZE TABLE t_indexed_generated_column;
```

Now we have a mean to address the JSON document via index (of course, limited to the specific field):

```sql
EXPLAIN FORMAT=TREE SELECT COUNT(*) FROM t_indexed_generated_column WHERE parameter_serial = 'CAFE';

-- -> Aggregate: count(0)
--     -> Index lookup on t_indexed_generated_column using parameter_serial (parameter_serial='CAFE')  (cost=1.10 rows=1)
```

The functionality above applies also to MySQL versions prior to 8.0, however, the latest version lifted a restriction: the backing generated column is not required anymore. A specific name is also given: "Functional key parts", because indexes can now be composed of both functions and column references.

Behind the scenes, there's nothing really new; appropriately, the engineers recycled the existing functionality, so that a functional indexes are backed by a hidden generated column.

Let's create the table without the generated column, and fill it with random strings:

```sql
CREATE TEMPORARY TABLE t_functional_index
(
  id         INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  parameters JSON NOT NULL,
  KEY ( (CAST(parameters ->> '$.serial' AS CHAR(4))) )
);

INSERT INTO t_functional_index (parameters)
WITH RECURSIVE counter (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM counter WHERE n + 1 < 100000
)
SELECT /*+ SET_VAR(cte_max_recursion_depth = 1M) */
  CONCAT('{"serial": "', HEX(RANDOM_BYTES(2)), '"}') `parameters`
FROM counter;

ANALYZE TABLE t_functional_index;
```

The syntax is conceptually the same as generated columns - the function is wrapped by round brackets (the surrounding spaces are cosmetic).

Note that in this case, we must `CAST` the extracted value to `CHAR`, because we `Cannot create a functional index on an expression that returns a BLOB or TEXT`: the implicit function `JSON_UNQUOTE` return type is `LONGTEXT`.  
We're also hitting a limitation of functional indexes - while with normal indexes we could specify an index prefix (thus, converting the `LONGTEXT` into a `(VAR)CHAR`), this is not possible with functional indexes.

Now let's test the index:

```sql
EXPLAIN FORMAT=TREE SELECT COUNT(*) FROM t_functional_index WHERE parameters ->> '$.serial' = 'CAFE';

-- -> Aggregate: count(0)
--     -> Filter: (json_unquote(json_extract(t_functional_index.parameters,'$.serial')) = 'CAFE')  (cost=10384.20 rows=100312)
--         -> Table scan on t_functional_index  (cost=10384.20 rows=100312)
```

Nuts! A table scan. What happened?

## JSON functional index gotchas

I'll summarize here a few gotchas with JSON functional indexes. While the expression exactness is obvious, the other two aren't [so much 😉].

### Expression exactness

When using functional indexes, the match condition must be exact, in order for the index to be used. This is because MySQL needs to evaluates expressions in a general form, and, although some expressions can certainly be transformed (and some actually are, by the optimizer), a sensible design choice is to shift the burden to the developer, in some cases, including this one.

Let's use a condition with the same function as the index definition:

```sql
EXPLAIN FORMAT=TREE SELECT COUNT(*) FROM t_functional_index WHERE CAST(parameters ->> '$.serial' AS CHAR(4)) = 'CAFE';

-- -> Aggregate: count(0)
--    -> Index lookup on t_functional_index using functional_index (cast(json_unquote(json_extract(t_functional_index.parameters,_utf8mb4'$.serial')) as char(4) charset utf8mb4)='CAFE')  (cost=1.10 rows=1)
```

Even a minor change will make the optimizer discard the index:

```sql
EXPLAIN FORMAT=TREE SELECT COUNT(*) FROM t_functional_index WHERE CAST(parameters ->> '$.serial' AS CHAR(5)) = 'CAFE';

-- -> Aggregate: count(0)
--     -> Filter: (cast(json_unquote(json_extract(t_functional_index.parameters,'$.serial')) as char(5) charset utf8mb4) = 'CAFE')  (cost=10384.20 rows=100312)
--         -> Table scan on t_functional_index  (cost=10384.20 rows=100312)
```

### Inconsistent behavior between generated columns with index, and functional indexes

Interestingly, if we use the form generated column with index, in place of the functional index, the index _will_ be used:

```sql
EXPLAIN FORMAT=TREE SELECT COUNT(*) FROM t_indexed_generated_column WHERE parameters ->> '$.serial' = 'CAFE';

-- -> Aggregate: count(0)
--     -> Index lookup on t_indexed_generated_column using parameter_serial (parameter_serial='CAFE')  (cost=1.10 rows=1)
```
there is an inconsistency between a functional index and its generated column and index equivalent.

Let's review the table definitions:

```sql
CREATE TEMPORARY TABLE t_indexed_generated_column
(
  id                 INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  parameters         JSON NOT NULL,
  parameter_serial   CHAR(4) AS (parameters ->> '$.serial'),
  KEY (parameter_serial)
);

CREATE TEMPORARY TABLE t_functional_index
(
  id         INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  parameters JSON NOT NULL,
  KEY ( (CAST(parameters ->> '$.serial' AS CHAR(4))) )
);
```

There is no obvious reason for the optimizer not to use the functional index; it would definitely benefit from this improvement, in order for functional indexes to be a solid choice.

### Encoding inconsistency based on the index usage

The combination of the `CAST` and `JSON_UNQUOTE` required in the context of functional indexes/generated columns has also another unintended effect: different results, based on the collation chosen by the query structure.

Let's create a table with a generated column and an index:

```sql
CREATE TEMPORARY TABLE t_encoding_test
(
  id                INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  parameters        JSON NOT NULL,
  parameters_serial CHAR(4) AS (CAST(parameters ->> '$.serial' AS CHAR(4))),
  KEY (parameters_serial)
)
SELECT '{"serial": "CAFE"}' `parameters`;
```

If a query uses the index indirectly (here we query on `parameters`, but the optimizer automatically uses the index on `parameters_serial`), we get a case insensitive search:

```sql
SELECT COUNT(*) FROM t_encoding_test WHERE parameters ->> '$.serial' = 'CAFe';

-- +----------+
-- | COUNT(*) |
-- +----------+
-- |        1 |
-- +----------+
```

this happens because the `CAST` function used to build the index, is associated to the system collation, which is case insensitive (by default, `utf8mb4_0900_ai_ci`).

However, if the index is not used:

```sql
SELECT COUNT(*) FROM t_encoding_test USE INDEX () WHERE parameters ->> '$.serial' = 'CAFe';

-- +----------+
-- | COUNT(*) |
-- +----------+
-- |        0 |
-- +----------+
```

the record is not matched! This is because the `->>` operator uses `JSON_UNQUOTE`, whose hardcoded collation is `utf8mb4_bin`, which is case insensitive.

For more details, see the MySQL [manpage](https://dev.mysql.com/doc/refman/8.0/en/create-index.html#create-index-functional-key-parts) or even the [worklog](https://dev.mysql.com/worklog/task/?id=1075#Usage_of_CAST_in_functional_index).

## An example of functional index with dates

Let's take another example, and test the index:

```sql
CREATE TEMPORARY TABLE date_functional_index
(
  id         INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  created_at DATETIME NOT NULL,
  INDEX ( (DATE(created_at)) )
);

INSERT INTO date_functional_index (created_at)
WITH RECURSIVE sequence (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM sequence WHERE n + 1 < 100000
)
SELECT /*+ SET_VAR(cte_max_recursion_depth = 100K) */
  NOW() - INTERVAL (90 * RAND()) DAY `created_at`
FROM sequence;

ANALYZE TABLE date_functional_index;
```

(There are two issues in relation to this test; the details are given below)

Let's test the index access:

```sql
EXPLAIN FORMAT=TREE SELECT COUNT(*) FROM date_functional_index WHERE DATE(created_at) = CURDATE();

-- -> Aggregate: count(0)
--     -> Index lookup on date_functional_index using functional_index (cast(date_functional_index.created_at as date)=curdate())  (cost=668.80 rows=608)
```

Works as expected; with this data type, we don't need to deal with BLOBs and/or collations.

### Gotcha: JOINs don't use functional key parts

How about joins?

```sql
EXPLAIN FORMAT=TREE
WITH RECURSIVE dates_range (d) AS
(
  SELECT CURDATE() - INTERVAL 90 DAY
  UNION ALL
  SELECT d + INTERVAL 1 DAY FROM dates_range WHERE d + INTERVAL 1 day <= CURDATE()
)
SELECT d, COUNT(id)
FROM
  dates_range
  LEFT JOIN date_functional_index ON d = DATE(created_at)
GROUP BY d;

-- -> Table scan on <temporary>
--     -> Aggregate using temporary table
--         -> Nested loop left join
--             -> Table scan on dates_range
--                 -> [...]
--             -> Filter: (dates_range.d = cast(date_functional_index.created_at as date))  (cost=3429.97 rows=100649)
--                 -> Table scan on date_functional_index  (cost=3429.97 rows=100649)
```

Ouch! The index is not used; this is definitely something that needs to be considered.

Indexes on generated columns exhibit the same behavior, however, we can perform the join against the generated column, whose index is then used by the optimizer:

```sql
CREATE TEMPORARY TABLE date_generated_column_functional_index
(
  id              INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  created_at      DATETIME NOT NULL,
  created_at_date DATE AS (DATE(created_at)),
  INDEX (created_at_date)
)
WITH RECURSIVE sequence (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM sequence WHERE n + 1 < 100000
)
SELECT /*+ SET_VAR(cte_max_recursion_depth = 100K) */
  NOW() - INTERVAL (90 * RAND()) DAY `created_at`
FROM sequence;

ANALYZE TABLE date_generated_column_functional_index;

EXPLAIN FORMAT=TREE
WITH RECURSIVE dates_range (d) AS
(
  SELECT CURDATE() - INTERVAL 90 DAY
  UNION ALL
  SELECT d + INTERVAL 1 DAY FROM dates_range WHERE d + INTERVAL 1 day <= CURDATE()
)
SELECT d, COUNT(id)
FROM
  dates_range
  LEFT JOIN date_generated_column_functional_index ON d = created_at_date
GROUP BY d;

-- -> Table scan on <temporary>
--     -> Aggregate using temporary table
--         -> Nested loop left join
--             -> Table scan on dates_range
--                 -> [...]
--             -> Index lookup on date_generated_column_functional_index using created_at_date (created_at_date=dates_range.d)  (cost=36.18 rows=1026)
```

Therefore, it's not possible to use functional key parts with JOINs at all, while it's possible with indexed generated columns. This makes functional key parts less appealing, when considering the overall design.

I've filed this as [feature request](https://bugs.mysql.com/bug.php?id=98937).

## Bugs

### Bug on `CREATE TABLE ... SELECT`

In some of the previous queries I've used `CREATE TABLE` + `INSERT` instead of `CREATE TABLE ... SELECT`. Why?

Because of a bug:

```sql
CREATE TEMPORARY TABLE bug_functional_index (
  sold_on DATETIME NOT NULL,
  INDEX sold_on_date ((DATE(sold_on)))
)
SELECT NOW() `sold_on`;

-- ERROR 3105 (HY000): The value specified for generated column '3351ae78dcbae4f473d53aebdc350681' in table 'bug_functional_index' is not allowed.
```

the above should work, considering split form works ok:

```sql
CREATE TEMPORARY TABLE bug_functional_index (
  sold_on DATETIME NOT NULL,
  INDEX sold_on_date ((DATE(sold_on)))
);

INSERT INTO bug_functional_index VALUES (NOW());

-- Query OK, 1 row affected (0,00 sec)
```

I've [reported this](https://bugs.mysql.com/bug.php?id=98896) to the MySQL bug tracker.

### Bug on `LOAD DATA INFILE`

There is also an additional bug: `LOAD DATA INFILE` statements will fail, if the columns are not explicitly specified:

```bash
echo '[]' > /tmp/test_data.csv

mysql <<'SQL'
  CREATE SCHEMA IF NOT EXISTS tmp;

  CREATE TEMPORARY TABLE tmp.issue_load_data_on_functional_index
  (
    json_col JSON,
    KEY json_col ( (CAST(json_col -> '$' AS UNSIGNED ARRAY)) )
  );

  LOAD DATA INFILE '/tmp/test_data.csv' INTO TABLE tmp.issue_load_data_on_functional_index;
SQL

# ERROR 1261 (01000) at line 9: Row 1 doesn't contain data for all columns
```

The workaround is to explicitly specify the columns:

```sql
LOAD DATA INFILE '/tmp/test_data.csv' INTO TABLE tmp.issue_load_data_on_functional_index (json_col);
```

I've [reported this bug](https://bugs.mysql.com/bug.php?id=98925) as well.

## Conclusion

I'm not bought into functional key parts.

While I find functional indexes an important functionality of solid, modern, RDBMSs, I think that the functional key parts feature itself needs some time to mature, especially considering that indexed generated columns can do the same work (with some exceptions, e.g. multi-valued indexing).

Now moving on to another new 8.0 interesting feature (window functions!) 😄

