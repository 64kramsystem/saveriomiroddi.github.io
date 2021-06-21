---
layout: post
title: Installing MySQL 5.7.19 on Ubuntu 14.04
tags: [mysql, sysadmin, quick]
category: mysql
last_modified_at: 2017-12-23 12:42:00
---

MySQL 5.7.19 fixes a [quite dangerous functionality](https://bugs.mysql.com/bug.php?id=84375) that causes corruption of a slave when changing the delay (`CHANGE MASTER TO MASTER_DELAY=<seconds>`) while the slave threads are stopped; since one wouldn't expect this condition to cause harm, users of such setup should upgrade, if possible.

Users trying to perform the update on Ubuntu 14.04 LTS will face the mysql service not starting.

## Diagnosis and solution

Starting via `/etc/init.d/mysqld.server` will exit without reporting anything in the log, so we'll start `mysqld` directly, which will reveal the problem:

```sh
/usr/lib/x86_64-linux-gnu/libstdc++.so.6: version `GLIBCXX_3.4.20' not found
```

The cause is that v5.7.19 requires a version of `libstdc++6` more recent than the one available in Ubuntu 14.04 (6.0.19).

Some users have dangerously tried to use a PPA that includes an updated version of the compiler toolchain (`ppa:ubuntu-toolchain-r/test`); this is discouraged. The safest way is to download and store this library separately, and add the path to the shared libraries load path.

The official Ubuntu 16.04 (Xenial) package contains the library; a reasonable strategy is to download the package, extract the library, and change the path in the MySQL startup script (`/etc/init.d/mysql.server`, or any other path where this file is located).

Execution:

```sh
# Run everything as root

export MYSQL_PATH=/usr/local/mysql     # change to match the MySQL installation path
export TEMP_PATH=/tmp/mysql_lib_update # change at will

mkdir -p $TEMP_PATH

wget http://security.ubuntu.com/ubuntu/pool/main/g/gcc-5/libstdc++6_5.4.0-6ubuntu1~16.04.4_amd64.deb -O $TEMP_PATH/libstdc.deb

cd $TEMP_PATH
ar xv libstdc.deb
tar xvf data.tar.xz

mv ./usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.21 $MYSQL_PATH/lib/
ln -s libstdc++.so.6.0.21 $MYSQL_PATH/lib/libstdc++.so.6

awk "NR==1{print; print \"export LD_LIBRARY_PATH=$MYSQL_PATH/lib:\$LD_LIBRARY_PATH\"} NR!=1" /etc/init.d/mysql.server > $TEMP_PATH/mysql.server.fixed
cat $TEMP_PATH/mysql.server.fixed > /etc/init.d/mysql.server
```

The strategy of the last block is to modify the path in the second line of the init script, which is very simple and "good enough".

Note that awk 4.1 supports in-place editing, but Ubuntu 14.04 comes with 4.0.

After this modification, it will be possible to use the `mysql.server` init script as usual.

For curiosity, one can verify that the new library is compatible, by inspecting the library strings:

```sh
$ strings $MYSQL_PATH/lib/libstdc++.so.6 | grep GLIBCXX
GLIBCXX_3.4
...
GLIBCXX_3.4.20   # Found!
```
