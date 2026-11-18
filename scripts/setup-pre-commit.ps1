# ForgeOps Gate G09.3: Pre-Commit Hook Installer (Windows PowerShell)
# Configures Git core.hooksPath to .githooks and verifies Gitleaks.

$ErrorActionPreference = "Stop"

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) {
    $repoRoot = Get-Location
}

Write-Host "=== ForgeOps Pre-Commit Hook Setup (Windows PowerShell) ===" -ForegroundColor Cyan

# 1. Configure git hooks path
Write-Host "--> Configuring git core.hooksPath to .githooks..." -ForegroundColor Yellow
git config core.hooksPath .githooks
Write-Host "  [PASS] Git core.hooksPath set to .githooks." -ForegroundColor Green

# 2. Check Gitleaks
$gitleaks = Get-Command gitleaks -ErrorAction SilentlyContinue
if ($gitleaks) {
    $ver = & gitleaks version
    Write-Host "  [PASS] Gitleaks found: $ver at $($gitleaks.Source)" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Gitleaks executable not found in PATH." -ForegroundColor Yellow
    Write-Host "         To install on Windows:" -ForegroundColor Gray
    Write-Host "           winget install Gitleaks.Gitleaks" -ForegroundColor Gray
    Write-Host "           or choco install gitleaks" -ForegroundColor Gray
    Write-Host "         Or run inside WSL2 using 'scripts/setup-pre-commit.sh'." -ForegroundColor Gray
}

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " Pre-commit secret scanning configured.           " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
