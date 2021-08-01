---
layout: post
title: Speeding up Ruby gems compilation (installation)
tags: [linux,quick,ruby]
---

I'm very annoyed by how slow installing Ruby gems is, even with a large number of available hardware threads (and even with many Bundler jobs configured).

I had a quick look a the Rubygems/Bundler source code today, and I've found a quick win.

Content:

- [Context](/Speeding-up-Ruby-gems-compilation#context)
- [The tweak](/Speeding-up-Ruby-gems-compilation#the-tweak)
- [Conclusion](/Speeding-up-Ruby-gems-compilation#conclusion)

## Context

Ruby gems can have native extensions, which require compilation.

When installing via Bundler, it's very common to install with the `--jobs` option, which launches each gem installation in a separate job (with the disclaimer that Ruby concurrency is limited).

Such option does not apply though, to the native extensions compilation; gems with relatively large C code may take a relatively considerable time to compile.

I've inspected the source code, and tried to find out where `make` (which is used to compile) was invoked, and found it [here](https://github.com/rubygems/rubygems/blob/master/lib/rubygems/ext/builder.rb#L27):

```rb
# simplified version

make_program = ENV['MAKE'] || ENV['make'] || $1
make_program = Shellwords.split(make_program)

destdir = 'DESTDIR=%s' % ENV['DESTDIR']

['clean', '', 'install'].each do |target|
  cmd = [
    *make_program,
    destdir,
    target,
  ].reject(&:empty?)

  run(cmd, results, "make #{target}".rstrip, make_dir)
end
```

Here we observe that `make` is invoked without the jobs argument (`-j`), therefore, it's run by default in single-thread.

## The tweak

Since the `make` executable is configurable (also) via `MAKE` environment variable, we just use it:

```sh
# Run with all the available threads!
#
MAKE="make -j $(nproc)" bundle install
```

On our application, this sped up the `bundle install` operation from 2'41" to 59"!

(This works on Linux/macOS; Windows user may need to adjust the variable)

## Conclusion

Due to history, parallelism is not pervasive in the Ruby culture. Let's fix that! 🙂

Happy gem installation!
