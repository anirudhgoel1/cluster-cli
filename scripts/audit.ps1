# audit.ps1 · run the vibe-coded-launch hard checklist against any project.
#
# Usage:
#   .\audit.ps1 -ProjectDir 'D:\Vibe Coding Projects\Pavilion' -Repo 'anirudhgoel1/pavilion' -Domain 'pavilion.anirudhgoel.xyz'
#   .\audit.ps1 -ProjectDir '.' -Repo (gh repo view --json nameWithOwner -q .nameWithOwner) -Domain 'pavilion.anirudhgoel.xyz'
#
# Exit codes:
#   0  · all P0 checks pass (no blockers)
#   1  · one or more P0 checks failed
#
# Severity ladder:
#   P0 · blocks launch · must fix before next deploy
#   P1 · hygiene · fix in the next pass
#   P2 · polish · nice to have

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectDir,
    [Parameter()][string]$Repo,
    [Parameter()][string]$Domain,
    [Parameter()][string]$WorkingDir = '.'
)

$ErrorActionPreference = 'Stop'
$ProjectDir = (Resolve-Path $ProjectDir).Path
$wd = if ($WorkingDir -eq '.') { $ProjectDir } else { Join-Path $ProjectDir $WorkingDir }

$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param([string]$Section, [string]$Item, [string]$Severity, [bool]$Pass, [string]$Note = '')
    $results.Add([PSCustomObject]@{ Section=$Section; Item=$Item; Severity=$Severity; Pass=$Pass; Note=$Note })
}

function Test-FileExists { param([string]$Path) Test-Path -LiteralPath $Path -PathType Leaf }
function Test-DirExists  { param([string]$Path) Test-Path -LiteralPath $Path -PathType Container }
function Read-File       { param([string]$Path) if (Test-FileExists $Path) { Get-Content -LiteralPath $Path -Raw } else { '' } }

# =============================================================
# A · Git / GitHub / CI
# =============================================================
Add-Result 'A.1' 'Git initialized'         'P0' (Test-DirExists "$ProjectDir/.git")
if (Test-DirExists "$ProjectDir/.git") {
    $branch = (& git -C $ProjectDir rev-parse --abbrev-ref HEAD 2>$null).Trim()
    Add-Result 'A.2' 'Default branch is main'  'P0' ($branch -eq 'main') "current: $branch"
    $unc = (& git -C $ProjectDir status -s 2>$null | Measure-Object -Line).Lines
    Add-Result 'A.3' 'No uncommitted changes' 'P1' ($unc -eq 0) "$unc files dirty"
}
$gi = Read-File "$ProjectDir/.gitignore"
Add-Result 'A.4' '.gitignore covers .wrangler/' 'P0' ($gi -match '\.wrangler/?')
Add-Result 'A.5' '.gitignore covers .claude/'   'P1' ($gi -match '\.claude/?')
Add-Result 'A.6' '.gitignore covers .env'       'P0' ($gi -match '\.env')
Add-Result 'A.7' 'deploy.yml workflow present'  'P0' (Test-FileExists "$ProjectDir/.github/workflows/deploy.yml")
$dy = Read-File "$ProjectDir/.github/workflows/deploy.yml"
Add-Result 'A.8' 'deploy.yml calls cluster-cli reusable' 'P0' ($dy -match 'anirudhgoel1/cluster-cli/\.github/workflows/_deploy-cf-worker\.yml')
Add-Result 'A.9' 'deploy.yml has secrets block' 'P0' ($dy -match 'CLOUDFLARE_API_TOKEN' -and $dy -match 'CLOUDFLARE_ACCOUNT_ID')

