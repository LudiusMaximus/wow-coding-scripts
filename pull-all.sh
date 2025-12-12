#!/bin/bash

# Call this script with a directory path as first argument.
# It will traverse all subdirectories and pull every found git repo in parallel.

# Maximum number of parallel jobs
MAX_JOBS=8

# Function to update a single repo
updateRepo() {
  local repo_path=$1
  echo "Updating: $repo_path"
  cd "$repo_path"
  git fetch --tags --prune --prune-tags 2>&1 | sed "s|^|[$repo_path] |"
  git pull --all --ff-only 2>&1 | sed "s|^|[$repo_path] |"
  echo "Completed: $repo_path"
}

export -f updateRepo

# Find all git repositories
findRepos() {
  local path=$1
  
  if [ ! -d "$path" ]; then
    echo "$path not found!!"
    exit 1
  fi
  
  # Find all directories containing .git (both directories and files for submodules)
  find "$path" -name ".git" -type d -o -name ".git" -type f | while read -r gitpath; do
    # Get the parent directory (the actual repo directory)
    dirname "$gitpath"
  done
}

# Main execution
echo "Searching for git repositories in: $1"
repos=$(findRepos "$1")

if [ -z "$repos" ]; then
  echo "No git repositories found!"
  exit 0
fi

repo_count=$(echo "$repos" | wc -l)
echo "Found $repo_count repositories. Updating with $MAX_JOBS parallel jobs..."
echo ""

# Run updates in parallel
echo "$repos" | xargs -P "$MAX_JOBS" -I {} bash -c 'updateRepo "$@"' _ {}

echo ""
echo "All repositories updated!"

