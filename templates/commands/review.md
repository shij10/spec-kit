---
description: Review a feature by performing comprehensive checks before completion
scripts:
  sh: scripts/bash/review.sh
  ps: scripts/powershell/review.ps1
---

Given the context provided as an argument, do this:

1. Run the script `{SCRIPT}` from repo root to perform comprehensive checks.

2. The script will automatically:
   - Check if all feature tasks are completed (scans specs/ directory for task files)
   - Verify changes comply with the constitution (code style, documentation, basic security checks)
   - Run all tests to ensure no regressions (pytest via the configured Python interpreter)
   - For web applications, start Flask dev server and perform HTTP health check
   - Provide detailed report of any issues found

3. If any check fails, the script will:
   - List incomplete tasks
   - Show constitution violations
   - Display test failures
   - Report web functionality issues
   - Stop the process for manual correction

4. On success, the script will:
   - Confirm all tasks are completed
   - Validate code quality and security
   - Verify all tests pass
   - Confirm web functionality works correctly
   - Provide green light for completion

Usage examples:
- Run from feature branch: `/review`
- Specify feature name: `/review 002-feature`

Context for feature review: $ARGUMENTS