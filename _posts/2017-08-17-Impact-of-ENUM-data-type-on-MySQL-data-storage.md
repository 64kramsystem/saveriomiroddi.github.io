---
layout: post
title: Impact of ENUM data type on MySQL data storage
tags: [mysql, data_types, indexes, storage, performance, databases]
---

In the vein of the [previous article][Previous article], we'll examine here the impact of using the [ENUM][ENUM type] data type.

Such data type is very interesting, although it requires a careful examination, since it has very important design implications.

## VARCHAR vs ENUM

The ENUM data type is stored in two locations:

1. the set of values is stored in the table metadata;
2. in each row, only the set index is stored, as integer, which requires one byte for enums up to 255 entries large, then two for up to 65535 entries (see [MySQL reference][Data type storage requirements])

The difference compared to using a (VAR)CHAR are significant. Suppose a column defined as `latin1 VARCHAR NOT NULL`, with an average string length of 6 bytes (which requires 1 extra byte due to VARCHAR), and a million rows, we save:

    10^6 * (7-1) = 60 out of 70 MB (~86%)

In addition to the space saved, there is a performance improvement in related indexes scanning due to:

1. smaller footprint;
2. comparing integers is computationally faster than comparing strings.

It's always important to be aware that any performance consideration should always be measured - if performance is the target - as such improvement may be negligible. There are a couple of articles on performance:

- [Enum Fields VS Varchar VS Int + Joined table: What is Faster?][Percona article]
- [Using the ENUM data type to increase performance][ENUM performance increase article]

They explore different use cases and outcomes.

## Design considerations

When searching for ENUM, one of the top articles is [8 Reasons Why MySQL's ENUM Data Type Is Evil][Evil ENUM article].

Before talking about it, it's crucial to know that one of the points (#2) is partially obsolete - in modern MySQL versions, adding an entry to the set does not require a table rebuild.

Having said that, while the points raised by the article are valid, ultimately, I take ENUM as a tool: unless it implicitly promotes for bad design (a famous example being Visual Basic 6, with [lack of separation of concerns][VB6 No separation of concerns] and [On Error Resume Next][VB6 On Error Resume Next]), I'm neutral toward a tool in itself.

In particular, one use case is worth exploring: polymorphic associations.

## Real world example: Polymorphic associations

One design pattern is polymorphic associations; this is a (simplified) example of the underlying structure of a widespread Rails gem:

    CREATE TABLE taggings (
      id            int(11) NOT NULL AUTO_INCREMENT,
      tag_id        int(11) NOT NULL,
      taggable_id   int(11) NOT NULL,
      taggable_type varchar(255) NULL,
      PRIMARY KEY (id),
      KEY index_taggings_on_tag_id_and_taggable_type (tag_id, taggable_type),
      KEY index_taggings_on_taggable_id_and_taggable_type (taggable_id,taggable_type)
    );

and some column/rows statistics:

    SELECT AVG(CHAR_LENGTH(taggable_type)) `average_size`, COUNT(*) FROM taggings `count`;

    +--------------+----------+
    | average_size | count    |
    +--------------+----------+
    |       5.3578 | 30601263 |
    +--------------+----------+

There are a few elements that make this case a good candidate:

- the entries are (relatively) very static; they don't change due to typical human factors, as they are model names, and if a new model is introduced, addition is not expesive;
- the `taggable_type` field takes a (relatively) significant part of the data, both in the rows and in the (composite) index;
- this table/model tends to grow very large, so it's a good candidate for optimization.

We'll use the following tweaked query to aggregate the results:

    SELECT table_name, index_name, SUM(ROUND(stat_value*@@innodb_page_size/1048576, 2)) `size`
    FROM mysql.innodb_index_stats
    WHERE stat_name = 'size'
          AND (database_name, table_name) = ('temp', '_copy_taggings')
    GROUP BY table_name, index_name
    WITH ROLLUP
    HAVING table_name IS NOT NULL;

As mentioned previously, in InnoDB, the rows are kept in an index, `PRIMARY`.

This is the index statistics before the change (after having rebuilt the table):

    +----------------+-------------------------------------------------+---------+
    | table_name     | index_name                                      | size    |
    +----------------+-------------------------------------------------+---------+
    | _copy_taggings | PRIMARY                                         | 1322.98 |
    | _copy_taggings | index_taggings_on_tag_id_and_taggable_type      |  668.98 |
    | _copy_taggings | index_taggings_on_taggable_id_and_taggable_type |  668.98 |
    | _copy_taggings | NULL                                            | 2660.94 |
    +----------------+-------------------------------------------------+---------+

ALTER TABLE[s]:

    ALTER TABLE _copy_taggings MODIFY taggable_type ENUM(
        'Cart','Customer','Discount','Event','LineItem','Order','Payment','Product','Show','Subdomain',
        'TicketAllocation','TicketPrice','User','Venue'
      ) NOT NULL;

And the index statistics after the change (after having rebuilt the table):

    +----------------+-------------------------------------------------+---------+
    | table_name     | index_name                                      | size    |
    +----------------+-------------------------------------------------+---------+
    | _copy_taggings | PRIMARY                                         | 1130.98 |
    | _copy_taggings | index_taggings_on_tag_id_and_taggable_type      |  488.98 |
    | _copy_taggings | index_taggings_on_taggable_id_and_taggable_type |  488.98 |
    | _copy_taggings | NULL                                            | 2108.94 |
    +----------------+-------------------------------------------------+---------+

There is a significant reduction in size:

- 15% on the rows;
- 27% on each of the two indexes;
- an overall 21% on the whole table.

This is a significant size reduction.

Of course, this is not always the case. On our generic settings table, which has 10 columns, and the following statistics:

    SELECT AVG(CHAR_LENGTH(resource_type)) `average_type_size`, AVG(CHAR_LENGTH(value)) `average_value_size`, COUNT(*) `count`
    FROM settings;

    +-------------------+--------------------+-------+
    | average_type_size | average_value_size | count |
    +-------------------+--------------------+-------+
    |            6.0933 |           384.1169 | 70017 |
    +-------------------+--------------------+-------+

The saving would be around 1%, which is not worth considering.

## Conclusion

Although ENUM must be used very carefully, we've identified a (common) use case where there is a significant gain in using it, at virtually no cost.
All conditions considered, we believe that using ENUM for this use case is very convenient, and that it's worth analyzing similar cases when designing the schema.

[Previous article]: {% post_url 2017-08-01-Data-storage-analysis-and-optimization-of-InnoDB-indexes %}
[ENUM type]: https://dev.mysql.com/doc/refman/5.7/en/enum.html
[Data type storage requirements]: https://dev.mysql.com/doc/refman/5.7/en/storage-requirements.html
[Percona article]: https://www.percona.com/blog/2008/01/24/enum-fields-vs-varchar-vs-int-joined-table-what-is-faster
[ENUM performance increase article]: https://web.archive.org/web/20161025132529/http://fernandoipar.com/mysql/2009/03/09/using-the-enum-data-type-to-increase-performance.html
[Evil ENUM article]: http://komlenic.com/244/8-reasons-why-mysqls-enum-data-type-is-evil
[VB6 No separation of concerns]: https://www.quora.com/Why-do-most-programmers-consider-Visual-Basic-a-bad-programming-language/answer/Philip-Stuyck
[VB6 On Error Resume Next]: http://www.developerfusion.com/code/4325/on-error-resume-next-considered-harmful
