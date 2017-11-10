---
layout: post
title: Data storage analysis and optimization of (MySQL) InnoDB indexes
tags: [mysql, innodb, indexes, storage, performance, databases]
---

Recently, we decided to clean our data model, in particular, the OLTP section of our schema. We have a reasonably well structured model, but it falls short when it comes to the data type definitions.

In this article we explore the storage requirements of a (InnoDB) table of ours, and the impact of choosing more strictly defined columns.

## Measuring the data structures (data/indexes) occupation of an InnoDB table

It's very easy to measure how much the indexes of an InnoDB table take. Bear in mind that, due to InnoDB storing the data in a so-called ["clustered"][Clustered indexes] index, called `PRIMARY`.

This is the command used for checking the statistics of a table called `reservations`, with a single regular index, on the column `allocation_id`:

```sql
SELECT table_name, index_name, stat_value*@@innodb_page_size `size`
FROM mysql.innodb_index_stats
WHERE stat_name = 'size'
      AND (database_name, table_name) = ('test', 'reservations')
;
```

```
+--------------+----------------------+-----------+
| table_name   | index_name           | size      |
+--------------+----------------------+-----------+
| reservations | PRIMARY              | 871366656 |
| reservations | allocation_id        | 476053504 |
+--------------+----------------------+-----------+
```

In this case, the table data (`PRIMARY` index) takes ~831 MiB, while the `allocation_id` takes ~454 MiB.

As you can see from the query, the statistics table stores the result in pages, so we multiply by the page size.

For reference, the table has ~16.6M records.

## Indexes fragmentation

Indexes are efficient data stuctures for storing/retrieving data, but they are subject to fragmentation.

It's normal and expected to have fragmentation, but it's important to be aware of its existence, in order to take the appropriate measures in the case where it affects performance.

In this article we won't explore the fragmentation (a starting point is the `index_page_splits` metric - see `information_schema.innodb_metrics`), but we observe how the size (and indirectly, structure) of a live table changes when rebuilt:

```sql
ALTER TABLE reservations DROP KEY allocation_id, ADD KEY (allocation_id);
```

```sql
SELECT table_name, index_name, stat_value*@@innodb_page_size `size`
FROM mysql.innodb_index_stats
WHERE stat_name = 'size'
      AND (database_name, table_name, index_name) = ('test', 'reservations', 'allocation_id')
;
```

```
+--------------+---------------+-----------+
| table_name   | index_name    | size      |
+--------------+---------------+-----------+
| reservations | allocation_id | 259784704 |
+--------------+---------------+-----------+
```

This is an interesting result; the compacted index takes (248 MiB), which is ~54% of the original size.
It's up to the administrator, to measure the impact and decide if action needs to be taken, on a per-table basis.