if ($Repo) {
    $hasToken = (& gh secret list -R $Repo 2>$null) -match 'CLOUDFLARE_API_TOKEN'
    $hasAcct  = (& gh secret list -R $Repo 2>$null) -match 'CLOUDFLARE_ACCOUNT_ID'
    Add-Result 'A.10' 'CLOUDFLARE_API_TOKEN secret set'    'P0' $hasToken
    Add-Result 'A.11' 'CLOUDFLARE_ACCOUNT_ID secret set'   'P0' $hasAcct
    $latest = & gh run list -R $Repo --limit 1 --workflow=deploy.yml --json conclusion -q '.[0].conclusion' 2>$null
    Add-Result 'A.12' 'Latest CI run succeeded'            'P0' ($latest -eq 'success') "latest: $latest"
    $rd = & gh repo view $Repo --json description,homepageUrl,repositoryTopics 2>$null | ConvertFrom-Json
    Add-Result 'A.13' 'GitHub description set'             'P1' (-not [string]::IsNullOrWhiteSpace($rd.description))
    Add-Result 'A.14' 'GitHub homepage URL set'            'P1' (-not [string]::IsNullOrWhiteSpace($rd.homepageUrl))
    Add-Result 'A.15' 'GitHub topics set (>=3)'            'P2' ($rd.repositoryTopics.Count -ge 3) "$($rd.repositoryTopics.Count) topics"
}

# =============================================================
# B · Cloudflare config
# =============================================================
$wt = Read-File "$wd/wrangler.toml"
Add-Result 'B.1' 'wrangler.toml present'                'P0' ($wt -ne '')
Add-Result 'B.2' 'wrangler.toml has custom_domain route' 'P0' ($wt -match 'custom_domain\s*=\s*true')
Add-Result 'B.3' 'wrangler.toml [assets] block'         'P0' ($wt -match '\[assets\]')
Add-Result 'B.4' 'wrangler.toml [observability] enabled' 'P1' ($wt -match '\[observability\]' -and $wt -match 'enabled\s*=\s*true')
Add-Result 'B.5' '.assetsignore present'                'P1' (Test-FileExists "$wd/.assetsignore")
Add-Result 'B.6' '_headers present'                     'P0' (Test-FileExists "$wd/_headers")
$hd = Read-File "$wd/_headers"
Add-Result 'B.7' '_headers has CSP'                     'P0' ($hd -match 'Content-Security-Policy' -or $hd -match 'Strict-Transport-Security') "(checking HSTS as proxy)"

# =============================================================
# C · SEO + social pack
# =============================================================
$ix = Read-File "$wd/index.html"
if ($ix -ne '') {
    Add-Result 'C.1' 'meta description'                 'P0' ($ix -match '<meta\s+name="description"')
    Add-Result 'C.2' 'og:title'                         'P0' ($ix -match 'og:title')
    Add-Result 'C.3' 'og:image (1200x630)'              'P0' ($ix -match 'og:image' -and $ix -match 'og:image:width.*1200')
    Add-Result 'C.4' 'twitter:card summary_large_image' 'P0' ($ix -match 'summary_large_image')
    Add-Result 'C.5' 'canonical link'                   'P1' ($ix -match 'rel="canonical"')
    Add-Result 'C.6' 'theme-color meta'                 'P0' ($ix -match 'name="theme-color"')
    Add-Result 'C.7' 'JSON-LD WebApplication'           'P1' ($ix -match 'WebApplication')
}
Add-Result 'C.8' 'og.png (social image)'                'P0' (Test-FileExists "$wd/og.png")
Add-Result 'C.9' 'favicon.svg'                          'P1' (Test-FileExists "$wd/favicon.svg")
Add-Result 'C.10' 'icon-192.png'                        'P0' (Test-FileExists "$wd/icon-192.png")
Add-Result 'C.11' 'icon-512.png'                        'P0' (Test-FileExists "$wd/icon-512.png")
Add-Result 'C.12' 'icon-maskable.png'                   'P1' (Test-FileExists "$wd/icon-maskable.png")

# =============================================================
# D · PWA layer
# =============================================================
Add-Result 'D.1' 'manifest.webmanifest'                 'P0' (Test-FileExists "$wd/manifest.webmanifest")
$mf = Read-File "$wd/manifest.webmanifest"
if ($mf -ne '') {
    Add-Result 'D.2' 'manifest has theme_color'         'P0' ($mf -match 'theme_color')
    Add-Result 'D.3' 'manifest has start_url'           'P0' ($mf -match 'start_url')
    Add-Result 'D.4' 'manifest icons (>=3)'             'P0' (($mf -split '"src"').Count -ge 4) "(found $(($mf -split '"src"').Count - 1) icons)"
}
Add-Result 'D.5' 'sw.js service worker'                 'P0' (Test-FileExists "$wd/sw.js")
Add-Result 'D.6' 'robots.txt'                           'P1' (Test-FileExists "$wd/robots.txt")
Add-Result 'D.7' 'sitemap.xml'                          'P1' (Test-FileExists "$wd/sitemap.xml")

