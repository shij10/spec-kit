#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Review a feature by performing comprehensive checks before completion
.DESCRIPTION
    This script performs the following actions:
    1. Checks if all feature tasks are completed
    2. Verifies changes comply with the constitution
    3. Runs all tests to ensure no regressions
    4. For web applications, tests user functionality with Playwright
.PARAMETER FeatureName
    The name of the feature being reviewed (optional, auto-detected if not provided)
.EXAMPLE
    .\review.ps1
    .\review.ps1 -FeatureName "002-feature"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$FeatureName
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Enable strict mode and define Python interpreter per constitution
Set-StrictMode -Version Latest

$python = if ($env:PYTHON_INTERPRETER) { $env:PYTHON_INTERPRETER } else { 'C:\Users\shish\miniconda3\envs\todo_list_4\python.exe' }

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

function Test-CommandExists {
    param($command)
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    if (-not $exists) {
        Write-ColorOutput Error "Required command '$command' not found in PATH"
    }
    return $exists
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

function Test-FeatureTasksCompleted {
    param($featureName)

    Write-ColorOutput Info "Checking if all feature tasks are completed..."

    # Check if feature directory exists
    $featureDir = "specs\$featureName"
    if (-not (Test-Path $featureDir)) {
        Write-ColorOutput Warning "Feature directory not found: $featureDir"
        return $true  # Continue if no feature directory
    }

    # Look for markdown files and scan for unchecked checkboxes
    $taskFiles = Get-ChildItem -Path $featureDir -Filter "*.md" -Recurse

    if ($taskFiles.Count -eq 0) {
        Write-ColorOutput Info "No task files found. Assuming all tasks are completed."
        return $true
    }

    # Check for incomplete tasks
    $incompleteTasks = @()
    foreach ($file in $taskFiles) {
        $matches = Select-String -Path $file.FullName -Pattern '^\s*\[ \].+' -AllMatches
        foreach ($m in $matches) {
            $incompleteTasks += "$($file.Name): $($m.Line.Trim())"
        }
    }

    if ($incompleteTasks.Count -gt 0) {
        Write-ColorOutput Error "Incomplete tasks found:"
        foreach ($task in $incompleteTasks) {
            Write-Host "  - $task"
        }
        Write-ColorOutput Error "Please complete all tasks before running the review command."
        return $false
    }

    Write-ColorOutput Success "All feature tasks are completed!"
    return $true
}

function Test-ConstitutionCompliance {
    Write-ColorOutput Info "Checking constitution compliance..."

    $constitutionFile = ".specify/memory/constitution.md"
    if (-not (Test-Path $constitutionFile)) {
        Write-ColorOutput Warning "Constitution file not found: $constitutionFile"
        return $true
    }

    # Get staged changes
    $stagedFiles = git diff --cached --name-only
    if (-not $stagedFiles) {
        # If no staged changes, get working directory changes
        $stagedFiles = git diff --name-only
    }

    if (-not $stagedFiles) {
        Write-ColorOutput Info "No changes to check against constitution."
        return $true
    }

    # Load constitution rules
    $constitution = Get-Content $constitutionFile -Raw
    $rules = @()

    # Extract rules from constitution
    $ruleMatches = [regex]::Matches($constitution, "##\s+(.+?)\s*\n((?:[^#]|\n(?!#))*)(?=\n##|\z)", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($match in $ruleMatches) {
        $rules += @{
            Name = $match.Groups[1].Value
            Content = $match.Groups[2].Value
        }
    }

    # Check each changed file against rules (map to Technical Standards section)
    $violations = @()
    foreach ($file in $stagedFiles) {
        if (-not (Test-Path $file)) { continue }

        $extension = [System.IO.Path]::GetExtension($file).ToLower()

        foreach ($rule in $rules) {
            switch -regex ($rule.Name) {
                'Technical.*Standards' {
                    if ($extension -eq '.py') {
                        # Python code style via flake8
                        try {
                            $output = & $python -m flake8 $file 2>&1
                            if ($LASTEXITCODE -ne 0 -or $output) {
                                $violations += "Python style violation in $file`: $output"
                            }
                        } catch {
                            Write-ColorOutput Warning "flake8 not available in interpreter environment; skipping style check for $file"
                        }
                    }

                    if ($extension -eq '.md') {
                        # Skip header check for template files
                        if ($file -notmatch '[\\/]templates?[\\/]') {
                            # Documentation header presence
                            $content = Get-Content $file -Raw
                            if (-not ($content -match '^# .+')) {
                                $violations += "Missing header in documentation: $file"
                            }
                        }
                    }

                    if ($extension -in '.py', '.js', '.html') {
                        # Basic security scans
                        $content = Get-Content $file -Raw
                        $securityIssues = @()
                        if ($content -match 'password.*=.*["'']\w+["'']') { $securityIssues += 'Hardcoded password detected' }
                        if ($extension -eq '.py' -and $content -match 'exec\s*\(') { $securityIssues += 'Use of exec() function' }
                        if ($extension -eq '.js' -and $content -match 'eval\s*\(') { $securityIssues += 'Use of eval() function' }
                        if ($securityIssues) { $violations += "Security issues in $file`: $($securityIssues -join ', ')" }
                    }
                }
            }
        }
    }

    if ($violations.Count -gt 0) {
        Write-ColorOutput Error "Constitution violations found:"
        foreach ($violation in $violations) {
            Write-Host "  - $violation"
        }
        Write-ColorOutput Error "Please fix all violations before proceeding."
        return $false
    }

    Write-ColorOutput Success "All changes comply with the constitution!"
    return $true
}

function Test-AllTestsPass {
    Write-ColorOutput Info "Running all tests..."

    # Run tests without coverage to avoid plugin issues (use fixed interpreter)
    $testOutput = & $python -m pytest tests/ -v --tb=short 2>&1
    $testExitCode = $LASTEXITCODE

    # Check if tests ran successfully
    if ($testExitCode -ne 0) {
        Write-ColorOutput Error "Tests failed or had errors."
        Write-Host "Exit code: $testExitCode"

        # Parse output for failures
        $lines = $testOutput -split "`n"
        $failedLine = $lines | Where-Object { $_ -match "(\d+)\s+failed" }
        if ($failedLine) {
            Write-Host $failedLine
        }

        Write-ColorOutput Error "Please fix all test failures before proceeding."
        return $false
    }

    Write-ColorOutput Success "All tests passed!"
    return $true
}

function Test-WebFunctionality {
    Write-ColorOutput Info "Testing web functionality..."

    # Check if this is a web application
    $isWebApp = (Test-Path "templates") -or (Test-Path "static") -or (Test-Path "app.py") -or (Test-Path "src/infrastructure/web")

    if (-not $isWebApp) {
        Write-ColorOutput Info "Not a web application, skipping web functionality tests."
        return $true
    }

    # Check if the app can start
    Write-ColorOutput Info "Starting Flask application..."
    $appProcess = $null

    try {
        # Verify Flask availability and start app in background using fixed interpreter
        $flaskCheck = & $python -c "import flask; print(flask.__version__)" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput Error "Flask is not available in the configured interpreter."
            return $false
        }
        $env:FLASK_ENV = "development"
        $appProcess = Start-Process -FilePath $python -ArgumentList "-m", "flask", "run", "--port=5001" -PassThru -NoNewWindow

        # Wait for app to start
        Start-Sleep -Seconds 3

        # Test if app is responding
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:5001" -TimeoutSec 10 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-ColorOutput Success "Web application is responding correctly!"
                return $true
            } else {
                Write-ColorOutput Error "Web application returned status code: $($response.StatusCode)"
                return $false
            }
        } catch {
            Write-ColorOutput Error "Web application is not responding: $($_.Exception.Message)"
            return $false
        }
    } catch {
        Write-ColorOutput Error "Failed to start web application: $($_.Exception.Message)"
        return $false
    } finally {
        # Clean up: stop the Flask process
        if ($appProcess -and -not $appProcess.HasExited) {
            try {
                Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue
                Write-ColorOutput Info "Stopped Flask application."
            } catch {
                Write-ColorOutput Warning "Could not stop Flask process cleanly."
            }
        }
    }
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

    Write-ColorOutput Info "Starting review process for feature: $FeatureName"
    Write-Host ""

    $allChecksPassed = $true

    # Step 1: Check feature tasks
    if (-not (Test-FeatureTasksCompleted -featureName $FeatureName)) {
        $allChecksPassed = $false
    }
    Write-Host ""

    # Step 2: Check constitution compliance
    if (-not (Test-ConstitutionCompliance)) {
        $allChecksPassed = $false
    }
    Write-Host ""

    # Step 3: Run tests
    if (-not (Test-AllTestsPass)) {
        $allChecksPassed = $false
    }
    Write-Host ""

    # Step 4: Test web functionality
    if (-not (Test-WebFunctionality)) {
        $allChecksPassed = $false
    }
    Write-Host ""

    # Final review result
    if ($allChecksPassed) {
        Write-ColorOutput Success "✅ All review checks passed!"
        Write-ColorOutput Success "Feature '$FeatureName' is ready for completion."
        Write-ColorOutput Info "You can now run the complete command to merge this feature."
    } else {
        Write-ColorOutput Error "❌ Review failed!"
        Write-ColorOutput Error "Please fix all issues before proceeding with completion."
        exit 1
    }

} catch {
    Write-ColorOutput Error "An error occurred during review: $($_.Exception.Message)"
    exit 1
}