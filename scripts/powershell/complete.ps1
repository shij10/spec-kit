#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Complete a feature by merging it to the default branch
.DESCRIPTION
    This script performs the following actions:
    1. Verifies working tree is clean (enforces atomic commits)
    2. Merges the current feature branch into the default branch (master/main)
    3. Preserves the feature branch for reference

    Note: This script is designed for local development. No remote operations are performed.
.PARAMETER FeatureName
    The name of the feature being completed (optional, auto-detected if not provided)
.EXAMPLE
    .\complete.ps1
    .\complete.ps1 -FeatureName "002-feature"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$FeatureName
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Color codes for output
$colors = @{
    Success = "`e[32m"
    Error = "`e[31m"
    Warning = "`e[33m"
    Info = "`e[36m"
    Reset = "`e[0m"
}

function Write-ColorOutput($ForegroundColor, $Message) {
    Write-Host "$($colors[$ForegroundColor])$Message$($colors.Reset)"
}

function Get-CurrentFeature {
    # Get current branch name
    $currentBranch = git rev-parse --abbrev-ref HEAD
    if ($currentBranch -eq "master" -or $currentBranch -eq "main") {
        Write-ColorOutput Error "Already on master branch. Please run this from a feature branch."
        exit 1
    }
    return $currentBranch
}

function Get-DefaultBranch {
    # Simple local branch detection - no remote required
    if (git show-ref --verify --quiet refs/heads/main) {
        return 'main'
    } else {
        return 'master'
    }
}

function Complete-Feature {
    param($featureName)

    Write-ColorOutput Info "Completing feature: $featureName"

    # Enforce clean working tree (atomic commits per constitution)
    $status = git status --porcelain
    if ($status) {
        Write-ColorOutput Error "Working tree not clean. Please commit task-by-task (TXXX) before completion."
        exit 1
    }

    # Switch to default branch
    $defaultBranch = Get-DefaultBranch
    Write-ColorOutput Info "Switching to default branch '$defaultBranch'..."
    git checkout $defaultBranch

    # Merge feature branch - simple local merge, no remote operations
    Write-ColorOutput Info "Merging $featureName into $defaultBranch..."
    git merge $featureName

    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput Error "Merge failed. Please resolve conflicts manually."
        exit 1
    }

    Write-ColorOutput Success "Feature '$featureName' merged successfully into '$defaultBranch'!"
    Write-ColorOutput Info "Feature branch '$featureName' is preserved for your reference."
}

# Main execution
try {
    # Check if we're in a git repository
    if (-not (Test-Path ".git")) {
        Write-ColorOutput Error "Not in a git repository."
        exit 1
    }

    # Get current feature if not provided
    if ([string]::IsNullOrWhiteSpace($FeatureName)) {
        $FeatureName = Get-CurrentFeature
    }

    Write-ColorOutput Info "Starting completion process for feature: $FeatureName"
    Write-ColorOutput Warning "Note: This assumes review has been completed successfully."
    Write-Host ""

    # Confirm before proceeding
    $confirm = Read-Host "Proceed with commit and merge to master? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-ColorOutput Warning "Operation cancelled."
        exit 0
    }

    # Complete feature
    Complete-Feature -featureName $FeatureName

} catch {
    Write-ColorOutput Error "An error occurred: $($_.Exception.Message)"
    exit 1
}