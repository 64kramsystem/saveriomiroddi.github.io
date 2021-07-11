#!/bin/bash

set -o pipefail
set -o errexit
set -o nounset
set -o errtrace
shopt -s inherit_errexit

v_book_name=
v_cover_file=

function decode_cmdline_options {
  if [[ $# -ne 1 || $1 == -h || $1 == --help ]]; then
    echo "\
Usage: $(basename "$0") <cover_file>

The cover filename (without extension) must be the underscore version of the book name.

Takes care of everything, including creating the PR and merging, so carefully review the commit content when presented."
    exit
  fi

  v_cover_file=$1
}

function check_preconditions {
  if ! git st | grep -q "nothing to commit, working tree clean"; then
    >&2 echo "The git index is dirty!"
    exit 1
  fi
}

function set_book_name {
  v_book_name=$(basename "${v_cover_file%.*}")
}

function create_branch {
  git co -b "add_$v_book_name" master
}

function clear_existing_books {
  perl -i -pe 's/^new: \Ktrue/false/' _bookshelf/*.md
}

function add_image {
  cp "$v_cover_file" images/bookshelf/
}

function add_new_book_description {
  cat > "_bookshelf/$v_book_name.md" << MD
---
description: <DESCRIPTION>
new: true
cover: /images/bookshelf/$(basename "$v_cover_file")
completed: $(date +%F)
---
MD
  vim "_bookshelf/$v_book_name.md"
}

function start_server_and_open_blog {
  bundle exec jekyll serve &
  while ! nc -z localhost 4000; do sleep 0.25; done
  xdg-open http://localhost:4000/bookshelf
  echo "Press any key to commit and follow up..."
  read -rsn1
  pkill -f 'jekyll serve'
}

function create_commit {
  local book_name_humanized=${v_book_name//_/ }
  book_name_humanized=${book_name_humanized^}
  git ca -m "Add to bookshelf: $book_name_humanized"
}

function create_pr_and_merge {
  geet pr create -an -l bookshelf
  geet pr merge
}

decode_cmdline_options "$@"
check_preconditions
set_book_name
clear_existing_books
add_image
add_new_book_description
start_server_and_open_blog
create_branch
create_commit
create_pr_and_merge
