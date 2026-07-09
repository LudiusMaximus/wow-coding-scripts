#!/bin/bash
set -uo pipefail

# Call this script with a directory path as first argument.
# It will traverse all subdirectories and pull every found git repo in parallel.

# Maximum number of parallel jobs
MAX_JOBS=8

# Temporary directory for synchronization
TEMP_DIR=$(mktemp -d)
MUTEX_DIR="$TEMP_DIR/mutex"
FAILED_FILE="$TEMP_DIR/failed"
: > "$FAILED_FILE"

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
  set -uo pipefail
  local repo_path=$1

  # Do the git operations (this runs in parallel)
  cd "$repo_path"

  local fetch_status=0
  local pull_status=0
  local fetch_output
  local pull_output
  fetch_output=$(git fetch --force --tags --prune --prune-tags 2>&1) || fetch_status=$?
  pull_output=$(git pull --all --no-rebase 2>&1) || pull_status=$?

  # Acquire lock before printing (serializes output and the shared failure list)
  acquire_lock

  echo ""
  echo "Updating: $repo_path"
  [ -n "$fetch_output" ] && echo "$fetch_output"
  [ -n "$pull_output" ] && echo "$pull_output"

  if [ "$fetch_status" -ne 0 ] || [ "$pull_status" -ne 0 ]; then
    printf '\033[01;31mFAILED: %s (fetch=%s pull=%s)\033[0m\n' "$repo_path" "$fetch_status" "$pull_status"
    echo "$repo_path" >> "$FAILED_FILE"
  else
    echo "Completed: $repo_path"
  fi

  release_lock
}

export -f updateRepo
export TEMP_DIR
export MUTEX_DIR
export FAILED_FILE
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
echo "Searching for git repositories in: ${1:-}"
repos=$(findRepos "${1:-}")

if [ -z "$repos" ]; then
  echo "No git repositories found!"
  exit 0
fi

repo_count=$(echo "$repos" | wc -l)
echo "Found $repo_count repositories. Updating with $MAX_JOBS parallel jobs..."

# Launch all jobs in parallel with limited concurrency
echo "$repos" | xargs -P "$MAX_JOBS" -I {} bash -c 'updateRepo "$@"' _ {}

echo ""

if [ -s "$FAILED_FILE" ]; then
  fail_count=$(wc -l < "$FAILED_FILE")
  echo "FAILED to update $fail_count of $repo_count repositories:"
  cat "$FAILED_FILE"
  echo ""
  exit 1
fi

echo "All repositories updated!"

