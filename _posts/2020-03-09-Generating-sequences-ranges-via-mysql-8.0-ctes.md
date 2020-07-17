---
layout: post
title: Generating sequences/ranges, via MySQL 8.0's Common Table Expressions (CTEs)
tags: [databases,mysql]
category: mysql
---

A long-time missing (and missed) functionality in MySQL, is sequences/ranges.

As of MySQL 8.0, this functionality is still not supported in a general sense, however, it's now possible to generate a sequence to be used within a single query.

In this article, I'll give a brief introduction to CTEs, and explain how to build different sequence generators; additionally, I'll introduce the new (cool) MySQL 8.0 query hint `SET_VAR`, and a pinch of virtual columns and functional indexes ("functional key parts", another MySQL 8.0 feature).

Contents:

- [A brief introduction to Common Table Expressions (CTEs)](/Generating-sequences-ranges-via-mysql-8.0-ctes#a-brief-introduction-to-common-table-expressions-ctes)
- [Recursive CTEs, and generating a linear sequence of integers](/Generating-sequences-ranges-via-mysql-8.0-ctes#recursive-ctes-and-generating-a-linear-sequence-of-integers)
  - [Per-statement variables setting](/Generating-sequences-ranges-via-mysql-8.0-ctes#per-statement-variables-setting)
- [Generating a sequence of random integers](/Generating-sequences-ranges-via-mysql-8.0-ctes#generating-a-sequence-of-random-integers)
- [Generating a characters interval](/Generating-sequences-ranges-via-mysql-8.0-ctes#generating-a-characters-interval)
- [Generating a dates interval](/Generating-sequences-ranges-via-mysql-8.0-ctes#generating-a-dates-interval)
- [Conclusion](/Generating-sequences-ranges-via-mysql-8.0-ctes#conclusion)
- [Footnotes](/Generating-sequences-ranges-via-mysql-8.0-ctes#footnotes)

## A brief introduction to Common Table Expressions (CTEs)

Roughly, Common Table Expressions (`CTE`s) can be thought as ephemeral views or temporary tables.

CTEs bring very significant advantages, one of the most important being recursion, which, barring hacks, wasn't supported before.

The simplest syntax is:

```sql
WITH <cte_name> (<colums>) AS
(
  <cte_query>
)
<main_query>
```

for example[¹](#footnote01):

```sql
CREATE TABLE line_items(
  item_number INT UNSIGNED PRIMARY KEY,
  item_total  DECIMAL(8,2) NOT NULL,
  order_number INT UNSIGNED NOT NULL
);

INSERT INTO line_items VALUES
  (1, 10, 1),
  (2, 10, 1),
  (3, 15, 2)
;

WITH order_totals(order_number, order_total) AS
(
  SELECT order_number, SUM(item_total) `order_total`
  FROM line_items
  GROUP BY order_number
)
SELECT item_number, item_total, order_number, order_total
FROM line_items
     JOIN order_totals USING (order_number)
;

-- +-------------+------------+--------------+-------------+
-- | item_number | item_total | order_number | order_total |
-- +-------------+------------+--------------+-------------+
-- |           1 |      10.00 |            1 |       20.00 |
-- |           2 |      10.00 |            1 |       20.00 |
-- |           3 |      15.00 |            2 |       15.00 |
-- +-------------+------------+--------------+-------------+
```

The syntax is intuitive; in this example, it's used very much like a temporary table, with the advantage that no cleanup (`DROP TEMPORARY TABLE`) is needed.

## Recursive CTEs, and generating a linear sequence of integers

If one has to create a table filled with integers, say, as an example for a blog post 😉, the common approach is to use extended `INSERT`s (the form that stores multiple rows in one statement).

We can accomplish this more elegantly with a CTE, specifically, with a recursive one.

The syntax of recursive CTEs is:

```sql
WITH RECURSIVE <cte_name> (<colums>) AS
(
  <base_case_query>
  UNION ALL
  <recursive_step_query> -- invoke the CTE here!
)
<main_query>
```

The concept we apply here is to simulate iteration via recursion (more on this later).

Straight to the generator!:

```sql
-- Create a table with the integers in the range [0, 10].
--
CREATE TABLE int_sequence
WITH RECURSIVE sequence (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM sequence WHERE n + 1 <= 10
)
SELECT n
FROM sequence;
```

The table creation syntax may be slightly odd - one may expect `CREATE TABLE` to be below the `WITH` clause - but the working is straightforward.

When the `SELECT` invokes the CTE:

- the first row returned is the base case (`SELECT 0`);
- from the second onward, one row for each recursive step is returned.

This is all in all, simple. However, something important to pay attention to, is the termination condition: `WHERE n + 1 <= 0`. Why not using `WHERE n <= ...`?

Because this is a part where, it's easy to do a fencepost error. Let's see the wrong case:

```sql
-- Attempt to select the integers in the range [0, 10], the wrong way.
--
WITH RECURSIVE sequence (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM sequence WHERE n <= 10
)
SELECT n
FROM sequence;
```

What happens here is that one confuses the _returned row_ with the _last verified condition_. On the two last steps,

- `n = 10`;
- the condition is verified;
- `SELECT n + 1` is executed, returning `11`;
- `n = 11`;
- the condition is _not_ verified;
- recursion terminates.

Now, two alternatives are the conditions `WHERE n <= 9` or `WHERE n < 10`; while they are correct, they may be less intuitive than `WHERE n + 1 <= 10`, which mimicks the `SELECT`ed expression.

I'll conclude with two final notes.

First, we're using recursion as a way of performing iteration; this is subject to the same criticism of teaching recursion via Fibonacci series: it can arguably be considered as an overengineered/underperforming solution to a problem.

I don't take any position in this case, however, my personal order of increasing elegance for filling a table with a series of numbers is:

1. using an extended `INSERT`,
2. using a recursive CTE,
3. using a sequence generator.

Since MySQL doesn't provide 3., I'm happy to use 2. 😬.

The second note is more interesting, and I'll highlight it with a dedicated section.

### Per-statement variables setting

MySQL limits by default the number of recursions 1000, via the [`cte_max_recursion_depth` sysvar](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_cte_max_recursion_depth).

Now, if we want to generate a long sequence, we should:

1. set the variable,
2. execute the statement,
3. reset the variable.

This procedure consists of three statements, which is of course inconvenient. What do we do?

Enters the scene the [Per-statement variables setting](https://dev.mysql.com/doc/refman/8.0/en/optimizer-hints.html#optimizer-hints-set-var).

This is a lesser known MySQL 8.0 new feature, that comes very handy where needed.

In short, `SET_VAR` is a query hint, that allows one or more variables to be set exclusively within the scope of a statement.

In this case, if we want to generate a 1M numbers sequence, we set `cte_max_recursion_depth`:

```sql
-- Select the integers in the range [0, 1000000].
--
WITH RECURSIVE sequence (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM sequence WHERE n + 1 <= 1000000
)
SELECT /*+ SET_VAR(cte_max_recursion_depth = 1M) */
  n
FROM sequence;
```

(I've actually [opened a bug](https://bugs.mysql.com/bug.php?id=98881) suggesting to include this function in the CTE manpage.)

## Generating a sequence of random integers

If we want to create random numbers, we use `RAND()`[²](#footnote02) and `SELECT` only the associated expression:

```sql
-- Create a table with 1000 random integers in the range [0, 65536).
--
CREATE TABLE random_int_sequence
WITH RECURSIVE sequence (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM sequence WHERE n + 1 < 1000
)
SELECT FLOOR(65536 * RAND()) `rand_n`
FROM sequence;
```

## Generating a characters interval

Nothing prohibits us from generating a sequence of characters; in this case, we'll use the `CHAR()` and `ORD()` functions to increment the current value:

```sql
CREATE TABLE random_char_sequence
WITH RECURSIVE sequence (c) AS
(
  SELECT 'A'
  UNION ALL
  SELECT CHAR(ORD(c) + 1 USING ASCII) FROM sequence WHERE CHAR(ORD(c) + 1 USING ASCII) <= 'Z'
)
SELECT c
FROM sequence;
```

## Generating a dates interval

Finally, we'll generate a dates interval.

In this section, it's worth mentioning an interesting usage. Suppose one is reporting monthly sales. Is this query correct?:

```sql
-- Underlying table structure.
--
-- CREATE TABLE line_items(
--   id INT    UNSIGNED PRIMARY KEY,
--   total     DECIMAL(8,2) NOT NULL,
--   sold_on   DATETIME NOT NULL 
-- );

SELECT YEAR(sold_on) `sale_year`, MONTH(sold_on) `sale_month`, SUM(total) `month_sales`
FROM line_items
GROUP BY sale_year, sale_month;
```

The answer is: it depends on the requirements.

If the requirement is that _all_ the months must be displayed, one may miss rows for months when there are no sales.

A solution is to use a sequence with all the months in the required interval, and (left) join the CTE with the table.

Let's prepare some data (via CTE, of course! 😉), for a few months (except the current):

```sql
CREATE TABLE line_items(
  id INT       UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  total        DECIMAL(8,2) NOT NULL,
  sold_on      DATETIME NOT NULL,
  sold_on_date DATE AS (DATE(sold_on)),
  KEY (sold_on_date)
)
WITH RECURSIVE sequence (n) AS
(
  SELECT 0
  UNION ALL
  SELECT n + 1 FROM sequence WHERE n + 1 < 100000
)
SELECT /*+ SET_VAR(cte_max_recursion_depth = 1M) */
  CAST(20 * RAND() AS DECIMAL) `total`,
  NOW() - INTERVAL DAYOFMONTH(CURDATE()) DAY - INTERVAL (100 * RAND()) DAY `sold_on`
FROM sequence;
```

There are a couple of interesting concepts here:

The first is that by using `NOW() - INTERVAL DAYOFMONTH(CURDATE()) DAY` as base, we ensure that we don't store any sales for the current month.

The second is that, in order to perform an efficient left join, a functional index is required; there are a few considerations about this subject, which I'll leave to a separate article.

Additionally, note that float `INTERVAL`s are rounded (but it's irrelevant in this context).

Now we can query!

```sql
WITH RECURSIVE dates_range (d) AS
(
  SELECT CURDATE() - INTERVAL 124 DAY
  UNION ALL
  SELECT d + INTERVAL 1 DAY FROM dates_range WHERE d + INTERVAL 1 day <= CURDATE()
)
SELECT YEAR(d) `sales_year`, MONTH(d) `sales_month`, SUM(total) `month_total_sales`
FROM
  dates_range
  LEFT JOIN line_items ON d = sold_on_date
GROUP BY sales_year, sales_month
ORDER BY sales_year, sales_month;

-- +------------+-------------+-------------------+
-- | sales_year | sales_month | month_total_sales |
-- +------------+-------------+-------------------+
-- |       2019 |          11 |          27895.00 |
-- |       2019 |          12 |         331700.00 |
-- |       2020 |           1 |         335775.00 |
-- |       2020 |           2 |         306289.00 |
-- |       2020 |           3 |              NULL |
-- +------------+-------------+-------------------+
```

Excellent. The current month is displaying, as intended, even if it has no sales.

Let's check the optimizer plan (note that I've removed the `ORDER BY` clause for simplicity):

```sql
EXPLAIN FORMAT=TREE
WITH RECURSIVE dates_range (d) AS
(
  SELECT CURDATE() - INTERVAL 124 DAY
  UNION ALL
  SELECT d + INTERVAL 1 DAY FROM dates_range WHERE d + INTERVAL 1 day <= CURDATE()
)
SELECT YEAR(d) `sales_year`, MONTH(d) `sales_month`, SUM(total) `month_total_sales`
FROM
  dates_range
  LEFT JOIN line_items ON d = sold_on_date
GROUP BY sales_year, sales_month\G

-- *************************** 1. row ***************************
-- EXPLAIN: -> Table scan on <temporary>
--     -> Aggregate using temporary table
--         -> Nested loop left join
--             -> Table scan on dates_range
--                 -> Materialize recursive CTE dates_range
--                     -> Rows fetched before execution
--                     -> Repeat until convergence
--                         -> Filter: ((dates_range.d + interval 1 day) <= <cache>(curdate()))  (cost=2.73 rows=2)
--                             -> Scan new records on dates_range  (cost=2.73 rows=2)
--             -> Index lookup on line_items using sold_on_date (sold_on_date=dates_range.d)  (cost=0.28 rows=1)
```

The plan has a few interesting points, but they are left to the reader, since they are out of the scope of this article.

## Conclusion

MySQL 8.0 brought many, very interesting, features. Although sequences/generator are still not fully supported, we can use the (very flexible) CTEs to cover a part of the use cases.

Happy querying with MySQL 8.0!

## Footnotes

<a name="footnote01">¹</a>: Please note that real-world schemas are generally designed differently, and this example has been written with simplicity in mind instead.
<a name="footnote02">²</a>: Remember that `RAND()` is not a cryptographically secure function.
