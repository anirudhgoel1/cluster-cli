# scaffold.ps1 · materialize a new vibe-coded app from cluster-cli templates.
#
# Called by the `vibe-coded-new` skill after Claude has gathered the
# project parameters. Substitutes {{placeholders}} in templates/*.tmpl
# and writes them into the new project directory.
#
# Does NOT touch git, GitHub, secrets, or PROJECT_META — those are
# orchestrated by the skill via gh CLI + Claude tool calls because
# they involve credentials and cross-repo edits.
#
# Usage:
#   .\scaffold.ps1 -Slug 'echoes' -SlugShort 'echoes' `
#                  -Title 'Echoes' -ShortName 'Echoes' `
#                  -Description 'Most-streamed song of every year, 1960 to 2026.' `
#                  -Domain 'echoes.anirudhgoel.xyz' `
#                  -PaperHex '#F4ECDF' -AccentHex '#1D62C9' `
#                  -DesignSkill 'typeui-claude' `
#                  -LocalDir 'D:\Vibe Coding Projects\Spotify-x-Claude'

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Slug,         # 'pavilion-quiz'
    [Parameter(Mandatory=$true)][string]$SlugShort,    # 'quiz' (the ship.ps1 short key)
    [Parameter(Mandatory=$true)][string]$Title,        # 'Pavilion Quiz Battle'
    [Parameter(Mandatory=$true)][string]$ShortName,    # 'Quiz Battle' (PWA short_name)
    [Parameter(Mandatory=$true)][string]$Description,  # one-sentence pitch
    [Parameter(Mandatory=$true)][string]$Domain,       # 'pavilion-quiz.anirudhgoel.xyz'
    [Parameter(Mandatory=$true)][string]$PaperHex,     # '#FAF9F6' or other paper background hex
    [Parameter(Mandatory=$true)][string]$AccentHex,    # '#1A4488' project accent
    [Parameter()][string]$DesignSkill = 'typeui-claude',
    [Parameter()][string]$LocalDir,
    [Parameter()][switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Resolve paths
$LocalDir = if ($LocalDir) { $LocalDir } else { "D:\Vibe Coding Projects\$Slug" }
$TemplateDir = Join-Path $PSScriptRoot '..\templates'
$TemplateDir = (Resolve-Path $TemplateDir).Path
$today = Get-Date -Format 'yyyy-MM-dd'

if (Test-Path $LocalDir) {
    Write-Host "Directory already exists: $LocalDir" -ForegroundColor Yellow
    Write-Host "Use -LocalDir to point at a different path, or remove the existing folder first."
    exit 1
}

# Validate paper hex (H1 — no dark mode)
if ($PaperHex -match '^#[0-3][0-3][0-3]([0-9a-fA-F]{0,3})$') {
    Write-Host "✗ PaperHex looks too dark ($PaperHex). H1 says paper bg + carbon text. Reject." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "═══ Scaffolding $Slug ═══" -ForegroundColor Cyan
Write-Host "  title:         $Title"
Write-Host "  domain:        $Domain"
Write-Host "  paper bg:      $PaperHex"
Write-Host "  accent:        $AccentHex"
Write-Host "  design skill:  $DesignSkill"
Write-Host "  local dir:     $LocalDir"
Write-Host ""

if ($DryRun) {
    Write-Host "[dry-run] would create $LocalDir + 10 files. Re-run without -DryRun." -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Path $LocalDir | Out-Null
New-Item -ItemType Directory -Path "$LocalDir/.github/workflows" -Force | Out-Null

$subs = [ordered]@{
    '{{slug}}'         = $Slug
    '{{slug_short}}'   = $SlugShort
    '{{title}}'        = $Title
    '{{short_name}}'   = $ShortName
    '{{description}}'  = $Description
    '{{domain}}'       = $Domain
    '{{paper_hex}}'    = $PaperHex
    '{{accent_hex}}'   = $AccentHex
    '{{design_skill}}' = $DesignSkill
    '{{today}}'        = $today
}

$files = [ordered]@{
    'wrangler.toml.tmpl'        = 'wrangler.toml'
    'gitignore.tmpl'            = '.gitignore'
    'assetsignore.tmpl'         = '.assetsignore'
    '_headers.tmpl'             = '_headers'
    'manifest.webmanifest.tmpl' = 'manifest.webmanifest'
    'sw.js.tmpl'                = 'sw.js'
    'robots.txt.tmpl'           = 'robots.txt'
    'sitemap.xml.tmpl'          = 'sitemap.xml'
    'README.md.tmpl'            = 'README.md'
    'deploy.yml.tmpl'           = '.github/workflows/deploy.yml'
}

foreach ($pair in $files.GetEnumerator()) {
    $src = Join-Path $TemplateDir $pair.Key
    $dst = Join-Path $LocalDir $pair.Value
    if (-not (Test-Path $src)) {
        Write-Host "  ✗ template missing: $($pair.Key)" -ForegroundColor Red
        continue
    }
    $content = Get-Content -LiteralPath $src -Raw
    foreach ($k in $subs.Keys) {
        $content = $content.Replace($k, $subs[$k])
    }
    $dstDir = Split-Path -Path $dst -Parent
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Set-Content -Path $dst -Value $content -NoNewline -Encoding UTF8
    Write-Host "  ✓ $($pair.Value)"
}

Write-Host ""
Write-Host "✓ Templates instantiated at $LocalDir" -ForegroundColor Green
Write-Host ""
Write-Host "Remaining steps for the skill to handle:" -ForegroundColor Cyan
Write-Host "  ◆ Write index.html (drive from $DesignSkill)"
Write-Host "  ◆ Render og.png (1200x630) + icon-192/512/maskable.png"
Write-Host "  ◆ git init -b main + first commit"
Write-Host "  ◆ gh repo create anirudhgoel1/$Slug --private --source=. --remote=origin --push"
Write-Host "  ◆ Set CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID secrets on the repo"
Write-Host "  ◆ Enable reusable workflow access (gh api -X PUT .../actions/permissions/access -f access_level=user)"
Write-Host "  ◆ Add ship.ps1 + ship.sh Projects map entry"
Write-Host "  ◆ Add PROJECT_META entry in f1-pit-wall hosted/src/worker.js + redeploy that worker"
Write-Host "  ◆ Add to mission-control PROJECTS array + redeploy"
Write-Host "  ◆ Update cross-link strips on existing live apps (reciprocal)"
Write-Host "  ◆ Write memory: project_$Slug.md + MEMORY.md entry"
Write-Host "  ◆ Obsidian: 02-Default-Architecture + 09-Infrastructure-Snapshot + 00-Overview properties"
Write-Host "  ◆ CHANGELOG entry"
