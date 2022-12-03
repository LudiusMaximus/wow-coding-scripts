#!/bin/bash

# Call this script with a directory path as first argument.
# It will traverse all subdirectories and pull every found git repo.

checkDir() {
  local path=$1  

  if [ -d "$path" ]; then
    cd "$path"
    for dir in */; do

      if [ -d "$path$dir" ]; then
        cd "$path$dir"
        if [ -d ".git" ] || [ -f ".git" ]; then
          echo "$(pwd)"
          git fetch --tags --prune --prune-tags
          git pull --all --ff-only
        fi
        
        checkDir "$(pwd)/"
      fi
    done
  else
    echo "$path not found!!"
  fi
}

# checkDir "$(cygpath -u "$1")/"
checkDir "$1/"

