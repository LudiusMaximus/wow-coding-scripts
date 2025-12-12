#!/bin/bash

# Call this script with a directory path as first argument.
# It will traverse all subdirectories and pull every found git repo in parallel.

# Maximum number of parallel jobs
MAX_JOBS=8

# Temporary directory for synchronization
TEMP_DIR=$(mktemp -d)
MUTEX_DIR="$TEMP_DIR/mutex"

# Cleanup function
cleanup() {
  rm -rf "$TEMP_DIR"
}

# Ensure cleanup on exit, interrupt, or termination
trap cleanup EXIT INT TERM

# Acquire mutex (blocks until available)
acquire_lock() {
  while ! mkdir "$MUTEX_DIR" 2>/dev/null; do
    sleep 0.1
  done
}

# Release mutex
release_lock() {
  rmdir "$MUTEX_DIR" 2>/dev/null
}

# Function to update a single repo
updateRepo() {
  local repo_path=$1
  
  # Do the git operations (this runs in parallel)
  cd "$repo_path"
  local fetch_output=$(git fetch --tags --prune --prune-tags 2>&1)
  local pull_output=$(git pull --all --ff-only 2>&1)
  
  # Acquire lock before printing (serializes output only)
  acquire_lock
  
  echo ""
  echo "Updating: $repo_path"
  [ -n "$fetch_output" ] && echo "$fetch_output"
  [ -n "$pull_output" ] && echo "$pull_output"
  echo "Completed: $repo_path"
  
  release_lock
}

export -f updateRepo
export TEMP_DIR
export MUTEX_DIR
export -f acquire_lock
export -f release_lock

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

# Launch all jobs in parallel with limited concurrency
echo "$repos" | xargs -P "$MAX_JOBS" -I {} bash -c 'updateRepo "$@"' _ {}

echo ""
echo "All repositories updated!"

