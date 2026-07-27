# cloudflare-pages

Build a static site from its own directory and **direct-upload** it to Cloudflare Pages with Wrangler.

Use this when CI owns the build. If the Pages project is Git-connected and Cloudflare runs the build,
use [`cloudflare-pages-terraform`](../cloudflare-pages-terraform). If the site is an app inside a
pnpm + Turborepo workspace, use [`cloudflare-pages-turbo`](../cloudflare-pages-turbo).

| | |
|---|---|
| Composition type | `cloudflare-pages` |
| Schema | `cloudflare-pages-component` |
| Job | `verify-deploy` (default) |
| Default profile | `verify` |
| Runner | `ubuntu-22.04`, timeout `25m`, no retries |
| Scope label | `delivery` |

## Steps and profiles

Steps run in this order. A step is planned only when its capability is in the profile's
`includeCapabilities`.

| # | Step | Capability (`cloudflare-pages.`) | What it runs | `pull-request` | `verify` | `deploy` |
|---|---|---|---|:--:|:--:|:--:|
| 1 | `setup-node` | `setup` | `actions/setup-node@v4` at `nodeVersion` | ✅ | ✅ | ✅ |
| 2 | `install-site-dependencies` | `install` | `cd siteDir && <installCommand>` | ✅ | ✅ | ✅ |
| 3 | `build-site` | `build` | `cd siteDir && <buildCommand>` | ✅ | ✅ | ✅ |
| 4 | `verify-build-output` | `verify` | asserts `outputDir` exists, lists the first 20 files | ✅ | ✅ | ✅ |
| 5 | `ensure-pages-project` | `provision` | creates or reconciles the Pages project over the Cloudflare API | — | — | ✅ |
| 6 | `deploy-pages-artifact` | `deploy` | `npx wrangler pages deploy` | — | — | ✅ |

`pull-request` and `verify` cover the same steps today; they stay separate so PR-lane tuning can land
without touching the branch lane. Every step is `onFailure: stop`.

## Inputs

All seven inputs are required, and `additionalProperties: false` — an unrecognised key fails validation.

| Input | Description |
|---|---|
| `siteDir` | Directory containing the site. Steps 2, 3, 4 and 6 `cd` here first. |
| `installCommand` | Dependency install, e.g. `npm ci`. |
| `buildCommand` | Build command, e.g. `npm run build`. |
| `outputDir` | Build output directory, **relative to `siteDir`** (e.g. `dist`). Verified in step 4, uploaded in step 6. |
| `projectName` | Cloudflare Pages project name. Created during `provision` if it does not exist. |
| `nodeVersion` | Node version for `actions/setup-node`, e.g. `"20"`. Quote it — `20.11` unquoted is a float. |
| `productionBranch` | Branch allowed to deploy, and the project's production branch, e.g. `main`. |

## Deployment gating

Steps 5 and 6 exit 0 with a skip message unless **both** hold:

- `{{.Environment}}` is `production`, and
- `GITHUB_REF` is `refs/heads/<productionBranch>`.

Credentials are asserted only after that gate passes, so verify lanes run with no Cloudflare secrets.

| Variable | Needed by | Notes |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | `provision`, `deploy` | Step fails fast if unset once the gate passes. |
| `CLOUDFLARE_API_TOKEN` | `provision`, `deploy` | Needs Pages edit permission on the account. |

`ensure-pages-project` is idempotent: it `GET`s the project, `POST`s it when the API returns 404, then
`PATCH`es `production_branch` either way. Any other status code prints the response body and fails.

## Usage

```yaml
# apps/docs/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: docs-site
spec:
  type: cloudflare-pages
  subscribe:
    environments:
      - name: dev
        profile: pull-request
      - name: staging
        profile: verify
      - name: production
        profile: deploy
  inputs:
    siteDir: apps/docs
    installCommand: npm ci
    buildCommand: npm run build
    outputDir: dist
    projectName: tectonic-docs
    nodeVersion: "20"
    productionBranch: main
```

Inspect the resolved job before committing:

```bash
orun composition cloudflare-pages -e
orun plan --intent intent.yaml
```
