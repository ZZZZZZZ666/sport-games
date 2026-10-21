param(
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$RepositoryName = 'sport-games'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$safeDirectory = $projectRoot.Replace('\', '/')
$gitBase = @('-c', "safe.directory=$safeDirectory")

function Invoke-ProjectGit {
    param([string[]]$GitArguments)
    $result = & git @gitBase -C $projectRoot @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $($GitArguments[0])" }
    return $result
}

function Invoke-GitHub {
    param([string[]]$GhArguments)
    $result = & gh @GhArguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI failed: $($GhArguments[0])" }
    return $result
}

foreach ($commandName in @('git', 'gh', 'node')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Missing $commandName. Install Git, GitHub CLI and Node.js 20+ first."
    }
}

$repositoryRoot = [IO.Path]::GetFullPath((Invoke-ProjectGit -GitArguments @('rev-parse', '--show-toplevel'))).TrimEnd('\', '/')
if (-not $repositoryRoot.Equals($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Repository root must be the game directory, never its parent workspace.'
}

Push-Location -LiteralPath $projectRoot
try {
    & node tools/publication_audit.mjs --strict --write audit-output
    if ($LASTEXITCODE -ne 0) { throw 'Publication audit failed.' }
    & node tools/sync_assets.mjs --check
    if ($LASTEXITCODE -ne 0) { throw 'Upstream asset verification failed.' }
    $dirty = Invoke-ProjectGit -GitArguments @('status', '--porcelain')
    if ($dirty) { throw 'Commit the reviewed project changes before publishing.' }
    $branch = Invoke-ProjectGit -GitArguments @('branch', '--show-current')
    if ($branch -ne 'main') { throw 'This initial publisher expects the main branch.' }

    & gh auth status --hostname github.com
    if ($LASTEXITCODE -ne 0) {
        Invoke-GitHub -GhArguments @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web') | Out-Host
    }
    $owner = Invoke-GitHub -GhArguments @('api', 'user', '--jq', '.login')
    if ($owner -notmatch '^[A-Za-z0-9-]+$') { throw 'Cannot determine the authenticated GitHub account.' }
    $fullName = "$owner/$RepositoryName"
    $repoUrl = "https://github.com/$fullName"
    $remoteUrl = "$repoUrl.git"

    try { $origin = & git @gitBase -C $projectRoot remote get-url origin 2>$null }
    catch { $origin = $null }
    if ($LASTEXITCODE -eq 0) {
        if ($origin -ne $remoteUrl) { throw 'Existing origin differs from the authenticated account and requested repository.' }
    } else {
        Invoke-ProjectGit -GitArguments @('remote', 'add', 'origin', $remoteUrl) | Out-Host
    }

    try { $existingJson = & gh repo view $fullName --json nameWithOwner,isPrivate,isEmpty 2>$null }
    catch { $existingJson = $null }
    if ($LASTEXITCODE -eq 0) {
        $existing = $existingJson | ConvertFrom-Json
        if ($existing.isPrivate) { throw 'An existing private repository has this name; it will not be made public automatically.' }
        if (-not $existing.isEmpty) {
            $remoteHead = Invoke-ProjectGit -GitArguments @('-c', 'credential.helper=', '-c',
                'credential.helper=!gh auth git-credential', 'ls-remote', '--heads', 'origin', 'refs/heads/main')
            $localHead = Invoke-ProjectGit -GitArguments @('rev-parse', 'HEAD')
            if (-not $remoteHead -or ($remoteHead -split '\s+')[0] -ne $localHead) {
                throw 'An existing repository contains different commits; no history will be overwritten.'
            }
        }
    } else {
        Invoke-GitHub -GhArguments @('repo', 'create', $fullName, '--public', '--description',
            'Godot motion-controlled sports games with phone and Regina controllers. No Git LFS required.') | Out-Host
    }

    # The credential helper applies only to this command. Global Git settings are untouched.
    Invoke-ProjectGit -GitArguments @('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential',
        'push', '--set-upstream', 'origin', 'main') | Out-Host
    $published = Invoke-ProjectGit -GitArguments @('-c', 'credential.helper=', '-c',
        'credential.helper=!gh auth git-credential', 'ls-remote', '--heads', 'origin', 'refs/heads/main')
    $head = Invoke-ProjectGit -GitArguments @('rev-parse', 'HEAD')
    if (-not $published -or ($published -split '\s+')[0] -ne $head) { throw 'Remote commit verification failed.' }
    Write-Host "Uploaded and verified: $repoUrl"
} finally {
    Pop-Location
}
