---
layout: post
title: Installing MySQL 5.7.19 on Ubuntu 14.04
tags: [mysql, sysadmin, trivia]
---

MySQL 5.7.19 fixes a [quite dangerous functionality](https://bugs.mysql.com/bug.php?id=84375), which caused corruption of a slave when changing the delay (`CHANGE MASTER TO MASTER_DELAY`) under certain conditions.

Users trying to update on Ubuntu 14.04 LTS will face an error when starting the service (in a quite puzzling fashion, as the daemon will exit without reporting anything in the log).

## Cause and solution

The cause is that v5.7.18 requires a version of `libstdc++6` (6.0.20) more recent than the one available in Ubuntu 14.04 (6.0.19).

Some users have dangerously tried to use a PPA which upgrades such package; this is discouraged. The safest way is to download and store this library separately, and add the path to the shared libraries load path.

This solution simply uses the library version from the official Ubuntu Xenial repository, and places in the MySQL own library path:

    export MYSQL_PATH=/usr/local/mysql     # change to match the MySQL installation path
    export TEMP_PATH=/tmp/libstdc          # change at will
    
    mkdir -p $TEMP_PATH
    
    wget http://security.ubuntu.com/ubuntu/pool/main/g/gcc-5/libstdc++6_5.4.0-6ubuntu1~16.04.4_amd64.deb -O $TEMP_PATH/libstdc.deb

    cd $TEMP_PATH
    ar xv libstdc.deb
    tar xvf data.tar.xz
    
    mv ./usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.21 $MYSQL_PATH/lib/
    ln -s libstdc++.so.6.0.21 $MYSQL_PATH/lib/libstdc++.so.6

Now, you'll need to specify the load path in the `/etc/init/mysql.server`; the most trivial way is to add it to the second line:

    awk -i inplace "NR==1{print; print \"export LD_LIBRARY_PATH=$MYSQL_PATH/lib:\$LD_LIBRARY_PATH\"} NR!=1" /etc/init.d/mysql.server

This will solve the problem.
