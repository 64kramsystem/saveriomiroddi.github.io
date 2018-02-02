---
layout: post
title: Shell scripting adventures (Part 3, Terminal-based dialog boxes&colon; Whiptail)
tags: [gui,shell_scripting,sysadmin]
---

This is the Part 3 (of 5) of the shell scripting adventures, introduced in a [previous post]({% post_url 2017-11-02-Shell-scripting-adventures-introduction %}).

The following subjects are described in this part:

- [Introduction to Whiptail](/Shell-scripting-adventures-part-3#introduction-to-whiptail)
- [Widgets, with snippets](/Shell-scripting-adventures-part-3#widgets-with-snippets)
  - [Message box](/Shell-scripting-adventures-part-3#message-box)
  - [Yes/no box](/Shell-scripting-adventures-part-3#yesno-box)
  - [Gauge](/Shell-scripting-adventures-part-3#gauge)
  - [Radio list](/Shell-scripting-adventures-part-3#radio-list)
- [Other widgets](/Shell-scripting-adventures-part-3#other-widgets)
  - [Input box](/Shell-scripting-adventures-part-3#input-box)
  - [Text box](/Shell-scripting-adventures-part-3#text-box)
  - [Password box](/Shell-scripting-adventures-part-3#password-box)
  - [Menus](/Shell-scripting-adventures-part-3#menus)
  - [Check list](/Shell-scripting-adventures-part-3#check-list)

Since Whiptail is simple to use, the objective of this post is rather to show some useful code snippets/patterns.

The examples are taken from my [RPi VPN Router project installation script](https://github.com/saveriomiroddi/rpi_vpn_router/blob/master/install_vpn_router.sh).

## Introduction to Whiptail

Whiptail is a dialog boxes program, with some useful widgets, which makes shell scripting more user-friendly; it's included in all the Debian-based distributions.

## Widgets, with snippets

### Message box

The message box shows a message, waiting for the user to hit the OK button:

 ![Message box]({{ "/images/2017-12-23-Shell-scripting-adventures-part-3/message_box.png" }})

Command:

```sh
$ message="Hello! This script will prepare an SDCard for using un a RPi3 as VPN router.
>
> Please note that device events (eg. automount) are disabled during the script execution."

$ whiptail --msgbox --title "Introduction" "$message" 20 78
```

The parameters are:

- `--title` specifies the title;
- then, the body message;
- finally, the last two parameters specify height and width, in number of characters.

### Yes/no box

The yes/no works like the message box, but has two buttons:

 ![Message box]({{ "/images/2017-12-23-Shell-scripting-adventures-part-3/yesno_box.png" }})

Commands:

```sh
$ message=$'Disable on board wireless (WiFi/Bluetooth, on RPi3)?
>
> On RPi 3, it\'s advised to choose `Yes`, since the traffic will go through eth0; choosing `No` will yield a working VPN Router nonetheless.
>
> On other models, the choice won\'t have any effect.'

$ if (whiptail --yesno "$message" 20 78); then
>   v_disable_on_board_wireless=1
> fi
```

Whiptail will return 1/255 if the user, respectively, hits No or Esc, and 0 in case of Yes.

The `if` condition branch, in this format, will be executed in case of Yes.

The message variable is quoted using [ANSI C Quoting](http://www.gnu.org/software/bash/manual/html_node/ANSI_002dC-Quoting.html), which is helpful when we don't want string interpolation, but at the same time we want to avoid the awkward bash single quote quoting (`'\''`).

### Gauge

The gauge is a very interesting widget used for displaying a progress:

 ![Gauge]({{ "/images/2017-12-23-Shell-scripting-adventures-part-3/gauge.png" }})

The widget reads from the stdin a numeric value from 0 to 100, which regulates the progress, and exits when the stream is closed.

While the principle is easy, it can be tricky to convert the output of a given program to the format required; this is a real-world example:

```sh
$ (dd status=progress if="$v_os_image_filename" of="$v_sdcard_device") 2>&1 | \
>   stdbuf -o0 awk -v RS='\r' "/copied/ { printf(\"%0.f\n\", \$1 / $os_image_size * 100) }" | \
>   whiptail --title "Image writing" --gauge "Burning the image on the SD card..." 20 78 0
```

The last parameter is `0`, which is used for specifying the progress via stdin (otherwise, the passed percentage is displayed).

The functioning of this example is explained in detail in a section of [the previous post]({% post_url 2017-11-22-Shell-scripting-adventures-part-2 %}#progress-bars-processing-with-awk-and-stdbuf).

### Radio list

The radio list provides a list of entries, for choosing one:

 ![Radio list]({{ "/images/2017-12-23-Shell-scripting-adventures-part-3/radio_list.png" }})

An interesting way of implementing this functionality is to use a Bash associative array:

```sh
$ declare -A v_usb_storage_devices

$ v_usb_storage_devices[/dev/sdb]="My USB Key"
$ v_usb_storage_devices[/dev/sdc]="My external HDD"

$ entries_option=""
$ entries_count=0
$ message=$'Choose an external device. THE DEVICE WILL BE COMPLETELY ERASED.\n\nAvailable (USB) devices:\n\n'

$ for dev in "${!v_usb_storage_devices[@]}"; do
>   entries_option+=" $dev "
>   entries_option+=$(printf "%q" ${v_usb_storage_devices[$dev]})
>   entries_option+=" OFF"
>
>   let entries_count+=1
> done

$ v_sdcard_device=$(whiptail --radiolist --title "Device choice" "$message" 20 78 $entries_count $entries_option 3>&1 1>&2 2>&3);
```

The general format of this widget parameters is:

```sh
whiptail --radiolist [--title mytitle] <body_message_header> <width> <height> <entries_count> <entry_1_key> <entry_1_description> <entry_1_state> [<other entry params>...]
```

Note how we add `3>&1 1>&2 2>&3` at the end; they swap stdout and stderr, since whiptail's output goes to stderr, while we want it to go to stdout, so that we can capture it in the variable (see a detailed [Stackoverflow explanation](https://unix.stackexchange.com/questions/42728/what-does-31-12-23-do-in-a-script)).

Setting up the list definition parameters (key, description, state) is a bit convoluted, that's where using an associative array comes to help:

- we cycle the array (`for dev in "${!v_usb_storage_devices[@]}"`)
- for each cycle:
  - we append to `$entries_option` the key (device path), the description, and the default state (`OFF` for all, in this case)
  - we increment the counter (`$entries_count`)

This way, we can neatly prepare `$entries_count` and `$entries_option`.

There are two subtleties:

1. we don't quote `$entries_option`, since each individual token (each key/description/state) is an individual whiptail parameter;
2. because of that, we need to escape each individual entry option (in particular, the descriptions), otherwise each word would be interpreted as an individual whiptail parameter; for this purpose, we use `$(printf "%q" variable_to_escape)`.

Both are explained in the [part 1 of the series]({% post_url 2017-11-08-Shell-scripting-adventures-part-1 %}).

The result is:

```sh
whiptail --radiolist --title Device choice Choose an external device. THE DEVICE WILL BE COMPLETELY ERASED.

Available (USB) devices:

 20 78 2 /dev/sdb My\ USB\ Key OFF /dev/sdc My\ external\ HDD OFF
```

In one of the next posts of the series, I will show how to use udev to find the external USB devices.

## Other widgets

This is a brief list of other widgets with their description; the examples can be found in the [Whiptail chapter of the Bash shell scripting Wikibook](https://en.wikibooks.org/wiki/Bash_Shell_Scripting/Whiptail).

### Input box

A way to get free-form input from the user is via an input box. This displays a dialog with two buttons labeled Ok and Cancel.

### Text box

A text box with contents of the given file inside. Add --scrolltext if the file is longer than the window.

### Password box

A way to get a hidden password from the user is via an password box. This displays a dialog with two buttons labeled Ok and Cancel.

### Menus

A menu should be used when you want the user to select one option from a list, such as for navigating a program.

### Check list

A check list allows a user to select one or more options from a list.
