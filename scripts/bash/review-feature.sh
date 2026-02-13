#!/usr/bin/env bash

set -euo pipefail

# Colors
green="\033[32m"; red="\033[31m"; yellow="\033[33m"; cyan="\033[36m"; reset="\033[0m"
info()   { echo -e "${cyan}$*${reset}"; }
success(){ echo -e "${green}$*${reset}"; }
warn()   { echo -e "${yellow}$*${reset}"; }
error()  { echo -e "${red}$*${reset}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Args (optional feature name)
FEATURE_NAME="${1:-}"

# Python interpreter
if [[ -n "${PYTHON_INTERPRETER:-}" ]]; then
  PYTHON_BIN="$PYTHON_INTERPRETER"
else
  PYTHON_BIN="$(command -v python3 || command -v python || true)"
fi
if [[ -z "${PYTHON_BIN}" ]]; then
  error "Python interpreter not found (set PYTHON_INTERPRETER or install python3)."
  exit 1
fi

# Helpers
get_current_feature() {
  local current_branch
  if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
    current_branch=$(git rev-parse --abbrev-ref HEAD)
  else
    current_branch=$(get_current_branch)
  fi
  if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
    error "Already on default branch. Please run this from a feature branch."
    exit 1
  fi
  echo "$current_branch"
}

check_feature_tasks_completed() {
  local feature_name="$1"
  info "Checking if all feature tasks are completed..."
  local feature_dir="specs/${feature_name}"
  if [[ ! -d "$feature_dir" ]]; then
    warn "Feature directory not found: $feature_dir"
    return 0
  fi
  # find unchecked checkboxes
  local matches
  if matches=$(grep -RIn "^\s*\[ \].+" "$feature_dir" --include "*.md" || true); then
    if [[ -n "$matches" ]]; then
      error "Incomplete tasks found:"
      echo "$matches" | sed 's/^/  - /'
      error "Please complete all tasks before running the review command."
      return 1
    fi
  fi
  success "All feature tasks are completed!"
}

check_constitution_compliance() {
  info "Checking constitution compliance..."
  local constitution_file=".specify/memory/constitution.md"
  if [[ ! -f "$constitution_file" ]]; then
    warn "Constitution file not found: $constitution_file"
    return 0
  fi

  # changed files: prefer staged, else working tree
  local files
  if files=$(git diff --cached --name-only); [[ -z "$files" ]]; then
    files=$(git diff --name-only)
  fi
  if [[ -z "$files" ]]; then
    info "No changes to check against constitution."
    return 0
  fi

  local violations=()
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    ext="${file##*.}"
    case "$ext" in
      py)
        if "$PYTHON_BIN" - <<'PY' 2>/dev/null 1>/dev/null; then :; fi
PY
        if command -v flake8 >/dev/null 2>&1; then
          if ! out=$(flake8 "$file" 2>&1); then
            violations+=("Python style violation in $file: ${out}")
          elif [[ -n "$out" ]]; then
            violations+=("Python style violation in $file: ${out}")
          fi
        else
          warn "flake8 not available; skipping style check for $file"
        fi
        ;;
      md)
        # skip template docs
        if [[ "$file" != *"/templates/"* && "$file" != templates/* ]]; then
          if ! grep -qE '^# .+' "$file"; then
            violations+=("Missing header in documentation: $file")
          fi
        fi
        ;;
      js|html)
        :
        ;;
    esac
    # basic security scans
    if [[ "$ext" == "py" || "$ext" == "js" || "$ext" == "html" ]]; then
      content="$(cat "$file")"
      if echo "$content" | grep -qE 'password.*=.*["\'"'\"][[:alnum:]_]+["\'"'\"]'; then
        violations+=("Hardcoded password detected in $file")
      fi
      if [[ "$ext" == "py" ]] && echo "$content" | grep -qE '\\bexec\\s*\\('; then
        violations+=("Use of exec() in $file")
      fi
      if [[ "$ext" == "js" ]] && echo "$content" | grep -qE '\\beval\\s*\\('; then
        violations+=("Use of eval() in $file")
      fi
    fi
  done < <(printf '%s\n' "$files")

  if (( ${#violations[@]} > 0 )); then
    error "Constitution violations found:"
    for v in "${violations[@]}"; do echo "  - $v"; done
    return 1
  fi
  success "All changes comply with the constitution!"
}

run_all_tests() {
  info "Running all tests..."
  set +e
  out="$($PYTHON_BIN -m pytest tests/ -v --tb=short 2>&1)"
  code=$?
  set -e
  if (( code != 0 )); then
    error "Tests failed or had errors."
    echo "$out" | grep -E "[0-9]+\s+failed" || true
    return 1
  fi
  success "All tests passed!"
}

test_web_functionality() {
  info "Testing web functionality..."
  # heuristic: presence of common web app files/dirs
  if [[ ! -d templates && ! -d static && ! -f app.py && ! -d src/infrastructure/web ]]; then
    info "Not a web application, skipping web functionality tests."
    return 0
  fi
  # ensure Flask available
  if ! "$PYTHON_BIN" -c "import flask" >/dev/null 2>&1; then
    error "Flask is not available in the configured interpreter."
    return 1
  fi
  export FLASK_ENV=development
  # start server
  set +e
  "$PYTHON_BIN" -m flask run --port=5001 >/tmp/specify_flask.log 2>&1 &
  srv_pid=$!
  set -e
  sleep 3
  # health check
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS http://localhost:5001 >/dev/null; then
      success "Web application is responding correctly!"
      kill "$srv_pid" >/dev/null 2>&1 || true
      return 0
    else
      error "Web application is not responding (curl failed)."
      kill "$srv_pid" >/dev/null 2>&1 || true
      return 1
    fi
  else
    warn "curl not available; skipping HTTP check."
    kill "$srv_pid" >/dev/null 2>&1 || true
    return 0
  fi
}

# Main
if [[ ! -d .git ]]; then
  error "Not in a git repository."
  exit 1
fi

if [[ -z "$FEATURE_NAME" ]]; then
  FEATURE_NAME="$(get_current_feature)"
fi

info "Starting review process for feature: $FEATURE_NAME"
echo

all_ok=true

if ! check_feature_tasks_completed "$FEATURE_NAME"; then all_ok=false; fi
echo
if ! check_constitution_compliance; then all_ok=false; fi
echo
if ! run_all_tests; then all_ok=false; fi
echo
if ! test_web_functionality; then all_ok=false; fi
echo

if [[ "$all_ok" == true ]]; then
  success "✅ All review checks passed!"
  success "Feature '$FEATURE_NAME' is ready for completion."
  info "You can now run the complete command to merge this feature."
else
  error "❌ Review failed!"
  error "Please fix all issues before proceeding with completion."
  exit 1
fi


