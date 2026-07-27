# cloudflare-worker

Verify a Cloudflare Worker and deploy it from the production branch with your own deploy command.

Use this for a Worker that owns its install and build commands. For a Worker inside a pnpm + Turborepo
workspace, use [`cloudflare-worker-turbo`](../cloudflare-worker-turbo), which installs at the workspace
root and defaults its build and typecheck to Turbo.

| | |
|---|---|
| Composition type | `cloudflare-worker` |
| Schema | `cloudflare-worker-component` |
| Job | `verify-deploy` (default) |
| Default profile | `verify` |
| Runner | `ubuntu-22.04`, timeout `30m`, no retries |
| Scope label | `delivery` |

## Steps and profiles

| # | Step | Capability (`cloudflare-worker.`) | What it runs | `pull-request` | `verify` | `deploy` |
|---|---|---|---|:--:|:--:|:--:|
| 1 | `setup-node` | `setup` | `actions/setup-node@v4` at `nodeVersion` | ✅ | ✅ | ✅ |
| 2 | `install-dependencies` | `install` | installs pnpm globally when `pnpmVersion` is set, then `installCommand` | ✅ | ✅ | ✅ |
| 3 | `verify-worker-structure` | `verify-structure` | `test -f package.json` plus the Wrangler config check below | ✅ | ✅ | ✅ |
| 4 | `build-worker` | `build` | `buildCommand` | ✅ | ✅ | ✅ |
| 5 | `typecheck-worker` | `typecheck` | `typecheckCommand`, or prints a skip notice | ✅ | ✅ | ✅ |
| 6 | `deploy-worker` | `deploy` | dry-run in `dev`, real deploy on the production branch | — | — | ✅ |

The structure check asserts `wranglerConfig` when set, otherwise requires `wrangler.jsonc` **or**
`wrangler.toml`. Every step is `onFailure: stop`.

## Inputs

`additionalProperties: false` — an unrecognised key fails validation.

| Input | Required | Description |
|---|:--:|---|
| `installCommand` | ✅ | e.g. `npm ci` or `pnpm install --frozen-lockfile`. |
| `buildCommand` | ✅ | e.g. `npm run build`. Interpolated unconditionally, so it must be set even if it is a no-op. |
| `deployCommand` | ✅ | The real deploy, e.g. `npx wrangler deploy`. Runs only after the production gate. |
| `nodeVersion` | ✅ | Node version for `actions/setup-node`. Quote it. |
| `productionBranch` | ✅ | Branch allowed to deploy, e.g. `main`. |
| `pnpmVersion` | | When set, the install step runs `npm install -g pnpm@<version>` first. |
| `typecheckCommand` | | Omitted ⇒ step prints `Skipping typecheck (not configured).` |
| `wranglerConfig` | | Explicit path to the Wrangler config, e.g. `wrangler.production.jsonc`. |
| `preDeployCommand` | | Runs inside the deploy step, before migrations, in a `::group::Pre-deploy` block. |
| `migrationCommand` | | Database or D1 migrations, run after `preDeployCommand` in a `::group::Run migrations` block. |
| `smokeCommand` | | Post-deploy check; a failure fails the job. |

## Deployment behaviour

Step 6 branches three ways:

| Condition | Behaviour |
|---|---|
| `{{.Environment}}` is `dev` | `::notice::DRY-RUN:` then `pnpm exec wrangler deploy --dry-run` — real Wrangler validation with no upload. |
| Not `production`, or `GITHUB_REF` is not `refs/heads/<productionBranch>` | `::notice::SKIPPED:` and exit 0. |
| `production` on the production branch | Asserts credentials, then `preDeployCommand` → `migrationCommand` → `deployCommand` → `smokeCommand`, bracketed by `::notice::LIVE DEPLOY:` and `::notice::DEPLOY SUCCESS:`. |

The `dev` dry-run path invokes `pnpm exec wrangler`, so a component that subscribes `dev` to a profile
containing `deploy` needs pnpm on the runner — set `pnpmVersion` or keep `dev` on `pull-request`, which
excludes the deploy capability entirely. The default `dev` wiring in this stack uses `pull-request`.

| Variable | Needed by | Notes |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | live deploy | Asserted after the gate; not needed for the `dev` dry-run. |
| `CLOUDFLARE_API_TOKEN` | live deploy | Needs Workers Scripts edit permission. |

Anything `migrationCommand` needs (for example `SUPABASE_API_KEY`) must be present in the runner
environment — see the workflow's `env:` block.

## Usage

```yaml
# services/identity/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: identity-worker
spec:
  type: cloudflare-worker
  subscribe:
    environments:
      - name: dev
        profile: pull-request
      - name: staging
        profile: verify
      - name: production
        profile: deploy
  inputs:
    installCommand: npm ci
    buildCommand: npm run build
    typecheckCommand: npm run typecheck
    deployCommand: npx wrangler deploy
    nodeVersion: "20"
    productionBranch: main
    wranglerConfig: wrangler.jsonc
    migrationCommand: npm run db:migrate
    smokeCommand: curl -fsS https://identity.example.com/healthz
```

```bash
orun composition cloudflare-worker -e
```
