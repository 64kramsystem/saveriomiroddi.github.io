---
layout: post
title: An overview of Desktop Ruby GUI development in 2018
tags: [gui,ruby]
last_modified_at: 2018-03-15 10:47:00
---

Ruby GUI development is a seldom mentioned subject, but it has value. Probably after some Rails development (cough...), developing a desktop tool may be an interesting diversion (or even a requirement).

During the development of my [PM-Spotlight](https://github.com/saveriomiroddi/pm-spotlight) desktop application, I evaluated most of the Desktop Ruby GUI toolkits, and prototyped the application with three of them (Shoes 3, FXRuby, and Tk).

This article presents a summary of what I've experienced (or gathered) while I was "Developing GUI applications with Ruby"!

Contents:

- [TL;DR: The summary](/An-overview-of-ruby-gui-development-in-2018#tldr-the-summary)
- [Extension/mistakes](/An-overview-of-ruby-gui-development-in-2018#extensionmistakes)
- [Frameworks](/An-overview-of-ruby-gui-development-in-2018#frameworks)
  - [Shoes 3/4](/An-overview-of-ruby-gui-development-in-2018#shoes-34)
  - [Fox toolkit](/An-overview-of-ruby-gui-development-in-2018#fox-toolkit)
  - [Tk](/An-overview-of-ruby-gui-development-in-2018#tk)
  - [WxWidgets](/An-overview-of-ruby-gui-development-in-2018#WxWidgets)
  - [Qt](/An-overview-of-ruby-gui-development-in-2018#qt)
  - [GTK+](/An-overview-of-ruby-gui-development-in-2018#gtk)
- [Conclusion](/An-overview-of-ruby-gui-development-in-2018#conclusion)
- [Some references](/An-overview-of-ruby-gui-development-in-2018#some-references)

## TL;DR: The summary

Reference table:

| Framework   | Distribution | Functionality | Documentation | Widgets     |
|-------------|--------------|---------------|---------------|-------------|
| Shoes 3     | good         | poor          | so-so         | lightweight |
| Shoes 4     | good         | poor          | poor          | native      |
| Fox Toolkit | good         | good          | good          | lightweight |
| Tk          | poor         | good          | good          | mixed       |
| WxWidgets   | (dead)       | -             | -             | native      |
| Qt          | obsolete     | good?         | ?             | mixed       |
| GTK+        | good?        | good?         | ?             | mixed       |
| JRubyFX     | ?            | ?             | ?             | ?           |

This is certainly a reductionist view, so it's crucial to read to full article to get a grasp.

### Notes about platforms/toolkits

- Essentially all the toolkits are evaluated on the MRI (except Shoes 4, based on JRuby); compatibility with other interpreters is not specified;
- I did not prototype my application with Qt/GTK+, so for those, I only evaluated what I could gather by reading the documentation;
- RubyMotion is not included, as it doesn't support the major desktop platforms;
- I didn't evaluate JRubyFX, since I wasn't aware of it at the time of publication of the post.

### Notes about evaluation

- The distribution refers to the main desktop platforms: Linux, MacOS and Windows;
- The widgets implementation is listed in this table, but not referenced in the evaluations, because in the current landscape, the other aspects are significantly more pressuring; also, native widgets are not necessarily better than lightweight;
- I didn't consider ease of development;
- I didn't consider the size of the packages, as in the cases where packages applications are small, the libraries still need to be downloaded.

## Extension/mistakes

Please contact me if you have any worthy extension and/or correction! I care about producing/spreading informed Ruby GUI development.

## Frameworks

### Shoes 3/4

Shoes was a neat library originally developed by why the lucky stiff. Its target was to allow users write cross platform application in Ruby style (traditionally, GUI development has always had a relatively low-level structure, so this was a big deal).

There have been two major turning points in the development:

- in 2010, Shoes 3 was released, following \_why's disappearance;
- in 2013, Shoes 4 was started, transitioning to a new underlying model; after some time, Shoes 3 was forked and got a separate maintainer.

Shoes 4 is based on JRuby/SWT, and it's at Release Candidate stage (but keep in mind that the development of Shoes has been traditionally very slow).

Shoes 3 is a mixed C/Ruby binding.

#### Distribution

From the distribution perspective, both v3 and v4 are very similar: they can produce self-contained packages (v3 will produce a native binary; v4 a JAR).

This is excellent for distribution:

- Shoes 3: one native binary per platform, no libraries needed;
- Shoes 4: a universal package; Java JRE is needed.

#### Functionality

Design-wise, a Shoes program needs to be wrapped in the `Shoes.app` block, with the GUI elements being used in DSL form:

```ruby
Shoes.app do
  button "Click me" { close }
end
```

This orients the design to be GUI-centered, in a way, similarly to Visual Basic 6 - this has advantages, but also potentially terrifying disadvantages.

Although one can potentially produce a good design, it's not possible to fully decouple a program from the Shoes framework; this general structure is not possible:

```ruby
class ShoesGuiFrontend
  def display
    Shoes.app do
      button "Click me" { close }
    end
  end
end

class MyProgram
  def initialize
    @frontend = initialize_gui_frontend
  end

  def display_gui
    @frontend.display
  end
end
```

In terms of general API richness, Shoes is a very limited toolkit. For example, events are attached to layout containers, not to widgets [¹](#footnote01); there are basic widgets, but not all the typical ones present in mature toolkits (eg. tree list).

I experienced a crash (on the current release version, 3.3.5) after testing a handful of the demo examples, which is not a very good sign.

Shoes applications start slowly.

For the above reasons, I give a `poor` evaluation, although Shoes could still be an appropriate choice for trivial applications.

#### Documentation

The documentation of both v3 and v4 has a format appealing to beginners - flashy and friendly.  
Concepts are explained in a generally very limited (introductory) fashion; some miss examples in their chapters. There are examples for many widgets, though.  
In general, the documentation is not suited to (more) advanced development.

Shoes 4's documentation is outdated, which leads to a `poor` evaluation.

Shoes 3's documentation is unusually distributed; it's up to date, but it's readable only from the library main program (!). Gets a `so-so` evaluation for the basic, shared (with v4), content.

### Fox toolkit

Fox is the underdog of the GUI libraries - rarely mentioned, but active and very functional.

The Ruby binding library is called `FXRuby`.

#### Distribution

In order to run a Fox Ruby application, the user needs to install the Fox Toolkit library and the `fxruby` gem. This is a reasonably easy process, thus, the `good` evaluation.

#### Functionality

The Fox toolkit is a mature and flexible library - there are professional applications making use of it.

FXRuby applications start quickly.

For the reasons above, Fox toolkit gets a `good` evaluation.

#### Documentation

The Fox toolkit documentation has a `good` evaluation, since there is a [good book written](https://pragprog.com/book/fxruby/fxruby).

The book is old, but valid. The downside is that the documentation for widgets outside of the ones presented in the book is cryptic, as the Fox toolkit provides a very plain, low-level API documentation.

FXRuby examples are very thorough; there is even one dedicated to threading, which is a very delicate and generally overlooked problem (for example, Shoes and Tk don't mention it at all).

### Tk

Tk is a mature, flexible and widespread library; in fact, it's Python's standard.

#### Distribution

Although Tk is the official Ruby GUI library, the Ruby interpreter needs to be compiled with specific options in order to support it; generally, distributed Ruby versions don't support it out of the box.

This can be simplified in some cases (e.g. on Ubuntu, Brightbox provides precompiled Ruby versions up to 2.3), but it's not something to expect from a casual end-user.

This yields a `poor` evaluation.

#### Functionality

Tk is a mature and flexible library.

The only exception is threading, which is obscure and poorly documented, so it's somewhat discouraged for applications making use of it.

Tk applications start slowly.

All in all though, functionality itself is `good`.

#### Documentation

Tk is vastly documented (with the mentioned exception of threading), and it has a very good (multi-language) tutorial, therefore, it gets a `good` evaluation.

### WxWidgets

The Ruby binding project is dead! It's a shame, because the library is mature, flexible, and widespread.

### Qt

Qt is a mature and flexible library. It's not only a GUI toolkit, but an entire application framework. It's extremely widespread.

Qt bindings development for Ruby has roots in [QtRuby](https://en.wikipedia.org/wiki/QtRuby); after the project died, [qtbindings](https://github.com/ryanmelt/qtbindings) followed.

qtbindings supports Qt only up to an old version (4.8.6, released in 2011), therefore, my `obsolete` evaluation.

I haven't developed with Qt; due to the Qt backing, I gave a purely guessed `good?` functionality evaluation.

### GTK+

GTK+ is a mature and flexibly library. It's extremely widespread.

Packaging GTK+ application seems to be very easy, therefore my `good?` evaluation.

I haven't developed with GTK+; due to the GTK+ backing, I gave a purely guessed `good?` functionality evaluation.

## Conclusion

It's very difficult to give general guidelines, but I'll still give a shot.

For distributing applications, my guidelines are:

- for general purpose, FXRuby (also try GTK+);
- for *extremely* simple applications, try Shoes 3.

The other libraries/bindings has very shortcomings that in my opinion/use cases are far too inconvenient.

## Some references

This section is currently under works; if/once more links will be gathered, I will structure merge them in the toolkit sections.

- GTK
  - [A very good introduction on building a Ruby GTK GUI (Jan/2018)](https://iridakos.com/tutorials/2018/01/25/creating-a-gtk-todo-application-with-ruby.html)

<a name="footnote01">¹</a>: I'm not sure if this can be worked around or not, for example by wrapping each evented widget in one container.
