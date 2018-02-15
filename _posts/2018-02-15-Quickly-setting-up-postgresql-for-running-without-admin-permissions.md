---
layout: post
title: Quickly setting up PostgreSQL for running without admin permissions
tags: [databases,postgresql,sysadmin]
---

It's very convenient to run service processes (for development purposes!) without admin permissions, rather starting it as system service.

This guide will show how to easily setup PostgreSQL (both via package and binary tarball) to be run by an unprivileged user, with the data in any directory owned by him/her.

Contents:

- [Setup notes/requirements](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#setup-notesrequirements)
- [Installion via apt package (Ubuntu)](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#installion-via-apt-package-ubuntu)
- [Installion via binary tarball](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#installion-via-binary-tarball)
- [Conclusion](/Quickly-setting-up-postgresql-for-running-without-admin-permissions#conclusion)

## Setup notes/requirements

The binary package section applies to Ubuntu, but it can be trivially adapted to other O/Ss; the binary tarball procedure is essentially universal.

The procedure is run as the local user, in a modern Bash shell; `sudo` is provided where required. The standard Unix tools (and Ruby) are used.

The `$PGDATA` directory name must not contain quotes (which would complicate the commands).

## Installion via apt package (Ubuntu)

First, set a few variables, for convenience:

```sh
$ export PGSQL_VERSION=10
$ export PGDATA="$HOME/databases/pgsql_data"
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

For convenience, the `pg_ctl` binary can be symlinked to the `$HOME/bin` directory (which, in Ubuntu, is in the default `$PATH`):

```sh
$ mkdir -p "$HOME/bin"
$ ln -s "/usr/lib/postgresql/$PGSQL_VERSION/bin/pg_ctl" !$
```

Now PostgreSQL can be started via:

```sh
$ pg_ctl start
```

Ready to connect!:

```sh
$ psql -h localhost postgres
```

## Installion via binary tarball

First, variables setup:

```sh
$ export PGDATA="$HOME/databases/pgsql_data"
$ export LOCAL_LIB="$HOME/local"
$ export PGSQL_VERSION=10
$ export PGSQL_TARBALL_LINK="https://get.enterprisedb.com/postgresql/postgresql-10.2-1-linux-x64-binaries.tar.gz"
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

Symlink the `postgres`/`psql` binaries:

```sh
$ mkdir -p "$HOME/bin"
$ ln -s "$LOCAL_LIB/pgsql/bin/pg_ctl" !$
$ ln -s "$LOCAL_LIB/pgsql/bin/psql" !$
$ ln -s "$LOCAL_LIB/pgsql/bin/psql.bin" !$
```

Now, start PostgreSQL:

```sh
$ pg_ctl start
```

and connect via client:

```sh
$ psql -h localhost postgres
```

## Conclusion

Have fun with PostgreSQL!
