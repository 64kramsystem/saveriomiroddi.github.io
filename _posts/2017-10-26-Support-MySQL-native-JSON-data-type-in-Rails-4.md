---
layout: post
title: Support MySQL native JSON data type in Rails 4
tags: [mysql, data_types, rails]
last_modified_at: 2017-10-31 10:35:28
---

Mysql 5.7 added native support for JSON data type. This opens up several interesting possibilities, but it's not natively supported in Rails 4 (only in 5).

In this article, I'll explain how to implement it.

## Introduction

In Rails 5, representing a field in JSON is fairly easy:

    serialiaze :my_json_attribute, JSON

This is not possible in Rails 4, because this version does't natively understand the data type, deserializing it into a string.

Adding a new data type is fairly easy, though; I've used the following ActiveRecord files are reference:

    /path/to/activerecord_gem/lib/active_record/attributes.rb
    /path/to/activerecord_gem/lib/active_record/type/value.rb
    /path/to/activerecord_gem/lib/active_record/type/mutable.rb

This guide will assume recent versions of Rails 4 and MySQL 5.7.

## Implementation

In the basic form, implementing a new data type consist of coding the rules for translating to/from database and user.

Create this initializer (e.g. `config/initializers/json_data_type.rb`)

    module ActiveRecord
      module Type
        class Json < Type::Value
          include Type::Mutable

          def type
            :json
          end

          def type_cast_for_database(value)
            case value
            when Hash
              value.to_json
            when ::String
              value
            else
              raise "Unsupported data/type for JSON conversion: #{value.class}"
            end
          end

          private

          def type_cast(value)
            case value
            when nil
              {}
            when ::String
              parsed_value = JSON.parse(value)

              if parsed_value.is_a?(Hash)
                parsed_value.deep_symbolize_keys
              else
                raise "Only Hashes are supported (or their string representation)"
              end
            when Hash
              value.deep_symbolize_keys
            else
              raise "Unsupported data/type for JSON conversion: #{value.class}"
            end
          end
        end
      end
    end

add a field in the ActiveRecord desired model:

    class MyModel
      serialize :my_json_attribute, ActiveRecord::Type::Json.new
    end

and create a migration:

    class AddMyJsonAttributeToMyModel < ActiveRecord::Migration
      def up
        add_column :my_models, :my_json_attribute, :json
        MyModel.update_all('my_json_attribute = "{}"')
      end
    
      def down
        remove_column :my_models, :my_json_attribute
      end
    end

Now I'll break it down; the gotchas will be explained in the next section.


First we define the type:

    def type
      :json
    end

this will uniquely identify the data type; for example, it allows Rails to create a migration using the standard form (see above).

Then we need to define the type casting methods. Rails supports more granular casting, but for simple data types, we just need to define two methods (here in edited format:

    include Type::Mutable
    def type_cast_for_database(value)
      case value
      when Hash
        value.to_json
      when ::String
        value
      ...
      end
    end
    
    def type_cast(value)
      case value
      when ::String
        parsed_value = JSON.parse(value)

        if parsed_value.is_a?(Hash)
          HashWithIndifferentAccess.new(parsed_value)
        ...
      when Hash
        HashWithIndifferentAccess.new(parsed_value)
      ...
      end
    end

First of all, we need to take a design decision: we'll accept, for simplicity, only hashes and strings, and reject other data types.

The first method, `type_cast_for_database`, performs the conversion from the in-memory value to the value to be sent to the database.  
We'll simply convert the hash to a JSON string (note that Hash#to_json returns a String). Some cases (eg. `update_all`) can send a value without going through `type_cast` before, so we also support String values.

The second, `type_cast`, performs both the conversion from user and database-read values. In this case, we allow the user to pass strings/hashes (when reading from the database, ActiveRecord will receive strings).

There is here a second, crucial design decision: since symbols are a Ruby concept not included in JSON, it's important to decide what to do with the hash keys passed (other literal values also suffer this problem, but it can be somewhat ignored, at least, in the basic form). In this case, we use HashWithIndifferentAccess, but other options are possible, depending on the requirements, e.g. raising an error when an unexpected key type is received, or using (deep) keys conversion.

The `include Type::Mutable` module automatically adds a method (`changed_in_place?`) which detects differences between the old and new values when persisting the value.

Specifying the attribute in a model is trivial (more on this in the gotchas section):

    serialize :my_json_attribute, ActiveRecord::Type::Json.new

and so is creating the migration:

    add_column :my_models, :my_json_attribute, :json
    MyModel.update_all('my_json_attribute = "{}"')

while taking care of resetting the value that MySQL adds by default (`null`), since we designed the column to only accept hashes.  
MySQL doesn't accept a default for JSON columns.

### Gotchas

There are a couple of gotchas to take care of.

#### Default value

Ideally, we'd like the column to be NOT NULL. For this, we need to set a default. Although `serialize()` supports a default, it doesn't work well in this case, for two problems:

1. on the first persistence, `changed_in_place?()` will be called; it will find the old value to be `{}` (because it's the default), and the new value to be the same, therefore, ActiveRecord won't include the column in the INSERTed ones;
2. we can work this around by setting the default to `'{ }'` (with a space): the method `changed_in_place?()` will compare it against `{ }` (since it will serialize and deserialize the value for comparison); for unclear reasons, the default value will be set on `MyModel.new()`, but not on `MyModel.create!()`

Due to these problems, we'll need to set the column as nullable. On top of this, we'll need to allow `nil` when reading db (/user) input:

    def type_cast(value)
      case value
      when nil
        {}
      ...
    end

so that the `NULL` for the db is converted to an empty hash.

#### MySQL decimal normalization

MySQL will normalize decimal numbers with zero fractional (e.g. `5.0`) to integers, therefore, changing the data type on save.

It's not clear if this is a bug - it should, but even if not, it's not documented.

See [relevant bug](https://bugs.mysql.com/bug.php?id=88230).

## Conclusion

While a company is taking the time to migrate to Rails 5, by using custom data types - and caring about the rough edges - it's currently possible to implement easily and work smoothly with the JSON data type, opening up several interesting possibilities.

## Extra: References on working with JSON in MYSQL 5.7

Some introductory references on JSON in MySQL 5.7:

- [MySQL 5.7 Introduces a JSON Data Type](https://lornajane.net/posts/2016/mysql-5-7-json-features)
- [How to Use JSON Data Fields in MySQL Databases](https://www.sitepoint.com/use-json-data-fields-mysql-databases/)
- [JSON document fast lookup with MySQL 5.7](https://www.percona.com/blog/2016/03/07/json-document-fast-lookup-with-mysql-5-7/)

*Edited 2017-10-31: Added String case in `type_cast_for_database`*
