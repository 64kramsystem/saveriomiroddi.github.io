---
layout: post
title: Dropping a database column in production without waiting time and/or schema-aware code, on a MySQL/Rails setup
tags: [ruby,rails,mysql,databases]
category: mysql
---

We recently had to drop a column in production, from a relatively large (order of 10⁷ records) table.

On modern MySQL setups, dropping a column doesn't lock the table (it does, actually, but for a relatively short time), however, we wanted to improve a very typical Rails migration scenario in a few ways:

1. offloading the column dropping time from the deploy;
2. ensuring that in the time between the column is dropped and the app servers restarted, the app doesn't raise errors due to the expectation that the column is present;
3. not overloading the database with I/O.

I'll give the Gh-ost tool a brief introduction, and show how to fulfill the above requirements in a simple way, by using this tool and an ActiveRecord flag.

This workflow can be applied to almost any table alteration scenario.

Contents:

- [Gh-ost](/Dropping-a-database-column-in-production-without-waiting-time-and-or-schema-aware-code-on-a-mysql-rails-setup#gh-ost)
- [Setup and workflow](/Dropping-a-database-column-in-production-without-waiting-time-and-or-schema-aware-code-on-a-mysql-rails-setup#setup-and-workflow)
  - [Existing configuration](/Dropping-a-database-column-in-production-without-waiting-time-and-or-schema-aware-code-on-a-mysql-rails-setup#existing-configuration)
  - [Configure ActiveRecord for ignoring the column, and performing the deploy](/Dropping-a-database-column-in-production-without-waiting-time-and-or-schema-aware-code-on-a-mysql-rails-setup#configure-activerecord-for-ignoring-the-column-and-performing-the-deploy)
  - [Using gh-ost to drop the column](/Dropping-a-database-column-in-production-without-waiting-time-and-or-schema-aware-code-on-a-mysql-rails-setup#using-gh-ost-to-drop-the-column)
  - [Remove the `ignored_columns` and redeploy](/Dropping-a-database-column-in-production-without-waiting-time-and-or-schema-aware-code-on-a-mysql-rails-setup#remove-the-ignored_columns-and-redeploy)
- [Conclusion](/Dropping-a-database-column-in-production-without-waiting-time-and-or-schema-aware-code-on-a-mysql-rails-setup#conclusion)

## Gh-ost

Gh-ost is a relatively recent tool by GitHub, which allows online table modifications without locking.

Tools like gh-ost existed before - the first being `mk-online-schema-change` (now `pt-online-schema-change`), developed by Percona.

The Percona tool relies on triggers in order to achieve the objective, which is a good enough, stable, solution. However, there are a [variety of reasons](https://github.com/github/gh-ost/blob/master/doc/why-triggerless.md) that (can) make the tool inadequate for high-load conditions.

Gh-ost introduced the novel idea of reading from the binary log (which logs all the write operation) in order to reproduce the writes on the temporary table.

Gh-ost can be run in different setups; this article will show the simplest one.

## Setup and workflow

### Existing configuration

Let's assume the following table:

```sql
CREATE TABLE `customers` (
  --- column definitions
  `source_id` int(11) NOT NULL,
  -- index definitions
  KEY `index_customers_on_source_id` (`source_id`)
);
```

with the corresponding model:

```ruby
class Customer < ApplicationRecord
  # model content
end
```

and migration:

```ruby
class DropCustomersSourceId < ActiveRecord::Migration
  def change
    remove_column :customers, :source_id
  end
end
```

### Configure ActiveRecord for ignoring the column, and performing the deploy

First, we tackle point #2. Let's have a look at the stages of a typical deploy with migrations:

1. the deploy starts: various operations are performed, including copying the new codebase to a release directory, without the app servers actually (re)loading it;
2. the migrations are executed - in this case, with an underlying `ALTER TABLE` statement, which will take a long time;
3. the _current_ release directory is linked to the new codebase, and the app servers (processes) are restarted;
4. other operations are performed.

The problem is that between the stages 2. and 3. (and also, depending on the app server configuration, during the processes restart), the app servers will have in memory the old version of the codebase, which expects `customers.source_id` to be present.

Although this time is relatively short, on a high-load environment, if a `Customer` instance is saved, the operation will fail, because ActiveRecord will include the column in the underlying INSERT.

In systems engineering, schema-aware code strategy is sometimes applied: essentially, writing code in the form "if the schema is `foo`, do `bar`, otherwise, do `baz`".

In the case of a column drop, we have at our disposal a "cheap" schema-aware strategy: `ignored_columns` (see the [Rails PR](https://github.com/rails/rails/pull/21720)).

This directive makes ActiveRecord entirely ignore a column, so that the column can disappear at any time, without ActiveRecord noticing.

Let's update the model:

```ruby
class Customer < ApplicationRecord
  self.ignored_columns = %w(source_id)
  # model content
end
```

and the migration:

```ruby
class DropcustomersSourceId < ActiveRecord::Migration[5.2]
  def change
    remove_column :customers, :source_id unless is_production_environment?
  end

  def is_production_environment?
    # choose strategy
  end
end
```

We can now perform the deploy; this time, the table column will not be dropped. After the deploy, we will use gh-ost, as outlined in the next section.

### Using gh-ost to drop the column

Gh-ost is pretty straightforward to use. In this context it's used in the simplest way possible, that is, running directly on master.

Note that there are many options available, including:

- sharing the load with slaves,
- regulating the I/O load,
- not including the password in the command (for security reasons).

A summary document is available [here](https://github.com/github/gh-ost/blob/master/doc/cheatsheet.md); gh-ost has good documentation.

The sample command we use is:

```sh
$ GHOST_TABLE="customers"
$ GHOST_ALTER="DROP source_id"

$ gh-ost \
    --user="$GHOST_USER" --password="$GHOST_PASSWORD" --host="$GHOST_HOST" \
    --database="$GHOST_SCHEMA" --table="$GHOST_TABLE" --alter="$GHOST_ALTER" \
    --allow-on-master --exact-rowcount --verbose --execute
```

The options are clear; `--exact-rowcount` will trade a little execution time for more accurate progress estimation.

Gh-ost will create a temporary (in a logical, not SQL, sense) table, slowly fill it and update with original table updates, then swap (with negligible locking time) them.

A crucial detail is that gh-ost will leave the original table in the database, renamed (in this case, `_customers_del`).

Although there is an option to drop the table automatically, **do not enable it or do not attempt to do it manually**: dropping a large table creates a large amount of I/O, due to MySQL freeing the pool pages, which will likely halt the database system to a grind for some time. Instead, one should follow a progressive table drop workflow:

- drop the indexes (optionally, individually);
- delete the records in batches;
- drop the (now empty) table.

Between each drop/deletion, `SLEEP` calls should be performed, in order to ensure that the writes are fully flushed.

Internally, we have a script for this, and it's advised to find or develop something similar.

Of course, `SLEEP` can be replaced with sophisticated strategies (eg. relying on the server statistics to track the I/O), however, in our system, `SLEEP` is a perfectly adequate while simple strategy.

### Remove the `ignored_columns` and redeploy

At this point, in production, Rails will be completely unaware of the existence (or not) of the column (being) dropped.

After the column is dropped, we can remove the `Customer.ignored_columns` directive, and deploy any time (or even wait for the next deploy).

## Conclusion

We've been using gh-ost for a long time by now, and we've developed a surrounding tooling ecosystem.

Once one gets used to such workflows, it's actually satisfying to perform "push-button" table alterations without any locking or performance drop in general, instead of being worried of the impact of (relatively) large-scale db operations.

Paraphrasing the typical joke:

- Did you notice the downtime today during the migration?
- WHAT!?! NO!
- Exactly.

;-)
