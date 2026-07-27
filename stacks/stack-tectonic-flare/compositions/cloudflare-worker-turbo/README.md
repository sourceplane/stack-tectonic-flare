# cloudflare-worker-turbo

Verify a Cloudflare Worker inside a **pnpm + Turborepo** workspace and deploy it from the production
branch.

The Turbo variant of [`cloudflare-worker`](../cloudflare-worker): dependencies install once at the
workspace root, and build, typecheck, and deploy all have Turbo/pnpm defaults, so a component can
declare almost no inputs.

| | |
|---|---|
| Composition type | `cloudflare-worker-turbo` |
| Schema | `cloudflare-worker-turbo-component` |
| Job | `verify-deploy` (default) |
| Default profile | `verify` |
| Runner | `ubuntu-22.04`, timeout `30m`, no retries |
| Scope label | `delivery` |

## Steps and profiles

| # | Step | Capability (`cloudflare-worker-turbo.`) | What it runs | `pull-request` | `verify` | `deploy` |
|---|---|---|---|:--:|:--:|:--:|
| 1 | `setup-node` | `setup-node` | `actions/setup-node@v4` at `nodeVersion` | ✅ | ✅ | ✅ |
| 2 | `setup-pnpm` | `setup-pnpm` | `pnpm/action-setup@v4` at `pnpmVersion` | ✅ | ✅ | ✅ |
| 3 | `install-workspace-dependencies` | `install` | `pnpm install --no-frozen-lockfile` | ✅ | ✅ | ✅ |
| 4 | `pre-build` | `pre-build` | `preBuildCommand`, or prints a skip notice | ✅ | ✅ | ✅ |
| 5 | `verify-worker-structure` | `verify-structure` | `test -f package.json` plus the Wrangler config check | ✅ | ✅ | ✅ |
| 6 | `build-worker` | `build` | `buildCommand`, default `pnpm exec turbo run build --filter=./` | ✅ | ✅ | ✅ |
| 7 | `typecheck-worker` | `typecheck` | `typecheckCommand`, default `pnpm exec turbo run typecheck --filter=./` | ✅ | ✅ | ✅ |
| 8 | `deploy-worker` | `deploy` | dry-run in `dev`, real deploy on the production branch | — | — | ✅ |

The structure check asserts `wranglerConfig` when set, otherwise requires `wrangler.jsonc` **or**
`wrangler.toml`. Every step is `onFailure: stop`.

Unlike [`cloudflare-worker`](../cloudflare-worker), typecheck is **not** optional here: with no
`typecheckCommand` it falls back to `turbo run typecheck --filter=./`, which fails if the package has no
`typecheck` task. Give the package the task, or set `typecheckCommand` to something harmless.

## Inputs

`additionalProperties: false` — an unrecognised key fails validation.

| Input | Required | Description |
|---|:--:|---|
| `nodeVersion` | ✅ | Node version for `actions/setup-node`. Quote it. |
| `pnpmVersion` | ✅ | pnpm version for `pnpm/action-setup`. Quote it. |
| `productionBranch` | ✅ | Branch allowed to deploy, e.g. `main`. |
| `wranglerConfig` | | Explicit path to the Wrangler config; otherwise `wrangler.jsonc` or `wrangler.toml` must exist. |
| `preBuildCommand` | | Codegen and similar, before the structure check. Omitted ⇒ `Skipping pre-build.` |
| `buildCommand` | | Overrides the default Turbo build. |
| `typecheckCommand` | | Overrides the default Turbo typecheck. |
| `preDeployCommand` | | Runs inside the deploy step, before migrations. |
| `migrationCommand` | | Migrations, after `preDeployCommand`. |
| `deployCommand` | | Overrides the default `pnpm run deploy`. |
| `smokeCommand` | | Post-deploy check; a failure fails the job. |

## Deployment behaviour

| Condition | Behaviour |
|---|---|
| `{{.Environment}}` is `dev` | `::notice::DRY-RUN:` then `pnpm exec wrangler deploy --dry-run`. |
| Not `production`, or `GITHUB_REF` is not `refs/heads/<productionBranch>` | `::notice::SKIPPED:` and exit 0. |
| `production` on the production branch | Asserts credentials, then `preDeployCommand` → `migrationCommand` → `deployCommand` (default `pnpm run deploy`) → `smokeCommand`, bracketed by `::notice::LIVE DEPLOY:` and `::notice::DEPLOY SUCCESS:`. |

| Variable | Needed by | Notes |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | live deploy | Asserted after the gate; not needed for the `dev` dry-run. |
| `CLOUDFLARE_API_TOKEN` | live deploy | Needs Workers Scripts edit permission. |

## Usage

```yaml
# apps/api-edge/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: api-edge
spec:
  type: cloudflare-worker-turbo
  subscribe:
    environments:
      - name: dev
        profile: pull-request
      - name: staging
        profile: verify
      - name: production
        profile: deploy
  inputs:
    nodeVersion: "20"
    pnpmVersion: "9"
    productionBranch: main
    preBuildCommand: pnpm exec turbo run codegen --filter=./
    migrationCommand: pnpm run db:migrate
    smokeCommand: curl -fsS https://api.example.com/healthz
```

```bash
orun composition cloudflare-worker-turbo -e
```
