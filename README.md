# cluster-cli

Shared tooling for the vibe-coded app cluster. Single source of truth for:
- Reusable GitHub Actions workflow that every app's deploy.yml calls
- The local `ship.{ps1,sh}` emergency-deploy scripts
- Project scaffolding templates (`templates/`)
- The audit script that runs the hard checklist against any project

Each app under `anirudhgoel1/*` references this repo's reusable workflow
via `uses: anirudhgoel1/cluster-cli/.github/workflows/_deploy-cf-worker.yml@main`.
Update the workflow here → next push on any app picks up the change.

## Layout

```
cluster-cli/
├── .github/workflows/
│   └── _deploy-cf-worker.yml         # The reusable workflow
├── scripts/
│   ├── ship.ps1                      # Local emergency deploy (Windows)
│   ├── ship.sh                       # Local emergency deploy (Unix)
│   ├── audit.ps1                     # Run the hard checklist against a project
│   └── new-app.ps1                   # Scaffold a new vibe-coded app end-to-end
└── templates/                        # File templates for new apps
    ├── wrangler.toml.tmpl
    ├── _headers.tmpl
    ├── manifest.webmanifest.tmpl
    ├── sw.js.tmpl
    ├── deploy.yml.tmpl
    ├── gitignore.tmpl
    ├── robots.txt.tmpl
    └── README.md.tmpl
```

## Calling the reusable workflow

Minimal `.github/workflows/deploy.yml` for any app:

```yaml
name: Deploy <app>
on:
  push: { branches: [main] }
  workflow_dispatch:
concurrency:
  group: deploy-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false
jobs:
  deploy:
    uses: anirudhgoel1/cluster-cli/.github/workflows/_deploy-cf-worker.yml@main
    with:
      domain: <slug>.anirudhgoel.xyz
      # working-directory: hosted   # only if wrangler.toml is in a subdir
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

Inputs:
- `domain` (required) · the public hostname to smoke-test after deploy
- `working-directory` (default `.`) · subdir with wrangler.toml. `hosted` for Pit Wall.
- `node-version` (default `'22'`) · wrangler 4.92+ requires Node 22+
- `wrangler-version` (default `'4.92.0'`) · pin for reproducibility
- `smoke-accept-status` (default `'200|301|307|401'`) · regex of accepted HTTP codes for the smoke test
- `dry-run` (default `false`) · set true for PR validation

## Repo settings (one-time per app)

Reusable workflows from private repos in the same owner must be enabled per repo:
- `Settings → Actions → General → Access` → "Accessible from repositories owned by anirudhgoel1"
- Set `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` as repo secrets