# =============================================================
# E · Design hygiene (H1, H2, H10)
# =============================================================
if ($ix -ne '') {
    $emCount = (Select-String -InputObject $ix -Pattern '—' -AllMatches).Matches.Count
    Add-Result 'E.1' 'Em-dash count in index.html'      'P2' ($emCount -lt 5) "($emCount found)"
    Add-Result 'E.2' 'theme-color is paper hex (not dark)' 'P1' ($ix -notmatch 'theme-color"\s+content="#[0-3][0-3][0-3]')
}

# =============================================================
# F · Live URL smoke
# =============================================================
if ($Domain) {
    try {
        $resp = Invoke-WebRequest "https://$Domain/" -Method Head -MaximumRedirection 5 -ErrorAction Stop -TimeoutSec 10
        $sc = $resp.StatusCode
        Add-Result 'F.1' 'Live URL responds 200/301/307/401' 'P0' ($sc -match '^(200|301|307|401)$') "HTTP $sc"
        $themeColor = if ($resp.Content -match 'theme-color"\s+content="(#[0-9a-fA-F]{3,6})"') { $matches[1] } else { 'n/a' }
        Add-Result 'F.2' 'CSP / HSTS header in response' 'P1' ($resp.Headers.Keys -match 'Strict-Transport-Security|Content-Security-Policy')
    } catch {
        Add-Result 'F.1' 'Live URL reachable' 'P0' $false "$_"
    }
}

# =============================================================
# Output
# =============================================================
Write-Host ""
Write-Host "═══ Hard-Checklist Audit · $ProjectDir ═══" -ForegroundColor Cyan
Write-Host ""

$grouped = $results | Group-Object Section | Sort-Object Name
foreach ($g in $grouped) {
    Write-Host "─── Section $($g.Name) ───" -ForegroundColor Cyan
    foreach ($r in $g.Group) {
        $mark = if ($r.Pass) { '✓' } else { '✗' }
        $color = if ($r.Pass) { 'Green' } elseif ($r.Severity -eq 'P0') { 'Red' } else { 'Yellow' }
        $note = if ($r.Note) { "  ($($r.Note))" } else { '' }
        Write-Host ("  {0} [{1}] {2}{3}" -f $mark, $r.Severity, $r.Item, $note) -ForegroundColor $color
    }
    Write-Host ""
}

$summary = @{
    Total  = $results.Count
    Passed = ($results | Where-Object Pass).Count
    P0Fail = ($results | Where-Object { -not $_.Pass -and $_.Severity -eq 'P0' }).Count
    P1Fail = ($results | Where-Object { -not $_.Pass -and $_.Severity -eq 'P1' }).Count
    P2Fail = ($results | Where-Object { -not $_.Pass -and $_.Severity -eq 'P2' }).Count
}

Write-Host "─── Summary ───" -ForegroundColor Cyan
$pct = if ($summary.Total -gt 0) { [math]::Round(100 * $summary.Passed / $summary.Total, 1) } else { 0 }
Write-Host ("  passed: {0}/{1}  ({2}%)" -f $summary.Passed, $summary.Total, $pct) -ForegroundColor Green
if ($summary.P0Fail -gt 0) { Write-Host ("  P0 fails (blockers): {0}" -f $summary.P0Fail) -ForegroundColor Red }
if ($summary.P1Fail -gt 0) { Write-Host ("  P1 fails (hygiene):  {0}" -f $summary.P1Fail) -ForegroundColor Yellow }
if ($summary.P2Fail -gt 0) { Write-Host ("  P2 fails (polish):   {0}" -f $summary.P2Fail) -ForegroundColor DarkYellow }

if ($summary.P0Fail -gt 0) {
    Write-Host ""
    Write-Host "✗ Launch is BLOCKED. Fix P0 items before deploying." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "✓ All P0 checks passed. Ready to ship." -ForegroundColor Green
    exit 0
}
