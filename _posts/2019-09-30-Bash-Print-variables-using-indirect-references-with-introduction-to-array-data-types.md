---
layout: post
title: Bash&#58; Print variables using indirect references, with introduction to array data types
tags: [linux,shell_scripting]
last_modified_at: 2019-10-01 20:08:00
---

Although there is a complexity threshold for the convenience of shell scripting, there is still plenty that (in my opinion) can be done before hitting such ceiling.

In this brief article, I'll explain how to use indirect references to write a function that prints the names and content of the variables passed; this is useful when writing debugging code for a script.

Contents:

- [Specification](/Bash-Print-variables-using-indirect-references-with-introduction-to-array-data-types#specification)
- [Quick introduction to Bash array data types](/Bash-Print-variables-using-indirect-references-with-introduction-to-array-data-types#quick-introduction-to-bash-array-data-types)
  - [Arrays](/Bash-Print-variables-using-indirect-references-with-introduction-to-array-data-types#arrays)
  - [Associative arrays](/Bash-Print-variables-using-indirect-references-with-introduction-to-array-data-types#associative-arrays)
- [Other notions](/Bash-Print-variables-using-indirect-references-with-introduction-to-array-data-types#other-notions)
- [Indirect references, and writing the function](/Bash-Print-variables-using-indirect-references-with-introduction-to-array-data-types#indirect-references-and-writing-the-function)
- [Debugging goodies](/Bash-Print-variables-using-indirect-references-with-introduction-to-array-data-types#debugging-goodies)
- [Conclusion](/Bash-Print-variables-using-indirect-references-with-introduction-to-array-data-types#conclusion)

## Specification

We want a function that given the following variables (details explained later):

```sh
foo=123
bar=(abc "cde fgh" ijk)
declare -A baz=([abc]=cde [fgh ijk]="lmn opq")
```

is called in the following form:

```sh
print_variables foo bar baz
```

and prints:

```
foo: 123
bar: "abc" "cde fgh" "ijk"
baz: "fgh ijk"="lmn opq" "abc"="cde"
```

## Quick introduction to Bash array data types

First, a disclaimer: [Bash variables are untyped](https://www.tldp.org/LDP/abs/html/untyped.html), however, there is still some type of [weak typing](https://www.tldp.org/LDP/abs/html/declareref.html), meant as associating certain properties to a given variable. Therefore, in the context of this article, "data type" is an improper term used for simplicity.

Bash supports two array data types: arrays and associative arrays.

### Arrays

Arrays can be declared in the following forms:

```sh
# Empty array
myarray=()

# Inline initialization
myarray=(myentry1 "my entry 2" myentry3)

# Formal initialization
declare -a myarray
```

And the various operations (the results assume that all the commands are run in sequence):

```sh
myarray=(myentry1 "my entry 2" myentry3)

# Append an item
myarray+=(myentry4)

# Access
echo ${myarray[1]}       # "my entry 2"
echo ${myarray[-1]}      # "myentry4"

# Slicing (0-based): from <i> to end
echo "${myarray[@]:2}"   # "myentry3 myentry4"

# Delete an entry
unset 'myarray[3]'

# Size
echo ${#myarray[@]}      # 3

# Print the whole array
echo "${myarray[@]}"     # "myentry1 my entry 2 myentry3"

# Iterate
for entry in "${myarray[@]}"; do echo "$entry"; done
# "myentry1"
# "my entry 2"
# "myentry3"
```

Bash doesn't offer any functionality to test the inclusion of items in standard arrays. Where this functionality is required, the simplest solution is to use an associative array (see next section) with phony values.

### Associative arrays

Arrays can be declared in the following forms:

```sh
# Empty associative array
declare -A myarray

# Inline initialization
declare -A myarray=([mykey1]=myvalue1 [my key 2]="my value 2")
```

And the various operations (the results assume that all the commands are run in sequence):

```sh
declare -A myarray=([mykey1]=myvalue1 [my key 2]="my value 2")

# Set an item
myarray[mykey3]="my value 3"

# Access
echo ${myarray[my key 2]}  # "my value 2"

# Key test
[[ -v myarray["my key 2"] ]] && echo "found!" # "found!"

# Delete an entry
unset 'myarray[mykey3]'

# Size
echo ${#myarray[@]}        # 2

# Print the keys/values
echo ${!myarray[@]}        # "mykey1 my key 2"
echo ${myarray[@]}         # "myvalue1 my value 2"

# Iterate
for key in "${!myarray[@]}"; do
  echo "$key: ${myarray[$key]}"
done
# mykey1: myvalue1
# my key 2: my value 2
```

## Other notions

In order to write the function, we need a few other notions:

- Function arguments variable: when a function is called, the arguments are passed as `$@`;
- Declaring an indirect reference (cool!): we can use `declare -n variable_reference=variable_name`;
- Printing the declaration of a variable: `declare -p variable_name`; we exploit this to gather the data type of variables.

## Indirect references, and writing the function

Now that we know all the notions to write the function, I can write it entirely:

```sh
function print_variables {
  for variable_name in "$@"; do
    declare -n variable_reference="$variable_name"

    echo -n "$variable_name:"

    case "$(declare -p "$variable_name")" in
    "declare -a"* )
      for entry in "${variable_reference[@]}"; do
        echo -n " \"$entry\""
      done
      ;;
    "declare -A"* )
      for key in "${!variable_reference[@]}"; do
        echo -n " $key=\"${variable_reference[$key]}\""
      done
      ;;
    * )
      echo -n " $variable_reference"
      ;;
    esac

    echo
  done
}
```

The logic is straightforward.

Something worth knowing is that when using `declare` to declare variables, they're local by default, so we don't need to unset them.

## Debugging goodies

If the above function is used to debug (which is supposed to), don't forget that Bash has a debug mode, that can be enabled via:

```sh
exec 5> "$(dirname "$(mktemp)")/$(basename "$0").log"
BASH_XTRACEFD="5"
set -x
```

Note how we get the system temporary directory via `dirname "$(mktemp)"`.

## Conclusion

I use arrays and associative arrays often, when writing shell scripts. Although Bash is without any doubt "not very pretty", and "not very fun to debug", it is still a functional glue to write system logic of low to moderate complexity; all in all, although I can't say that writing Bash scripts is very fun, I definitely find it very satisfying.

Happy scripting 😄
