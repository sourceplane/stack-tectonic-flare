# turbo-package

Verify a shared package in a **pnpm + Turborepo** workspace: install, build, typecheck. Nothing is
deployed and nothing is published.

Use this for libraries and SDKs that other components depend on — the composition exists so a change to
a shared package gets its own check in the plan instead of only being exercised through consumers.

| | |
|---|---|
| Composition type | `turbo-package` |
| Schema | `turbo-package-component` |
| Job | `verify` (default) |
| Default profile | `verify` |
| Runner | `ubuntu-22.04`, timeout `25m`, no retries |
| Scope label | `verify` |

## Steps and profiles

| # | Step | Capability (`turbo-package.`) | What it runs | `quick-check` | `verify` |
|---|---|---|---|:--:|:--:|
| 1 | `setup-node` | `setup-node` | `actions/setup-node@v4` at `nodeVersion` | ✅ | ✅ |
| 2 | `setup-pnpm` | `setup-pnpm` | `pnpm/action-setup@v4` at `pnpmVersion` | ✅ | ✅ |
| 3 | `install-workspace-dependencies` | `install` | `pnpm install --no-frozen-lockfile` | ✅ | ✅ |
| 4 | `pre-build` | `pre-build` | `preBuildCommand`, or prints a skip notice | — | ✅ |
| 5 | `verify-package-structure` | `verify-structure` | `test -f package.json` | ✅ | ✅ |
| 6 | `build-package` | `build` | `buildCommand`, default `pnpm exec turbo run build --filter=./` | — | ✅ |
| 7 | `typecheck-package` | `typecheck` | `typecheckCommand`, default `pnpm exec turbo run typecheck --filter=./` | — | ✅ |

There is no `pull-request` profile here — PRs normally use `verify`, and `quick-check` exists for
components where the full build is too slow to run on every push. Every step is `onFailure: stop`.

This composition has no deploy capability in any profile, so it needs no Cloudflare credentials and
has nothing to gate on `productionBranch`.

## Inputs

`additionalProperties: false` — an unrecognised key fails validation.

| Input | Required | Description |
|---|:--:|---|
| `nodeVersion` | ✅ | Node version for `actions/setup-node`, e.g. `"20"`. Quote it. |
| `pnpmVersion` | ✅ | pnpm version for `pnpm/action-setup`, e.g. `"9"`. Quote it. |
| `preBuildCommand` | | Codegen or schema generation, before the structure check. Omitted ⇒ `Skipping pre-build.` |
| `buildCommand` | | Overrides the default Turbo build. |
| `typecheckCommand` | | Overrides the default Turbo typecheck. Note the default fails if the package has no `typecheck` task — add the task or set this input. |

## Usage

```yaml
# packages/platform-sdk/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: platform-sdk
spec:
  type: turbo-package
  subscribe:
    environments:
      - name: dev
        profile: verify
      - name: staging
        profile: verify
  inputs:
    nodeVersion: "20"
    pnpmVersion: "9"
    preBuildCommand: pnpm exec turbo run codegen --filter=./
```

```bash
orun composition turbo-package -e
```
