---
layout: post
title: Shell scripting adventures (Part 1)
tags: [shell_scripting,sysadmin]
last_modified_at: 2017-11-08 20:50:00
---

This is the Part 1 (of 4) of the shell scripting adventures, introduced in the [previous post]({% post_url 2017-11-02-Shell-scripting-adventures-introduction %}).

The following subjects are described in this part:

- [Associative arrays (hash maps)](Shell-scripting-adventures-part-1#associative-arrays-hash-maps)
- [Escape strings](Shell-scripting-adventures-part-1#escape-strings)
- [Expand strings into separate options](Shell-scripting-adventures-part-1#expand-strings-into-separate-options)
- [Regular expressions matching](Shell-scripting-adventures-part-1#regular-expressions-matching)
- [Find a filename's basename](Shell-scripting-adventures-part-1#find-a-filenames-basename)
- [Replace the extension of a filename](Shell-scripting-adventures-part-1#replace-the-extension-of-a-filename)
- [Cycle a multi-line variable](Shell-scripting-adventures-part-1#cycle-a-multi-line-variable)
- [Heredoc](Shell-scripting-adventures-part-1#heredoc)

The examples are taken from my [RPi VPN Router project installation script](https://github.com/saveriomiroddi/rpi_vpn_router/blob/master/install_vpn_router.sh).

## Associative arrays (hash maps)

Associative arrays have been introduced in Bash 4; although shell scripting shouldn't reach the complexity of general-purpose, in some cases, scripts using A.A. can be still a convenient choice.

The syntax is unfortunately very cryptic.

An example convenient case is to collect some device links, mapped to the device names, so that they can be iterated after, the names accesses using the device link as key.

Instantiation:

    declare -A v_usb_storage_devices

Adding/reassigning a key/value pair:

    v_usb_storage_devices[$devname]=$model

Lookup:

    echo ${v_usb_storage_devices[$dev]}

Count:

    if [[ ${#v_usb_storage_devices[@]} > 0 ]] ; then
      echo "There are pairs!"
    fi

Iteration:

    for dev in "${!v_usb_storage_devices[@]}"; do
      echo ${v_usb_storage_devices[$dev]}
    done

For clearing, the easiest way is to unset the variable, then re-instantiate it:

    unset v_usb_storage_devices
    declare -A v_usb_storage_devices

## Escape strings

String can be quoted via `printf`:

    entries_option+=$(printf "%q" ${v_usb_storage_devices[$dev]})

## Expand strings into separate options

A use case is to build the parameters for a program, then execute it; this is perfomed by building a variable and passing it unquoted.

In the building process, where parameter quoting is required (since the variable itself will be unquoted), it is performed as described in the previous section, via `printf`.

In this (edited) example, the variable is `entries_option`, and the program is `whiptail`:

    for dev in "${!v_usb_storage_devices[@]}"; do
      entries_option+=" $dev "
      entries_option+=$(printf "%q" ${v_usb_storage_devices[$dev]})
      let entries_count+=1
    done
    
    whiptail --radiolist "$message" 30 100 $entries_count $entries_option

This will evaluate, for example, to:

    whiptail --radiolist "$message" 30 100 2 /dev/sdb Chinese\ USB\ Disk /dev/sdc Super\ Flash\ Card

## Regular expressions matching

Bash can match strings against regular expressions:

    if [[ $v_rpi_static_ip_on_modem_net =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      break
    fi

The left operand doesn't need quoting.

The example above will match an IP.

## Find a filename's basename

The basename of a filename (path, or also http address), can be found with another cryptic construct:

    c_os_archive_address=http://vx2-downloads.raspberrypi.org/.../2017-09-07-raspbian-stretch-lite.zip
    echo "${c_os_archive_address##*/}"

The above will result in `2017-09-07-raspbian-stretch-lite.zip`.

## Replace the extension of a filename

Replace the extension of a filename:

    os_archive_filename=2017-09-07-raspbian-stretch-lite.zip
    echo "${os_archive_filename%.zip}.img"

The above will result in `2017-09-07-raspbian-stretch-lite.img`.

## Cycle a multi-line variable

Cycling a multi-line variable is tricky. This is a solution:

    while IFS=$'\n' read -r partition_data; do
      message+="$partition_data"
    done <<< "$(mount)"

Description:

1. `IFS=$'\n'` will set the separator to `\n`
2. `read -r` reads the input (`-r` specifies not to interpret backslahes), separated by the `IFS` value, and writes the token for each cycle into `partition_data`
3. `<<< "$(mount)"` needs to be used instead of `mount | while IFS=$'\n' read -r partition_data`; in the second case, the while is executed in a subshell (due to the pipe), and message is not visible outside the while scope!

## Heredoc

Heredoc is a convenient construct to handle complex input.

Bash already supports multi-line string literals, but more complex cases it's messy to escape the quotes inside the literal. Heredoc allows the user to define an arbitrary delimiter:

        cat >> "$c_data_dir_mountpoint/etc/dhcpcd.conf" << EOS
    interface eth0
    static ip_address=$v_rpi_static_ip_on_modem_net/24
    static routers=$modem_ip
    static domain_name_servers=$v_pia_dns_server_1 $v_pia_dns_server_2
    EOS

The delimiter name, in this case `EOS`, is arbitrary.

There are a few important notes:

1. the base format interpolates the content; use the format `<< 'EOS'` for raw strings
2. the closing delimiter must not be indented; used the format `<<- EOS` for allowing indenting it, BUT the indentation **must be with tabs, not spaces**
3. finally, most importantly, (and often misunderstood), heredoc strings are sent to stdin - they're not literals in a strict sense; this is the reason why they're sometimes associated with cat, e.g. `cat << EOS | myprogram -myoptions...`

In order to assign a heredoc string to a variable, some trickery is required:

    read -r -d '' body << STR
    {
      "title": "$1",
      "body": "$2",
    }
    STR

The above will set the variable `$body` to the heredoc content, by piping it to `read`, which will read it and set it without delimiter (`-d ''`). Don't forget that in order to use the resulting variable correctly, it must be quoted (`"$body"`)!
