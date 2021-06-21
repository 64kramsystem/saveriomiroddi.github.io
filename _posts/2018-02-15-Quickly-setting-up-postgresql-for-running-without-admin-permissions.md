---
layout: post
title: Quickly setting up PostgreSQL for running without admin permissions
tags: [databases,postgresql,quick,sysadmin]
last_modified_at: 2020-01-30 22:19:00
---

It's very convenient to run service processes (for development purposes!) without admin permissions, rather starting it as system service.

This guide will show how to easily setup PostgreSQL (both via package and binary tarball) to be run by an unprivileged user, with the data in any directory owned by him/her.

Contents:

- [Setup notes/requirements](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#setup-notesrequirements)
- [Installation via apt package (Ubuntu)](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#installation-via-apt-package-ubuntu)
- [Installation via binary tarball (universal)](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#installation-via-binary-tarball-universal)
- [Persisting the PGSQL data location, and adding the binaries to the `$PATH`](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#persisting-the-pgsql-data-location-and-adding-the-binaries-to-the-path)
- [Conclusion](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#conclusion)

## Setup notes/requirements

The binary package section applies to Ubuntu, but it can be trivially adapted to other O/Ss; the binary tarball procedure is essentially universal.

The procedure is run as the local user, in a modern Bash shell; `sudo` is provided where required. The standard Unix tools (and Ruby) are used.

The `$PGDATA` directory name must not contain quotes (which would complicate the commands).

## Installation via apt package (Ubuntu)

First, set a few variables, for convenience:

```sh
$ PGSQL_VERSION=10
$ PGDATA="$HOME/databases/pgsql_data"
```

Both can be adjusted to the user preference.

Install the package, if not done already:

```sh
$ wget -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
$ echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list

$ sudo apt-get update
$ sudo apt-get install -y postgresql-$PGSQL_VERSION
```

Prevent the service from starting on boot (Ubuntu 16.04+ version):

```sh
$ sudo systemctl stop postgresql
$ sudo systemctl disable postgresql
```

Now, initialize the data/configuration/run directory:

```sh
$ "/usr/lib/postgresql/$PGSQL_VERSION/bin/initdb"
```

Set the run path in the main configuration file:

```sh
$ ruby -i -pe "sub /^#(unix_socket_directories = ).*/, %q(\1'$PGDATA')" "$PGDATA/postgresql.conf"
```

Note that we use Ruby for using slashes and quotes without having to perform complex quoting (with Perl/Sed, we would have to).

Now PostgreSQL can be started via:

```sh
$ "/usr/lib/postgresql/$PGSQL_VERSION/bin/pg_ctl" start
```

Ready to connect!:

```sh
$ psql -h localhost postgres
```

Check out the [last section](#persisting-the-pgsql-data-location-and-adding-the-binaries-to-the-path) for persisting the data location, and adding the binaries to the `$PATH`!

## Installation via binary tarball (universal)

First, variables setup:

```sh
$ PGSQL_TARBALL_LINK="https://get.enterprisedb.com/postgresql/postgresql-10.10-1-linux-x64-binaries.tar.gz"
$ PGDATA="$HOME/databases/pgsql_data"
$ LOCAL_LIB="$HOME/local"
```

The `$LOCAL_LIB` path is the preferred location for software used by the current user only.

For the latest PGSQL version, check the [download page](https://www.enterprisedb.com/download-postgresql-binaries).

Download and uncompress the tarball:

```sh
$ wget "$PGSQL_TARBALL_LINK" -O "/tmp/${PGSQL_TARBALL_LINK##*/}"
$ tar xv -C "$LOCAL_LIB" -f !$
```

Initialize the data/configuration/run directory:

```sh
$ "$LOCAL_LIB/pgsql/bin/initdb"
```

With the binary tarball version, we don't need to change any configuration!

Now, start PostgreSQL:

```sh
$ "$LOCAL_LIB/pgsql/bin/pg_ctl" start
```

and connect via client:

```sh
$ "$LOCAL_LIB/pgsql/bin/psql" -h localhost postgres
```

Check out the [last section](#persisting-the-pgsql-data-location-and-adding-the-binaries-to-the-path) for persisting the data location, and adding the binaries to the `$PATH`!

## Persisting the PGSQL data location, and adding the binaries to the `$PATH`

In order to persist the PGSQL data location, and add the binaries to the `$PATH` for convenience, we need to extend the shell init scripts.

Shell init scripts vary slightly depending on the login conditions/configuration. For simplicity, extend `$HOME/.bashrc`.  
Also note that the following commands use the previously set environment variables.

The env variable `$PGDATA` tells PGSQL where the data resides:

```sh
$ echo "export PGDATA=$(printf "%q" "$PGDATA")" >> "$HOME/.bashrc"
```

It's convenient to have the PGSQL binaries in the path as well, in order to avoid having to write the full path each time:

```sh
# For apt package installations
$ echo "export PATH=/usr/lib/postgresql/$PGSQL_VERSION/bin:\$PATH" >> "$HOME/.bashrc"

# For binary tarball installations
$ echo "export PATH=$LOCAL_LIB:\$PATH" >> "$HOME/.bashrc"
```

## Conclusion

Have fun with PostgreSQL!
