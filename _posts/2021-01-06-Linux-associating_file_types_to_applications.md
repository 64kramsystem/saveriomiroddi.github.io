---
layout: post
title: Linux&#58; Associating file types to applications
tags: [linux,sysadmin,ubuntu]
---

Associating file types (extensions, in Windows) to applications is a fundamental functionality of desktop environments.

Some people may still have a troubled experiences while doing so; some others may want to script the operating system configuration. For both, I'm writing a small article about how to make such association via commandline, using standard Unix programs.

Content:

- [Introduction](/Linux-associating_file_types_to_applications#introduction)
- [Procedure](/Linux-associating_file_types_to_applications#procedure)
  - [Finding the desktop file](/Linux-associating_file_types_to_applications#finding-the-desktop-file)
  - [Finding the MIME type](/Linux-associating_file_types_to_applications#finding-the-mime-type)
  - [Registering the association](/Linux-associating_file_types_to_applications#registering-the-association)
- [Association by extension](/Linux-associating_file_types_to_applications#association-by-extension)
- [Conclusion](/Linux-associating_file_types_to_applications#conclusion)

## Introduction

Desktop environments of any operating systems provide a graphical mean of associating file types to applications ("Open with..." or similar); this includes Linux.

There is an underlying difference between Windows and Linux, though. Windows performs associations via file extension, while Linux typically does it in a more sophisticated way, via the so-called [MIME type](https://en.wikipedia.org/wiki/Media_type) (also known as "Media type").

In Linux desktop environments, (some) standards are specified by the [freedesktop.org](https://en.wikipedia.org/wiki/Freedesktop.org) association. This includes the related tools, which are therefore common across all the distributions.

## Procedure

As an example, let's suppose we want to associate Markdown files to Visual Studio Code.

### Finding the desktop file

When an application is installed in Linux, typically, a [desktop file](https://wiki.archlinux.org/index.php/desktop_entries) is installed, which contains informations necessary to integrate it into the desktop environment; the files are typically created under `/usr/share/applications`.

As a first step, we need to identify the desktop file; there are a few ways to accomplish this, some of whom may succeed with some installed applications, and some with other ones.

A simple search by filename will work most of the times:

```sh
# Case-insensitive search (`iname`).
#
$ find /usr/share/applications -iname '*code*'
/usr/share/applications/code-url-handler.desktop
/usr/share/applications/code.desktop
```

Alternatively, we can search the program or the executable names (in the latter case, watch out for symlinks!):

```sh
$ grep -Ri 'visual studio code' /usr/share/applications
/usr/share/applications/code-url-handler.desktop:Name=Visual Studio Code - URL Handler
/usr/share/applications/code.desktop:Name=Visual Studio Code

$ grep -R "/code" /usr/share/applications
/usr/share/applications/code-url-handler.desktop:Exec=/usr/share/code/code --no-sandbox --open-url %U
/usr/share/applications/code.desktop:Exec=/usr/share/code/code --no-sandbox --unity-launch %F
/usr/share/applications/code.desktop:Exec=/usr/share/code/code --no-sandbox --new-window %F
/usr/share/applications/bamf-2.index:code-url-handler.desktop	/usr/share/code/code --no-sandbox --open-url %U			true
/usr/share/applications/bamf-2.index:code.desktop	/usr/share/code/code --no-sandbox --unity-launch %F	Code		false
```

Insane engineers may inspect the package contents instead (for the lulz, of course!):

```sh
# Download the VSC package.
#
$ apt download code

# Extract the `data.tar.*` archive, which contains the files copied directly during the installation
# of the package.
#
$ ar xv code_*.deb data.tar.xz

# Now look for the desktop file!
#
$ tar tvf data.tar.xz | grep "/usr/share/applications"
-rw-r--r-- root/root       340 2020-12-16 17:28 ./usr/share/applications/code-url-handler.desktop
-rwxr-xr-x root/root       533 2020-12-16 17:28 ./usr/share/applications/code.desktop
```

In all the cases, the target file is very easily recognized as `code.desktop`.

### Finding the MIME type

Now that we know the desktop file, we'll need to find the MIME type. This can be done trivially by using the `mimetype` program; as an example, we'll download a markdown file:

```sh
$ wget -q https://raw.githubusercontent.com/saveriomiroddi/zfs-installer/master/README.md
$ mimetype README.md
README.md: text/markdown
```

The MIME type is therefore `text/markdown`.

As long as the extension is correct, there's no problem, but for the curious, keep in mind that it's easy to trick `mimetype` by using false extensions. Let's download a GIF file, storing it with an incorrect extension:

```sh
$ wget -q https://github.com/saveriomiroddi/zfs-installer/raw/master/demo/demo.gif -O demo.fakeext.txt
$ mimetype demo.fakeext.txt
demo.fakeext.txt: text/plain
```

What's interesting here, is that `mimetype` actually has several heuristics; it just picked the first:

```sh
$ mimetype -a demo.fakeext.txt
demo.fakeext.txt: text/plain
demo.fakeext.txt: image/gif
demo.fakeext.txt: application/octet-stream
```

In cases like this, we look only at the file content and ignore the extension ("magic"!):

```sh
$ mimetype --magic-only demo.fakeext.txt
demo.fakeext.txt: image/gif
```

Bingo!

Finally, there's also the standard tool `file`, which inspects the content by default:

```sh
$ file --mime demo.fakeext.txt
demo.fakeext.txt: image/gif; charset=binary
```

Generally speaking, if the file is correctly named, a basic `mimetype` invocation will suffice.

### Registering the association

Knowing both the desktop file and the MIME type, we can now... connect the dots 😬:

```sh
$ xdg-mime default code.desktop text/markdown
```

That's all! Now, when opening the file (either via GUI, or `xdg-open`), Visual Studio Code will execute.

Let's double check it!:

```sh
$ xdg-mime query default text/markdown
code.desktop
```

Correct!

## Association by extension

In some cases, the desktop environment may be fooled by the MIME type. No fear!

An example of this, are files in the [MAFF format](https://en.wikipedia.org/wiki/Mozilla_Archive_Format), the former Firefox pages archive format, which are technically ZIP files. When opening them, the desktop environment detects that they're archives, and opens the default archive manager.

In this case, we can enforce a certain mime type by matching the extension:

```sh
$ glob_pattern='*.maff'
$ mime_type="application/x-maff"
$ file_comment="Maff File"

$ sudo tee /tmp/maff.xml << XML
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type type="$mime_type">
<comment>$file_comment</comment>
<glob pattern="$glob_pattern"/>
</mime-type>
</mime-info>
XML

$ update-mime-database /usr/share/mime
```

The desktop environment will now recognize anything matching the glob `*.maff` as `application/x-maff`.

## Conclusion

One of my many favourite aspects of Linux, is that there is a program for any operation one may want to perform.

In this article, we've used a few tools used to configure file associations; this can be used to compensate unfortunate deficiencies of desktop environments, but also, for programmatically configuring systems (like I do!).

Happy system hacking!
