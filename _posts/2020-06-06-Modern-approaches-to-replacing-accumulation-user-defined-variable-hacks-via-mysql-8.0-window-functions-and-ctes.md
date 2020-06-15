---
layout: post
title: Modern approaches to replacing accumulation user-defined variable hacks, via MySQL 8.0 Window functions and CTEs
tags: [databases,indexes,innodb,mysql]
---

A common MySQL strategy to perform updates with accumulating functions is to employ user-defined variables, using the `UPDATE [...] SET mycol = (@myvar := EXPRESSION(@myvar, mycol))` pattern.

This pattern though doesn't play well with the optimizer (leading to non-deterministic behavior), so it has been deprecated. This left a sort of void, since the (relatively) sophisticated logic is now harder to reproduce, at least with the same simplicity.

In this article, I'll have a look at two ways to apply such logic: using, canonically, window functions, and, a bit more creatively, using recursive CTEs.

- [Requirements and background](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#requirements-and-background)
- [The problem](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#the-problem)
- [Setup](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#setup)
- [The old-school approach](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#the-old-school-approach)
- [Modern approach #1: Window functions](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#modern-approach-1-window-functions)
  - [High-level logic](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#high-level-logic)
  - [`LAG()` window function](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#lag-window-function)
  - [Technical aspects](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#technical-aspects)
  - [Named windows](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#named-windows)
  - [`PARTITION BY` clause](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#partition-by-clause)
  - [Ordering](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#ordering)
  - [Considerations](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#considerations)
- [Modern approach #2: Recursive CTE](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#modern-approach-2-recursive-cte)
  - [Working version](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#working-version)
  - [Performance considerations](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#performance-considerations)
  - [Alternative for suboptimal plans](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#alternative-for-suboptimal-plans)
- [Conclusion](/Modern-approaches-to-replacing-accumulation-user-defined-variable-hacks-via-mysql-8.0-window-functions-and-ctes#conclusion)

## Requirements and background

Although CTEs are fairly intuitive, I advise, to those unfamiliar with the subject, to read my [previous post on the subject]({% post_url 2020-03-09-Generating-sequences-ranges-via-mysql-8.0-ctes %}).

The same principle applies to the window functions principles; I will break the query/concepts down, however, it's advised to have at least an idea. There is a vast amount of literature about window functions (which is the reason why I haven't written about them until now); pretty much all the tutorials use as example either corporate budgets, or populations/countries. Here instead, I'll use a real-world case.

In relation to the software, MySQL 8.0.19 is convenient (but not required). All the statements need to be run in the same console, due to reusing `@venue_id`.

There is always an architectural dilemma between placing the logic at the application level as opposed as the database level. Although this is an appropriate debate, in this context the underlying assumption is that it's _necessary_ that the logic stays at the database level; a requirement for this can be, for example, speed, which has actually been our case.

## The problem

In this problem, we manage venue (theater) seats.

As a business requirement, we need to assign a "grouping": an additional number representing each seat.

In order to set the grouping value:

1. start with grouping 0, and the top left seat;
2. if there is a space between the previous and current seat, or if it's a new row, increase the grouping by 2 (unless it's the first absolute seat), otherwise, increase by 1;
3. assign the grouping to the seat;
4. move to the next seat in the same row, or to the next row (if the row is over), and iterate from point 2., until the seats are exhausted.

In pseudocode:

```
current_grouping = 0

for each row:
  for each number:
    if (is_there_a_space_after_last_seat or is_a_new_row) and is_not_the_first_seat:
      current_grouping += 2
    else
      current_grouping += 1

    seat.grouping = current_grouping
```

In practice, we want the setup on the left to have the corresponding values on the right:

```
  x→  0   1   2        0   1   2
y   ╭───┬───┬───╮    ╭───┬───┬───╮
↓ 0 │ x │ x │   │    │ 1 │ 2 │   │
    ├───┼───┼───┤    ├───┼───┼───┤
  1 │ x │   │ x │    │ 4 │   │ 6 │
    ├───┼───┼───┤    ├───┼───┼───┤
  2 │ x │   │   │    │ 8 │   │   │
    ╰───┴───┴───╯    ╰───┴───┴───╯
```

## Setup

Let's use a minimalist design for the underlying table:

```sql
CREATE TABLE seats (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  venue_id   INT,
  y          INT,
  x          INT,
  `row`      VARCHAR(16),
  number     INT,
  `grouping` INT,
  UNIQUE venue_id_y_x (venue_id, y, x)
);
```

We won't need the `row`/`number` columns, however, on the other hand, we don't want to use a table whose records are fully contained in an index, in order to be closer to a real-world setting.

Based on the diagram of the previous section, the seat coordinates are, in the form `(y, x)`:

- (0, 0), (0, 1)
- (1, 0), (1, 2)
- (2, 0)

Note that we're using `y` as first coordinate, because it makes it easier to reason in terms of rows.

We're going to load a large enough number of records, in order to make sure the optimizer doesn't take unexpected shortcuts. We use recursive CTEs, of course 😉:

```sql
INSERT INTO seats(venue_id, y, x, `row`, number)
WITH RECURSIVE venue_ids (id) AS
(
  SELECT 0
  UNION ALL
  SELECT id + 1 FROM venue_ids WHERE id + 1 < 100000
)
SELECT /*+ SET_VAR(cte_max_recursion_depth = 1M) */
  v.id,
  c.y, c.x,
  CHAR(ORD('A') + FLOOR(RAND() * 3) USING ASCII) `row`,
  FLOOR(RAND() * 3) `number`
FROM venue_ids v
     JOIN (
       VALUES
         ROW(0, 0),
         ROW(0, 1),
         ROW(1, 0),
         ROW(1, 2),
         ROW(2, 0)
     ) c (y, x)
;

ANALYZE TABLE seats;
```

A couple of notes:

1. we're using the CTEs in a (hopefully!) interesting way - each cycle represents a venue id, but since we want multiple seats to be generated for each venue (cycle), we cross join with a table including the seats data;
2. we're using the v8.0.19's row constructor (`VALUES ROW()...`) in order to represent a (joinable) table without actually creating it;
3. we generate random `row`/`number` data, as they're filler;
4. for simplicity, no tweaks have been applied (e.g. data types are wider than needed, the indexes are added before the records are inserted, etc.).

## The old-school approach

The old-school solution is very straightforward:

```sql
SET @venue_id = 5000; -- arbitrary venue id; any (stored) id will do

SET @grouping = -1;
SET @y = -1;
SET @x = -1;

WITH seat_groupings (id, y, x, `grouping`, tmp_y, tmp_x) AS
(
  SELECT
    id, y, x,
    @grouping := @grouping + 1 + (seats.x > @x + 1 OR seats.y != @y),
    @y := seats.y,
    @x := seats.x
  FROM seats
  WHERE venue_id = @venue_id
  ORDER BY y, x
)
UPDATE
  seats s
  JOIN seat_groupings sg USING (id)
SET s.grouping = sg.grouping
;

-- Query OK, 5 rows affected, 3 warnings (0,00 sec)
```

Nice and easy (but keep in mind the warnings)!

A little side note: I'm taking advantage of boolean arithmetic properties here; specifically, the following statements are equivalent:

```sql
SELECT seats.x > @x + 1 OR seats.y != @y `increment`;

SELECT IF (
  seats.x > @x + 1 OR seats.y != @y,
  1,
  0
) `increment`;
```

some people find it intuitive, some don't - it's a matter of taste; since it's clarified now, for compactness purposes, I will use it for the rest of the article.

Let's see the outcome:

```sql
SELECT id, y, x, `grouping` FROM seats WHERE venue_id = @venue_id ORDER BY y, x;

-- +-------+------+------+----------+
-- | id    | y    | x    | grouping |
-- +-------+------+------+----------+
-- | 24887 |    0 |    0 |        1 |
-- | 27186 |    0 |    1 |        2 |
-- | 29485 |    1 |    0 |        4 |
-- | 31784 |    1 |    2 |        6 |
-- | 34083 |    2 |    0 |        8 |
-- +-------+------+------+----------+
```

This approach is ideal!

It has just a "small" defect: it may work... or not.

The reason is that the query optimizer doesn't necessarily evaluate left to right, so the assignment operations (`:=`) may be evaluated out of order, causing the result to be wrong. This is a problem typically experienced after MySQL upgrades.

As of MySQL 8.0, this functionality is indeed deprecated:

```sql
-- To be run immediately after the UPDATE.
--
SHOW WARNINGS\G
-- *************************** 1. row ***************************
--   Level: Warning
--    Code: 1287
-- Message: Setting user variables within expressions is deprecated and will be removed in a future release. Consider alternatives: 'SET variable=expression, ...', or 'SELECT expression(s) INTO variables(s)'.
-- [...]
```

Let's fix this!

## Modern approach #1: Window functions

Window functions have been a long-awaited functionality in the MySQL world.

Generally speaking, the "rolling" nature of window functions fits very well accumulating functions. However, some complex accumulating functions require the results of the latest expression to be available, which is something window functions don't support, since they work on a column basis.

This doesn't mean that the problem can't be solved, rather, than it needs to be re-thought.

In this case, we split the problem in two concepts; we think the grouping value for each seat as the sum of two values:

- the sequence number of each seat, and
- the cumulative value of the increments of all the seats up to the current one.

Those familiar with window functions will recognize the patterns here 🙂

The sequence number of each seat is a built-in function:

```sql
ROW_NUMBER() OVER <window>
```

The cumulative value is where things get interesting. In order to accomplish this task, we perform two steps:

1. we calculate each seat increment, and put it on a table (or CTE),
1. then, for each seat, we use a window function to sum the increments up to that seat.

Let's see the SQL:

```sql
WITH
increments (id, increment) AS
(
  SELECT
    id,
    x > LAG(x, 1, x - 1) OVER tzw + 1 OR y != LAG(y, 1, y) OVER tzw
  FROM seats
  WHERE venue_id = @venue_id
  WINDOW tzw AS (ORDER BY y, x)
)
SELECT
  s.id, y, x,
  ROW_NUMBER() OVER tzw + SUM(increment) OVER tzw `grouping`
FROM seats s
     JOIN increments i USING (id)
WINDOW tzw AS (ORDER BY y, x)
;

-- +-------+---+---+----------+
-- | id    | y | x | grouping |
-- +-------+---+---+----------+
-- | 24887 | 0 | 0 |        1 |
-- | 27186 | 0 | 1 |        2 |
-- | 29485 | 1 | 0 |        4 |
-- | 31784 | 1 | 2 |        6 |
-- | 34083 | 2 | 1 |        8 |
-- +-------+---+---+----------+
```

Nice!

(Note that for simplicity, I'll omit the `UPDATE` from now on.)

Let's review the query.

### High-level logic

The CTE (edited):

```sql
SELECT
  id,
  x > LAG(x, 1, x - 1) OVER tzw + 1 OR y != LAG(y, 1, y) OVER tzw `increment`
FROM seats
WHERE venue_id = @venue_id
WINDOW tzw AS (ORDER BY y, x)
;

-- +-------+-----------+
-- | id    | increment |
-- +-------+-----------+
-- | 24887 |         0 |
-- | 27186 |         0 |
-- | 29485 |         1 |
-- | 31784 |         1 |
-- | 34083 |         1 |
-- +-------+-----------+
```

calculates the increments for each seat, compared to the previous (more on `LAG()` later). It works purely on each record and the previous; it's not cumulative.

Now, in order to calculate the cumulative increments, we just use a window function to compute the sum, for and up to each seat:

```sql
-- (CTE here...)
SELECT
  s.id, y, x,
  ROW_NUMBER() OVER tzw `pos.`,
  SUM(increment) OVER tzw `cum.incr.`
FROM seats s
     JOIN increments i USING (id)
WINDOW tzw AS (ORDER BY y, x);

-- +-------+---+---+------+-----------+
-- | id    | y | x | pos. | cum.incr. | (grouping)
-- +-------+---+---+------+-----------+
-- | 24887 | 0 | 0 |    1 |         0 | = 1 + 0 (curr.)
-- | 27186 | 0 | 1 |    2 |         0 | = 2 + 0 (#24887) + 0 (curr.)
-- | 29485 | 1 | 0 |    3 |         1 | = 3 + 0 (#24887) + 0 (#27186) + 1 (curr.)
-- | 31784 | 1 | 2 |    4 |         2 | = 4 + 0 (#24887) + 0 (#27186) + 1 (#29485) + 1 (curr.)
-- | 34083 | 2 | 1 |    5 |         3 | = 5 + 0 (#24887) + 0 (#27186) + 1 (#29485) + 1 (#31784)↵
-- +-------+---+---+------+-----------+     + 1 (curr.)
```

### `LAG()` window function

The `LAG` function, in the simplest form (`LAG(x)`), returns the previous value of the given column. A typical nuisance of window functions is to deal with the first record(s) in the window - since there is no previous record, they return NULL. With LAG, we can specify the value we want as third parameter:

```sql
LAG(x, 1, x - 1) -- defaults to `x -1`
LAG(y, 1, y)     -- defaults to `y`
```

By specifying the defaults above, we make sure that the very first seat in the window will be treated by the logic as adjacent to the previous one (`x - 1`) and in the same row (`y`).

The alternative to defaults is typically `IFNULL`, which is very intrusive, especially considering the relative complexity of the expression:

```sql
-- Both valid. And both ugly!
--
IFNULL(x > LAG(x) OVER tzw + 1 OR y != LAG(y) OVER tzw, 0)
IFNULL(x > LAG(x) OVER tzw + 1, FALSE) OR IFNULL(y != LAG(y) OVER tzw, FALSE)
```

The second `LAG()` parameter is the number of positions to go back in the window; `1` is the previous, which is also the default value.

### Technical aspects

### Named windows

In this query, we're using multiple times the same window. The following queries are formally equivalent:

```sql
SELECT
  id,
  x > LAG(x, 1, x - 1) OVER tzw + 1
    OR y != LAG(y, 1, y) OVER tzw
FROM seats
WHERE venue_id = @venue_id
WINDOW tzw AS (ORDER BY y, x);

SELECT
  id,
  x > LAG(x, 1, x - 1) OVER (ORDER BY y, x) + 1
    OR y != LAG(y, 1, y) OVER (ORDER BY y, x)
FROM seats
WHERE venue_id = @venue_id;
```

However, the latter may cause a suboptimal plan (which I've experienced, at least in the past); the optimizer may treat the windows as independent, and iterate them separately.  
For this reason, I advise to always use named windows, at least when there are duplicated ones.

### `PARTITION BY` clause

Typically, window functions are executed over a partition, which in this case would be:

```sql
SELECT
  id,
  x > LAG(x, 1, x - 1) OVER tzw + 1
    OR y != LAG(y, 1, y) OVER tzw
FROM seats
WHERE venue_id = @venue_id
WINDOW tzw AS (PARTITION BY venue_id ORDER BY y, x); -- here!
```

Since the window matches the full set of records (which is filtered by the `WHERE` condition), we don't need to specify it.

If we had to run this query over the whole `seats` table, then we'd need it, so that, across each `venue_id`, the window is reset.

### Ordering

In the query, the `ORDER BY` is specified at the window level:

```sql
SELECT
  id,
  x > LAG(x, 1, x - 1) OVER tzw + 1
    OR y != LAG(y, 1, y) OVER tzw
FROM seats
WHERE venue_id = @venue_id
WINDOW tzw AS (ORDER BY y, x)
```

The window ordering is separate from the `SELECT` one. This is crucial! The behavior of this query:

```sql
SELECT
  id,
  x > LAG(x, 1, x - 1) OVER tzw + 1
    OR y != LAG(y, 1, y) OVER tzw
FROM seats
WHERE venue_id = @venue_id
WINDOW tzw AS ()
ORDER BY y, x
```

is unspecified. Let's have a look at the [manpage](https://dev.mysql.com/doc/refman/8.0/en/window-functions-usage.html):

> Query result rows are determined from the FROM clause, after WHERE, GROUP BY, and HAVING processing, and windowing execution occurs before ORDER BY, LIMIT, and SELECT DISTINCT.

### Considerations

Abstractly speaking, in order to solve this class of problems, instead of representing each entry as as a function of the previous one, we calculate the state change for each entry, then sum the changes up.

Although more complex than the functionality it replaces, this solution is very solid. This approach though, may not be always possible, or at least easy, so that's where the recursive CTE solution comes into play.

## Modern approach #2: Recursive CTE

This approach requires a workaround due to a limitation in MySQL's CTE functionality, but, on the other hand, it's a generic, direct, solution, and as such, it doesn't require any rethinking of the approach.

Let's start from a the simplified version of the end query:

```sql
-- `p_` is for `Previous`, in order to make the conditions a bit more intuitive.
--
WITH RECURSIVE groupings (p_id, p_venue_id, p_y, p_x, p_grouping) AS
(
  (
    SELECT id, venue_id, y, x, 1
    FROM seats
    WHERE venue_id = @venue_id
    ORDER BY y, x
    LIMIT 1
  )

  UNION ALL

  SELECT
    s.id, s.venue_id, s.y, s.x,
    p_grouping + 1 + (s.x > p_x + 1 OR s.y != p_y)
  FROM groupings, seats s
  WHERE s.venue_id = p_venue_id AND (s.y, s.x) > (p_y, p_x)
  ORDER BY s.venue_id, s.y, s.x
  LIMIT 1
)
SELECT * FROM groupings;
```

Bingo! This query is (relatively) simple, but most importantly, it expresses the grouping accumulating function in the simplest possible way:

```sql
p_grouping + 1 + (s.x > p_x + 1 OR s.y != p_y)

-- the above is equivalent to:

@grouping := @grouping + 1 + (seats.x > @x + 1 OR seats.y != @y),
@y := seats.y,
@x := seats.x
```

Even for those who are not accustomed with CTEs, the logic is simple.

The initial row is the first seat of the venue, in order:

```sql
SELECT id, venue_id, y, x, 1
FROM seats
WHERE venue_id = @venue_id
ORDER BY y, x
LIMIT 1
```

In the recursive part, we proceed with the iteration:

```sql
SELECT
  s.id, s.venue_id, s.y, s.x,
  p_grouping + 1 + (s.x > p_x + 1 OR s.y != p_y)
FROM groupings, seats s
WHERE s.venue_id = p_venue_id AND (s.y, s.x) > (p_y, p_x)
ORDER BY s.venue_id, s.y, s.x
LIMIT 1
```

the `WHERE` condition, along with the `ORDER BY` and `LIMIT` clauses, simply find the next seat, that is, the one seat with the same venue id, which, in order of `(venue_id, x, y)`, has greater `(x, y)` coordinates.

The `s.venue_id` part of the ordering is crucial! This allows us to use the index.

The `SELECT` clause takes care of:

- performing the accumulation (computation of `(p_)grouping`),
- passing the values of the current seat (`s.id, s.venue_id, s.y, s.x`) to the next cycle.

We select `FROM groupings` so that we fulfill the requirements for the CTE to be recursive.

What's interesting here is that we use the recursive CTE essentially as iterator, via selection from the `groupings` table in the recursive subquery, while joining with `seats`, in order to find the data to work on.

The JOIN is formally a cross join, however, only one record is returned, due to the `LIMIT` clause.

### Working version

Unfortunately, the above query doesn't work because the `ORDER BY` clause is currently not supported in the recursive subquery; additionally, the semantics of the `LIMIT` as used here are not the intended ones, as they [apply to the outermost query](https://dev.mysql.com/doc/refman/8.0/en/with.html#common-table-expressions-recursive-examples):

> LIMIT is now supported [...] The effect on the result set is the same as when using LIMIT in the outermost SELECT

However, it's not a significant problem. Let's have a look at the working version:

```sql
WITH RECURSIVE groupings (p_id, p_venue_id, p_y, p_x, p_grouping) AS
(
  (
    SELECT id, venue_id, y, x, 1
    FROM seats
    WHERE venue_id = @venue_id
    ORDER BY y, x
    LIMIT 1
  )

  UNION ALL

  SELECT
    s.id, s.venue_id, s.y, s.x,
    p_grouping + 1 + (s.x > p_x + 1 OR s.y != p_y)
  FROM groupings, seats s WHERE s.id = (
    SELECT si.id
    FROM seats si
    WHERE si.venue_id = p_venue_id AND (si.y, si.x) > (p_y, p_x)
    ORDER BY si.venue_id, si.y, si.x
    LIMIT 1
  )
)
SELECT * FROM groupings;

-- +-------+------+------+------------+
-- | p_id  | p_y  | p_x  | p_grouping |
-- +-------+------+------+------------+
-- | 24887 |    0 |    0 |          1 |
-- | 27186 |    0 |    1 |          2 |
-- | 29485 |    1 |    0 |          4 |
-- | 31784 |    1 |    2 |          6 |
-- | 34083 |    2 |    0 |          8 |
-- +-------+------+------+------------+
```

It's a bit of shame having to use a subquery, but it works, and the boilerplate is minimal, as several clauses are required anyway.

Here, instead of performing the ordering and limiting, in the relation resulting from the join of `groupings` and `seats`, we do it in a subquery, and pass it to the outer query, which will consequently select only the target record.

### Performance considerations

Let's have a look at the query plan, using the `EXPLAIN ANALYZE` functionality:

```
mysql> EXPLAIN ANALYZE WITH RECURSIVE groupings [...]

-> Table scan on groupings  (actual time=0.000..0.001 rows=5 loops=1)
    -> Materialize recursive CTE groupings  (actual time=0.140..0.141 rows=5 loops=1)
        -> Limit: 1 row(s)  (actual time=0.019..0.019 rows=1 loops=1)
            -> Index lookup on seats using venue_id_y_x (venue_id=(@venue_id))  (cost=0.75 rows=5) (actual time=0.018..0.018 rows=1 loops=1)
        -> Repeat until convergence
            -> Nested loop inner join  (cost=3.43 rows=2) (actual time=0.017..0.053 rows=2 loops=2)
                -> Scan new records on groupings  (cost=2.73 rows=2) (actual time=0.001..0.001 rows=2 loops=2)
                -> Filter: (s.id = (select #5))  (cost=0.30 rows=1) (actual time=0.020..0.020 rows=1 loops=5)
                    -> Single-row index lookup on s using PRIMARY (id=(select #5))  (cost=0.30 rows=1) (actual time=0.014..0.014 rows=1 loops=5)
                    -> Select #5 (subquery in condition; dependent)
                        -> Limit: 1 row(s)  (actual time=0.007..0.008 rows=1 loops=9)
                            -> Filter: ((si.y,si.x) > (groupings.p_y,groupings.p_x))  (cost=0.75 rows=5) (actual time=0.007..0.007 rows=1 loops=9)
                                -> Index lookup on si using venue_id_y_x (venue_id=groupings.p_venue_id)  (cost=0.75 rows=5) (actual time=0.006..0.006 rows=4 loops=9)
```

The plan is very much as expected. The foundation of an optimal plan for this case, is in the index lookups:

```
-> Nested loop inner join  (cost=3.43 rows=2) (actual time=0.017..0.053 rows=2 loops=2)
-> Single-row index lookup on s using PRIMARY (id=(select #5))  (cost=0.30 rows=1) (actual time=0.014..0.014 rows=1 loops=5)
-> Index lookup on si using venue_id_y_x (venue_id=groupings.p_venue_id)  (cost=0.75 rows=5) (actual time=0.006..0.006 rows=4 loops=9)
```

which are paramount; if even an index scan is performed (in short, when the index entries are scanned linearly, instead of finding directly the desired one), the performance will tank.

Therefore, the requirements for this strategy to work, are that the related indexes are in place _and_ are used by the optimizer very efficiently.

It's expected that, in the future, if the restrictions are lifted, not having to use the subquery will make the task considerably simpler for the optimizer.

### Alternative for suboptimal plans

For particular use cases where an optimal plan can't be found, just use a temporary table:

```sql
CREATE TEMPORARY TABLE selected_seats (
  id INT NOT NULL PRIMARY KEY,
  y INT,
  x INT,
  UNIQUE (y, x)
)
SELECT id, y, x
FROM seats WHERE venue_id = @venue_id;

WITH RECURSIVE
groupings (p_id, p_y, p_x, p_grouping) AS
(
  (
    SELECT id, y, x, 1
    FROM seats
    WHERE venue_id = @venue_id
    ORDER BY y, x
    LIMIT 1
  )

  UNION ALL

  SELECT
    s.id, s.y, s.x,
    p_grouping + 1 + (s.x > p_x + 1 OR s.y != p_y)
  FROM groupings, seats s WHERE s.id = (
    SELECT ss.id
    FROM selected_seats ss
    WHERE (ss.y, ss.x) > (p_y, p_x)
    ORDER BY ss.y, ss.x
    LIMIT 1
    )
)
SELECT * FROM groupings;
```

Even if index scans are performed in this query, they're very cheap, as the `selected_seats` table is very small.

## Conclusion

I'm very pleased that a very effective but flawed workflow, can be replaced with clean (enough) functionalities, which have been brought by MySQL 8.0.

There are still new (underlying) functionalities in development in the 8.0 series, which therefore keeps proving to be a very strong release.

Happy recursion 😄