InnoDB index defragmentation on live systems can currently only be performed using online MySQL schema change tools like [gh-ost](https://github.com/github/gh-ost) or [pt-online-schema-change](https://www.percona.com/doc/percona-toolkit/LATEST/pt-online-schema-change.html).

In the context of this article, this section is meaningful because the compacted index size (248 MiB) is used as reference.

## Observing the effect of nullability on an INT column

There are a few reasons why columns should be set as NOT NULL unless strictly/semantically necessary:

1. the NULL flag takes (measurable) space;
2. nullable fields can complicate the query optimizer planning;
3. avoid ambiguity, particularly on large codebases, between a NULL value and a default one;
4. prevent corruption, particularly on data sets where manual operations (eg. data imports) are routinely performed.

In this article, we observe the effect of point 1, using:

```sql
ALTER TABLE reservations MODIFY allocation_id INT; # convert to nullable field
```

MySQL has [several][InnoDB INFORMATION_SCHEMA System Tables] [statistics tables][InnoDB Persistent Statistics Tables] in the metadata schemas, one of whom is `mysql.innodb_index_stats`:

```
+------------------+---------------------+------+-----+-------------------+-----------------------------+
| Field            | Type                | Null | Key | Default           | Extra                       |
+------------------+---------------------+------+-----+-------------------+-----------------------------+
| database_name    | varchar(64)         | NO   | PRI | NULL              |                             |
| table_name       | varchar(64)         | NO   | PRI | NULL              |                             |
| index_name       | varchar(64)         | NO   | PRI | NULL              |                             |
| stat_name        | varchar(64)         | NO   | PRI | NULL              |                             |
| stat_value       | bigint(20) unsigned | NO   |     | NULL              |                             |
...
+------------------+---------------------+------+-----+-------------------+-----------------------------+
```

Statistics in this table are identified by the `stat_name` field; in our case, the related one is `size`, which represents the number of database pages required to store the index.
In order to get the index size in bytes, we use the InnoDB page size, which is stored in the global (read-only) variable `innodb_page_size`.

The query and the results are therefore:

```sql
SELECT table_name, index_name, stat_value*@@innodb_page_size `size`
FROM mysql.innodb_index_stats
WHERE stat_name = 'size'
      AND (database_name, table_name, index_name) = ('test', 'reservations', 'allocation_id')
;
```

```
+--------------+---------------+-----------+
| table_name   | index_name    | size      |
+--------------+---------------+-----------+
| reservations | allocation_id | 278691840 |
+--------------+---------------+-----------+
```

The result is 7% more, which is non-negligible (as a low-hanging fruit).

## Cleaning up a real world table

This is the (anonymized) structure of a table of ours, with the first block highlighting the relevant columns and indexes:

```sql
CREATE TABLE `items` (
  `type` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `number` int(11) NOT NULL DEFAULT '0',
  `amount` float DEFAULT NULL,
  `tenant_id` int(11) DEFAULT NULL,
  `lock_version` int(11) DEFAULT '0',
  `report` varchar(4096) DEFAULT NULL,
  `params` varchar(4900) DEFAULT '--- {}\n\n',
  `discount_id` int(11) DEFAULT NULL,
  `discount_type` varchar(64) DEFAULT NULL,
  `explicit` tinyint(1) DEFAULT '0',
  KEY `index_line_items_on_account_id` (`account_id`),
  KEY `index_line_items_on_discount_source_id_and_discount_source_type` (`discount_source_id`,`discount_source_type`),

  `id` int(11) NOT NULL AUTO_INCREMENT,
  `field_01` int(11) DEFAULT NULL,
  `field_02` int(11) DEFAULT NULL,
  `field_03` int(11) DEFAULT NULL,
  `field_04` float NOT NULL DEFAULT '0',
  `field_05` int(11) DEFAULT NULL,
  `field_05` int(11) DEFAULT NULL,
  `field_07` int(11) DEFAULT '1',
  `field_08` int(11) DEFAULT NULL,
  `field_09` float DEFAULT '0',
  `field_10` int(11) DEFAULT NULL,
  `field_11` tinyint(1) NOT NULL DEFAULT '0',
  `field_12` decimal(13,9) NOT NULL DEFAULT '0.000000000',
  `field_13` int(11) DEFAULT NULL,
  `field_14` int(11) DEFAULT NULL,
  `field_15` char(36) NOT NULL,
  `field_16` int(11) DEFAULT NULL,
  `field_17` varchar(64) NOT NULL,
  `field_18` char(36) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_line_items_on_field_18` (`field_18`),
  KEY `line_items_field_01_index` (`field_01`),
  KEY `line_items_field_03_index` (`field_03`),
  KEY `index_line_items_on_field_10` (`field_10`),
  KEY `index_line_items_on_field_02` (`field_02`),
  KEY `index_line_items_on_field_05` (`field_05`),
  KEY `index_line_items_on_field_05` (`field_05`),
  KEY `index_line_items_on_field_08` (`field_08`),
  KEY `index_line_items_on_field_13` (`field_13`),
  KEY `index_line_items_on_field_14` (`field_14`),
  KEY `index_line_items_on_field_16` (`field_16`),
  KEY `index_line_items_on_field_15` (`field_15`)
);
```

The table has ~22.4M records.

We perform the following cleanup on it:

```sql
ALTER TABLE items
  MODIFY type           VARCHAR(32) NOT NULL,
  MODIFY created_at     DATETIME NOT NULL,
  MODIFY number         TINYINT(4) NOT NULL DEFAULT 0,
  MODIFY amount         FLOAT NOT NULL,
  MODIFY tenant_id      SMALLINT UNSIGNED NOT NULL,
  MODIFY lock_version   INT NOT NULL DEFAULT 0,
  MODIFY report         VARCHAR(128),
  MODIFY params         VARCHAR(1536) DEFAULT '--- {}\n\n',
  MODIFY discount_id    INT NOT NULL,
  MODIFY discount_type  VARCHAR(24) NOT NULL,
  MODIFY explicit       TINYINT(1) NOT NULL DEFAULT 0
;
```

The changes affecting indexes are:

| column        | before      | after                |
| ------------- | ----------- | -------------------- |
| tenant_id     | INT         | INT NOT NULL         |
| discount_id   | INT         | INT NOT NULL         |
| discount_type | VARCHAR(64) | VARCHAR(24) NOT NULL |

And we measure the effect of the change (the suffixed name represent the various versions):

```sql
SELECT table_name, IF(index_name = 'PRIMARY', 'primary', 'secondary') `indexes_type`, SUM(stat_value*@@innodb_page_size) `size`
FROM mysql.innodb_index_stats
WHERE stat_name = 'size'
      AND database_name = 'test' AND table_name LIKE ('items_%')
GROUP BY table_name, indexes_type
;
```

```
+------------------+--------------+-------------+
| table_name       | indexes_type | size        |
+------------------+--------------+-------------+
| items_live       | primary      |  8288714752 |
| items_live       | secondary    |   517095424 |
| items_compacted  | primary      |  4077912064 |
| items_compacted  | secondary    |   373161984 |
| items_cleaned    | primary      |  3930062848 |
| items_cleaned    | secondary    |   295452672 |
+------------------+--------------+-------------+
```

When comparing the cleaned version to the reference (`compacted`) one:

- the primary (data) index saving is minor (3.6%)
- the index saving is significant, 20%

## Conclusion

In this article we've examined two aspects of InnoDB indexes, along with the tools for investigating:

1. indexes fragmentation;
2. effect of converting NULLable [indexed] fields to NOT NULL.

We made the following conclusions:

1. live indexes will generally fragment after some time; depending on the requirements, compacting them may save space and increase performance
2. converting an indexed field to NOT NULL can save considerable space, which is important for an index; therefore, (especially) indexed fields should be NOT NULL unless strictly necessary.


[Clustered indexes]: https://dev.mysql.com/doc/refman/5.7/en/innodb-index-types.html
[InnoDB INFORMATION_SCHEMA System Tables]: https://dev.mysql.com/doc/refman/5.7/en/innodb-information-schema-system-tables.html
[InnoDB Persistent Statistics Tables]: https://dev.mysql.com/doc/refman/5.6/en/innodb-persistent-stats.html#innodb-persistent-stats-tables
