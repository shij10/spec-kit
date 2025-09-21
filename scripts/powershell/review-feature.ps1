#!/usr/bin/env pwsh

.
# Reuse content from review.ps1 (kept for backward compatibility) by dot-sourcing if needed
# For clarity and minimal change, duplicate the script body from review.ps1 would be acceptable,
# but here we dot-source the existing file to avoid divergence.

try {
    $scriptPath = Join-Path $PSScriptRoot 'review.ps1'
    if (Test-Path $scriptPath) {
        . $scriptPath
    } else {
        Write-Error "Missing review.ps1 to source."
        exit 1
    }
} catch {
    Write-Error $_
    exit 1
}


