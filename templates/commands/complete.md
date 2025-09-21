---
description: Complete a feature by merging to the default branch (run review first)
scripts:
  sh: scripts/bash/complete.sh
  ps: scripts/powershell/complete.ps1
---

Given the context provided as an argument, do this:

1. Run the script `{SCRIPT}` from repo root to perform the merge.

2. The script will automatically:
   - Verify working tree is clean (atomic commit discipline)
   - Detect the default branch (master/main) and switch to it
   - Merge the feature branch
   - Preserve the feature branch

3. Prerequisites (run review command first):
   - All feature tasks must be completed
   - Changes must comply with constitution
   - All tests must pass
   - Web functionality must work correctly

4. On success, the script will:
   - Merge cleanly to the default branch
   - Preserve the feature branch for reference
   - Prepare for next feature development

Usage examples:
- Run from feature branch after review: `/complete`
- Specify feature name: `/complete 002-feature`

Note: Always run `/review-feature` command first to ensure feature is ready for completion.

Context for feature completion: $ARGUMENTS