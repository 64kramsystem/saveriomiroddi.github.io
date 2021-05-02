#!/bin/bash

set -o pipefail
set -o errexit
set -o nounset
set -o errtrace
shopt -s inherit_errexit

v_book_name=
v_cover_file=

function decode_cmdline_options {
  if [[ $# -ne 2 ]]; then
    echo "\
Usage: $(basename "$0") <book_name_underscore> <cover_file>

Takes care of everything, including creating the PR and merging, so carefully review the commit content when presented."
    exit
  fi

  v_book_name=$1
  v_cover_file=$2
}

function check_preconditions {
  if ! git st | grep -q "nothing to commit, working tree clean"; then
    >&2 echo "The git index is dirty!"
    exit 1
  fi
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

function create_commit {
  git ca -m "Add to bookshelf: $v_book_name"
}

function create_pr_and_merge {
  geet pr create -an -l bookshelf
  geet pr merge
}

decode_cmdline_options "$@"
check_preconditions
create_branch
clear_existing_books
add_image
add_new_book_description
create_commit
create_pr_and_merge
