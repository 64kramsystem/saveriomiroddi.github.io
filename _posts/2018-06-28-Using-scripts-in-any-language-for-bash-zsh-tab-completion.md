---
layout: post
title: Using scripts in any language for Bash/Zsh tab completion
tags: [linux,shell_scripting]
last_modified_at: 2018-07-24 00:22:00
---

I've recently moved from Bash to Zsh, and I needed to port my tab completion scripts. Zsh has a sophisticated built-in tab completion, however, the documentation is not very beginner-friendly; moreover, Bash scripts can be used with no or little change in Zsh. Therefore, I've opted for using them directly.

This article will explain how to write tab-completion scripts in any language, with an example in Ruby, and how to use them in both Bash and Zsh.

As typical of this blog, the script is also used as an exercise in shell scripting, therefore, it contains additional (arguably) useful/interesting commands/concepts.

Contents:

- [Ruby Library](/Using-scripts-in-any-language-for-bash-zsh-tab-completion#ruby-library)
- [Writing a tab-completion script](/Using-scripts-in-any-language-for-bash-zsh-tab-completion#writing-a-tab-completion-bash-script)
- [Specification of the target program](/Using-scripts-in-any-language-for-bash-zsh-tab-completion#specification-of-the-target-program)
- [Writing the tab completion script](/Using-scripts-in-any-language-for-bash-zsh-tab-completion#writing-the-tab-completion-script)
- [Setting up autocompletion](/Using-scripts-in-any-language-for-bash-zsh-tab-completion#setting-up-autocompletion)
- [Debugging](/Using-scripts-in-any-language-for-bash-zsh-tab-completion#debugging)
- [Conclusion](/Using-scripts-in-any-language-for-bash-zsh-tab-completion#conclusion)

## Ruby Library

Due to the popularity of this article, following a suggestion from a reader, I'm writing a library for making tab completion scripts trivial. It will be published in August as addition to my [SimpleScripting project](https://github.com/saveriomiroddi/simple_scripting).

## Writing a tab-completion script

Bash and Zsh support tab-completion scripts in any language.

The workflow/structure of such scripts is actually trivial:

- the full command line string is received through an environment variable
- processing is performed
- the entries are sent to stdout, one line per entry

## Specification of the target program

The program the tab-completion applies to is called `open_project`.

Its programming language is irrelevant; what matters, from a tab-completion perspective, is:

- the program commandline interface;
- how to find out the tab completion entries.

This is the program help, to give an idea of the interface:

```
$ open_project --help
Usage: open_project [-s|--switch-only] project_name

Opens the project in `$PROJECTS_DIR/<project_name>` with the default editor; if a corresponding project configfile is found in `$PROJECTS_DIR/_configs/<project_name>.<cfg_ext>`, the file is opened instead with the associated editor.

If `--switch-only` is specified, the current directory is changed to the project's, but the editor is not launched.
```

The script is useful for people working on multiple projects, with multiple editors.

## Writing the tab completion script

Before writing the script, the specifications we need (to know) is:

- the commandline is passed by Bash as the env variable `$COMP_LINE`
- the projects directory is in the env variable `$PROJECTS_DIR`

The script source is below, followed by comments on the interesting code sections; we'll assume it's called `/path/to/open_project_tab_completion.rb`.

Note that in this section, I use the term `Zsh` referring to the combination of Zsh and bashcompinit.

```ruby
#!/usr/bin/env ruby

require 'shellwords'
require 'getoptlong'

class OpenProjectTabCompletion
  def find_matches(command_line, projects_dir)
    prepare_argv!(command_line)
    parse_and_consume_options!

    project_name_prefix = extract_project_name_prefix
    project_names = find_project_names(projects_dir)
    filtered_names = filter_names(project_names, project_name_prefix)

    puts filtered_names
  rescue GetoptLong::InvalidOption
    # getoptlong prints the error automatically
    exit(1)
  rescue => error
    STDERR.puts error.message
    exit(1)
  end

  private

  def prepare_argv!(command_line)
    # The first token is the command name; we don't need it.
    command_parameters = Shellwords.split(command_line)[1..-1]

    ARGV.clear
    ARGV.concat(command_parameters)
  end

  def parse_and_consume_options!
    options = GetoptLong.new(
      ["-s", "--switch-only", GetoptLong::NO_ARGUMENT]
    )

    # Consume the options.
    options.each {}
  end

  def extract_project_name_prefix
    if ARGV.size > 1
      raise ArgumentError.new("Expected at most one parameter (project identifier); #{ARGV.size} found")
    end

    ARGV[0] || ''
  end

  def find_project_names(projects_dir)
    Dir["#{projects_dir}/*"].select { |file| File.directory?(file) }.map { |file| File.basename(file) }
  end
end

if __FILE__ == $PROGRAM_NAME
  command_line = ENV.fetch('COMP_LINE')
  projects_dir = ENV.fetch('PROJECTS_DIR')

  OpenProjectTabCompletion.new.find_matches(command_line, projects_dir)
end
```

First, we prepare ARGV:

```ruby
  def prepare_argv!(command_line)
    # The first token is the command name; we don't need it.
    command_parameters = Shellwords.split(command_line)[1..-1]

    ARGV.clear
    ARGV.concat(command_parameters)
  end
```

We need to manually parse the command line, because Bash and Zsh differ: Bash populates ARGV, Zsh doesn't.

The `shellwords` library contains useful APIs for working with shell commands (more precisely, their string representation); `Shellwords.split` will make sure that a command like:

```
my command "option 1" 'option 2' option_3
```

is split into:

```
["option 1", "option 2", option_3]
```

which is what ARGV would be in a regular execution.

Then, we handle the options:

```ruby
  def parse_and_consume_options!
    options = GetoptLong.new(
      ["-s", "--switch-only", GetoptLong::NO_ARGUMENT]
    )

    # Consume the options.
    options.each {}
  end
```

Note that we're (likely) duplicating the option parsing: both the tab completion script and the program need to parse the options.  
However, the tab completion script has trivial logic: it doesn't act on options, instead, it only parses and consumes them; for this reason, this solution can be considered acceptable.

For parsing, here we use the `getoptlong` library. The Ruby standard library provides both `getoptlong` and `optparse`; in this context, they're both equivalent.

For more information on option parsing, refer to the [getoptlong](https://docs.ruby-lang.org/en/2.5.0/OptionParser.html) and/or [optparse](https://docs.ruby-lang.org/en/2.5.0/OptionParser.html) library API references.

Getoptlong will print a message, raise an error and stop consuming tokens if an invalid option is passed by the user.

Then, we check the number of non-option arguments passed:

```ruby
  def extract_project_name_prefix
    if ARGV.size > 1
      raise ArgumentError.new("Expected at most one parameter (project identifier); #{ARGV.size} found")
    end

    ARGV[0] || ''
  end
```

Here, Bash and Zsh differ again:

- Bash needs the filtered (end-resulting) list of entries;
- Zsh can take the whole list, and it will filter it for us, based on the characters on the commandline (argument).

For compatibility with both, we apply the filter in both cases.

Now we just find and filter the project names:

```ruby
  def find_project_names
    Dir["#{PROJECTS_DIRECTORY}/*"].select { |file| File.directory?(file) }.map { |file| File.basename(file) }
  end

  def filter_names(project_names, project_name_prefix)
    project_names.select { |name| name.start_with?(project_name_prefix) }
  end
```

In case of error, things get very confusing; the behavior differs between Bash and Zsh, and additionally, GetOptLong also prints a message to stderr even if the error is `rescue`d.

For this reason, in case of error we just return an empty list, and expect the user to abort the command:

```ruby
  def matches(command_line)
    prepare_argv!(command_line)
    parse_and_consume_options!

    project_name_prefix = extract_project_name_prefix
    project_names = find_project_names
    filtered_names = filter_names(project_names, project_name_prefix)

    puts filtered_names
  rescue GetoptLong::InvalidOption
    # getoptlong prints the error automatically
    exit(1)
  rescue => error
    STDERR.puts error.message
    exit(1)
  end
```

The `exit(1)` statements are not required; they're present only for cleanness' sake.

## Setting up autocompletion

In Zsh, we need to configure the Bash compatibility (add to `$HOME/.zshrc`):

```sh
autoload bashcompinit
bashcompinit
```

Then, for both shells, we invoke the `complete` command for associating the completion script with the script itself (append to `$HOME/.bash_profile` for Bash and `$HOME/.zshrc` for Zsh):

```sh
complete -C "/path/to/open_project_tab_completion.rb" -o default open_project
```

Don't forget to `chmod +x /path/to/open_project_tab_completion.rb`.

We're done! Example:

```sh
$ open_project -n g<tab>
geet       gitlab-ce  goby-dev
```

Note that Bash has multiple init scripts; `.bash_profile` may not be appropriate for some configurations.

## Debugging

In order to debug the script, just execute it passing a custom `COMP_LINE`:

```sh
$ COMP_LINE="open_project --switch-only g" /path/to/open_project_tab_completion.rb
```

## Conclusion

Although writing Zsh-specific tab completion is "the best" way, it's possible to write and set tab completion scripts in any language, in a trivial and portable way.

Happy scripting!
