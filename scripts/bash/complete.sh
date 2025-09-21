#!/usr/bin/env bash

set -euo pipefail

green="\033[32m"; red="\033[31m"; yellow="\033[33m"; cyan="\033[36m"; reset="\033[0m"
info()   { echo -e "${cyan}$*${reset}"; }
success(){ echo -e "${green}$*${reset}"; }
warn()   { echo -e "${yellow}$*${reset}"; }
error()  { echo -e "${red}$*${reset}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FEATURE_NAME="${1:-}"

get_current_feature() {
  local current_branch
  if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
    current_branch=$(git rev-parse --abbrev-ref HEAD)
  else
    current_branch=$(get_current_branch)
  fi
  if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
    error "Already on master branch. Please run this from a feature branch."
    exit 1
  fi
  echo "$current_branch"
}

get_default_branch() {
  if git show-ref --verify --quiet refs/heads/main; then
    echo main
  else
    echo master
  fi
}

complete_feature() {
  local feature_name="$1"
  info "Completing feature: $feature_name"

  # enforce clean working tree
  if [[ -n "$(git status --porcelain)" ]]; then
    error "Working tree not clean. Please commit task-by-task (TXXX) before completion."
    exit 1
  fi

  local default_branch; default_branch=$(get_default_branch)
  info "Switching to default branch '$default_branch'..."
  git checkout "$default_branch"

  info "Merging $feature_name into $default_branch..."
  if ! git merge "$feature_name"; then
    error "Merge failed. Please resolve conflicts manually."
    exit 1
  fi

  success "Feature '$feature_name' merged successfully into '$default_branch'!"
  info "Feature branch '$feature_name' is preserved for your reference."
}

if [[ ! -d .git ]]; then
  error "Not in a git repository."
  exit 1
fi

if [[ -z "$FEATURE_NAME" ]]; then
  FEATURE_NAME="$(get_current_feature)"
fi

info "Starting completion process for feature: $FEATURE_NAME"
warn "Note: This assumes review has been completed successfully."
echo

read -r -p "Proceed with commit and merge to master? (y/N) " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  warn "Operation cancelled."
  exit 0
fi

complete_feature "$FEATURE_NAME"


