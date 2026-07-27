# cloudflare-pages-turbo

Build a Pages app inside a **pnpm + Turborepo** workspace and direct-upload it to Cloudflare Pages.

The Turbo variant of [`cloudflare-pages`](../cloudflare-pages): dependencies are installed once at the
workspace root with pnpm, and the build runs through `turbo` rather than a per-site install command.
If the Pages project is Git-connected, use
[`cloudflare-pages-turbo-terraform`](../cloudflare-pages-turbo-terraform) instead.

| | |
|---|---|
| Composition type | `cloudflare-pages-turbo` |
| Schema | `cloudflare-pages-turbo-component` |
| Job | `verify-deploy` (default) |
| Default profile | `verify` |
| Runner | `ubuntu-22.04`, timeout `30m`, no retries |
| Scope label | `delivery` |

## Steps and profiles

| # | Step | Capability (`cloudflare-pages-turbo.`) | What it runs | `pull-request` | `verify` | `deploy` |
|---|---|---|---|:--:|:--:|:--:|
| 1 | `setup-node` | `setup-node` | `actions/setup-node@v4` at `nodeVersion` | ✅ | ✅ | ✅ |
| 2 | `setup-pnpm` | `setup-pnpm` | `pnpm/action-setup@v4` at `pnpmVersion` | ✅ | ✅ | ✅ |
| 3 | `install-workspace-dependencies` | `install` | `pnpm install --no-frozen-lockfile` | ✅ | ✅ | ✅ |
| 4 | `pre-build` | `pre-build` | `preBuildCommand`, or prints a skip notice | ✅ | ✅ | ✅ |
| 5 | `verify-pages-app-structure` | `verify-structure` | `test -f package.json` | ✅ | ✅ | ✅ |
| 6 | `build-pages-app` | `build` | `buildCommand`, default `pnpm exec turbo run build --filter=./` | ✅ | ✅ | ✅ |
| 7 | `verify-build-output` | `verify-output` | asserts `outputDir` exists, lists the first 20 files | ✅ | ✅ | ✅ |
| 8 | `ensure-pages-project` | `provision` | creates or reconciles the Pages project over the Cloudflare API | — | — | ✅ |
| 9 | `deploy-pages-artifact` | `deploy` | `pnpm exec wrangler pages deploy`, then `smokeCommand` | — | — | ✅ |

Steps run with the component directory as the working directory, so the default `--filter=./` targets
this package and `outputDir` is resolved relative to it. Every step is `onFailure: stop`.

## Inputs

`additionalProperties: false` — an unrecognised key fails validation.

| Input | Required | Description |
|---|:--:|---|
| `outputDir` | ✅ | Build output directory relative to the component, e.g. `dist`. Verified in step 7, uploaded in step 9. |
| `projectName` | ✅ | Cloudflare Pages project name. Created during `provision` if missing. |
| `nodeVersion` | ✅ | Node version for `actions/setup-node`, e.g. `"20"`. Quote it. |
| `pnpmVersion` | ✅ | pnpm version for `pnpm/action-setup`, e.g. `"9"`. Quote it. |
| `productionBranch` | ✅ | Branch allowed to deploy, and the project's production branch. |
| `preBuildCommand` | | Runs before the structure check — codegen, schema generation, prisma, etc. Omitted ⇒ step prints `Skipping pre-build.` |
| `buildCommand` | | Overrides the default Turbo build. |
| `smokeCommand` | | Post-deploy check, run inside the deploy step after a successful upload. A failure here fails the job. |

## Deployment gating

Steps 8 and 9 exit 0 with a `::notice::SKIPPED:` annotation unless **both** hold:

- `{{.Environment}}` is `production`, and
- `GITHUB_REF` is `refs/heads/<productionBranch>`.

A live upload emits `::notice::LIVE DEPLOY:` before and `::notice::DEPLOY SUCCESS:` after, so the
GitHub Actions summary shows exactly which components deployed.

| Variable | Needed by | Notes |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | `provision`, `deploy` | Asserted after the gate; step fails fast if unset. |
| `CLOUDFLARE_API_TOKEN` | `provision`, `deploy` | Needs Pages edit permission. |

## Usage

```yaml
# apps/web-console/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: web-console
spec:
  type: cloudflare-pages-turbo
  subscribe:
    environments:
      - name: dev
        profile: pull-request
      - name: staging
        profile: verify
      - name: production
        profile: deploy
  inputs:
    outputDir: dist
    projectName: tectonic-web-console
    nodeVersion: "20"
    pnpmVersion: "9"
    productionBranch: main
    preBuildCommand: pnpm exec turbo run codegen --filter=./
    smokeCommand: curl -fsS https://tectonic-web-console.pages.dev/healthz
```

```bash
orun composition cloudflare-pages-turbo -e
```
