<#
.SYNOPSIS
    Publishes the current state of this folder to GitHub as a SINGLE commit,
    erasing all previous commit history on the remote.

.USAGE
    .\Publish.ps1
    .\Publish.ps1 -Message "Updated security baseline"
#>

param(
    [string]$Message = "USB deployment tool"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Build a fresh orphan branch containing only the current files
git checkout --orphan publish-temp
git add -A
git commit -m $Message

# Replace main with it
git branch -D main
git branch -m main

# Overwrite remote history
git push --force origin main

Write-Host ""
Write-Host "Published. Remote history is now a single commit: '$Message'" -ForegroundColor Green
git log --oneline
