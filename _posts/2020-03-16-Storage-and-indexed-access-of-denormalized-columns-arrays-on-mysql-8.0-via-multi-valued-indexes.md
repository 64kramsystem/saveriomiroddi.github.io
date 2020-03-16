---
layout: post
title: Storage and Indexed access of denormalized columns (arrays) on MySQL 8.0, via multi-valued indexes
tags: [databases,data_types,indexes,innodb,mysql]
---

Another "missing and missed" functionality in MySQL is a data type for arrays.

While MySQL is not there yet, it's now possible to cover a significant use case: storing denormalized columns (or arrays in general), and accessing them via index.

In this article I'll give some context about denormalized data and indexes, including the workaround for such functionality on MySQL 5.7, and describe how this is (rather) cleanly accomplished on MySQL 8.0.

- [Terminology](/Storage-and-indexed-access-of-denormalized-columns-arrays-on-mysql-8.0-via-multi-valued-indexes#terminology)
- [Storing and indexing arrays in MySQL 5.7: an approach, and problems](/Storage-and-indexed-access-of-denormalized-columns-arrays-on-mysql-8.0-via-multi-valued-indexes#storing-and-indexing-arrays-in-mysql-57-an-approach-and-problems)
- [The MySQL 8.0 implementation: data type and index](/Storage-and-indexed-access-of-denormalized-columns-arrays-on-mysql-8.0-via-multi-valued-indexes#the-mysql-80-implementation-data-type-and-index)
- [Performance expectations](/Storage-and-indexed-access-of-denormalized-columns-arrays-on-mysql-8.0-via-multi-valued-indexes#performance-expectations)
  - [Why multiple arrays can't be indexed](/Storage-and-indexed-access-of-denormalized-columns-arrays-on-mysql-8.0-via-multi-valued-indexes#why-multiple-arrays-cant-be-indexed)
- [How do I declare an ARRAY UNSIGNED column?](/Storage-and-indexed-access-of-denormalized-columns-arrays-on-mysql-8.0-via-multi-valued-indexes#how-do-i-declare-an-array-unsigned-column)
- [Conclusion](/Storage-and-indexed-access-of-denormalized-columns-arrays-on-mysql-8.0-via-multi-valued-indexes#conclusion)
- [Footnotes](/Storage-and-indexed-access-of-denormalized-columns-arrays-on-mysql-8.0-via-multi-valued-indexes#footnotes)

## Terminology

Although B-trees are technically inverted indexes, in this context I'll use the "inverted index" term to describe document-oriented indexes, like PostgreSQL's GIN or InnoDB's fulltext index, and I'll refer to B-trees with their name.

Also, I won't make any distinction between B-trees and B+trees, using only the "B-tree" term.

## Storing and indexing arrays in MySQL 5.7: an approach, and problems

MySQL doesn't have an array data type. This is a fundamental problem in architectures where storing denormalized rows is a requirement, for example, where MySQL is (also) used for data warehousing.

Storage and access are two sides of the same coin: missing optimal storage data structures for a certain class of data almost certainly implies the lack of optimal related algorithms; in this case, it translates to lack of (direct) indexing.

Storing arrays is not a big problem in itself: assuming simple data types, like integers, we can easily adopt the workaround of using a VARCHAR/TEXT column to store the values with an arbitrary separator (space is the most convenient), however, MySQL is (was) not designed to index this scenario.

Again, we can adopt another workaround: fulltext indexes. We can either set the [InnoDB fulltext minimum token size](https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_ft_min_token_size) to 1, but this has the downside of being a global setting, or pad the values, which works, although it's suboptimal in terms of storage.

This is a working solution, if one really needs to: it has with the downsides of InnoDB's fulltext indexes support, which are not few, but it's good enough.

## The MySQL 8.0 implementation: data type and index

MySQL can store arrays since v5.7, through the JSON data type:

```sql
-- Note how we're using the v8.0.19's new `ROW()` construct for inserting multiple rows.
--
CREATE TEMPORARY TABLE t_json_arrays(
  id      INT PRIMARY KEY AUTO_INCREMENT,
  c_array JSON NOT NULL
)
SELECT *
FROM (
  VALUES
    ROW("[1, 2, 3]"),
    ROW(JSON_ARRAY(4, 5, 6))
) v (c_array);

SELECT * FROM t_json_arrays;

-- +----+-----------+
-- | id | c_array   |
-- +----+-----------+
-- |  1 | [1, 2, 3] |
-- |  2 | [4, 5, 6] |
-- +----+-----------+
```

We can insert a JSON document (array) either as a string, or using the `JSON_ARRAY` function.

Some operators are available for accessing the data stored in the JSON document, e.g. `->`:

```sql
-- Functionality for accessing JSON data
--
SELECT id, c_array -> "$[1]" `array_entry_1` FROM t_json_arrays;

-- +----+---------------+
-- | id | array_entry_1 |
-- +----+---------------+
-- |  1 | 2             |
-- |  2 | 5             |
-- +----+---------------+
```

However, indexing has been introduced only with v8.0.17, along with new search functionalities:

```sql
-- This is a functional index.
--
ALTER TABLE t_json_arrays ADD KEY ( (CAST(c_array -> '$' AS UNSIGNED ARRAY)) );

SELECT * FROM t_json_arrays WHERE 3 MEMBER OF (c_array);

-- +----+-----------+
-- | id | c_array   |
-- +----+-----------+
-- |  1 | [1, 2, 3] |
-- +----+-----------+

EXPLAIN FORMAT=TREE SELECT * FROM t_json_arrays WHERE 3 MEMBER OF (c_array -> '$');

-- -> Filter: json'3' member of (cast(json_extract(t_json_arrays.c_array,_utf8mb4'$') as unsigned array))  (cost=1.10 rows=1)
--     -> Index lookup on t_json_arrays using functional_index (cast(json_extract(t_json_arrays.c_array,_utf8mb4'$') as unsigned array)=json'3')  (cost=1.10 rows=1)
```

Note how the `WHERE` condition *must* replicate exactly the functional key part (in this case, `c_array -> '$'`).

## Performance expectations

According to the [functionality worklog](https://dev.mysql.com/worklog/task/?id=8955#tabs-8955-4), the index is a slightly modified B-tree:

> In general, multi-valued index is a regular functional index, with the exception that it requires additional handling under the hood on INSERT/UPDATE for multi-valued key parts.

```sql
SHOW INDEXES FROM t_json_arrays WHERE Key_name NOT LIKE 'PRIMARY'\G

-- *************************** 1. row ***************************
--      Table: t_json_arrays
--   Key_name: functional_index
-- Index_type: BTREE
-- [...]
```

Using a simple B-tree for this purpose has the specular opposite advantages and disadvantages of inverted indexes, the crucial difference being that the operations cost increases linearly with the size of the array stored.

This is because B-trees don't have optimizations for large/batch insertions (inverted indexes are document-oriented, so it's expected for insertions to be large); each array entry is one key in the index.

On the other hand, the DMLs cost is constant[¹](#footnote01); there are no spikes caused by maintenance operations (ie. [index merging](https://www.postgresql.org/docs/current/gin-implementation.html#GIN-FAST-UPDATE).

### Why multiple arrays can't be indexed

An interesting point is that:

> Only one multi-valued key part is allowed per index, to avoid exponential explosion. E.g if there would be two multi-valued key parts, and server would provide 10 values for each, SE would have to store 100 index records.

Why is that?

Because there are no convenient data structures for optimizing such case.

With the current data structure, the tuple `[1, 2], [4, 5]` would generate the index keys:

- `(1, 4)`,
- `(1, 5)`,
- `(2, 4)`,
- `(2, 5)`.

Suppose that we tackled the problem by reducing the keys to a composition of each value of the first array with the second array:

- `(1, 4, 5)`,
- `(2, 4, 5)`.

we couldn't efficiently search in both arrays, since the index is only on the first element; for example, searching on:

- `1, 4`

could only lookup for `1` entries, not for `4` ones.

Sounds familiar? This is essentially the leftmost string prefix search problem.

The arrays of each tuple can still be independently indexed; probably, such configuration could lead to the [index merge intersection optimization](https://dev.mysql.com/doc/refman/8.0/en/index-merge-optimization.html#index-merge-intersection).

## How do I declare an ARRAY UNSIGNED column?

We've played with arrays storage and indexing; how about creating a column of UNSIGNED ARRAY data type?:

```sql
CREATE TEMPORARY TABLE t_json_arrays(
  id      INT PRIMARY KEY AUTO_INCREMENT,
  c_array UNSIGNED ARRAY NOT NULL
);

-- ERROR 1064 (42000): You have an error in your SQL syntax [...] near 'UNSIGNED ARRAY NOT NULL
```

Ouch! There is no currently such data type. Internally, everything is done via json; the worklog explains this:

> [...] server creates virtual generated column using the typed array field (instead of a regular field) for a function for which is_returns_array() method returns true. This WL adds one such function - CAST(... AS ... ARRAY).<br>
> The typed array field (Field_typed_array class) essentially is a JSON field, a descendant of Field_json, but it reports itself as a regular field which type is typed array element's type. [...]

Adding a new data type would require a considerable amount of work; the team's resources are evidently focused on other functionalities, so they released a good-enough functionality, which in my opinion, is a balanced choice.

## Conclusion

We're very excited by the introduction of this data type, and we're in the process of migrating the fulltext indexes used for pseudo-arrays, to JSON-based array columns/indexes; I think this is a very significant step in making MySQL a well-rounded RDBMS, and covers an important use case in applications of a certain size.

## Footnotes

<a name="footnote01">¹</a>: Insertion cost in B-trees is not constant, however, the maintenance cost (rebalancing) is negligible in this context.
