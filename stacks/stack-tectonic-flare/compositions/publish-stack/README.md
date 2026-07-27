# publish-stack

Package an Orun stack and publish it to an OCI registry, with an always-on dry-run in front of the
real upload.

This is the composition this repository uses on itself: the `stack-tectonic` component
([`../../component.yaml`](../../component.yaml)) is of type `publish-stack`, which is how
`ghcr.io/sourceplane/saas-stack-tectonic-flare` gets its tags.

| | |
|---|---|
| Composition type | `publish-stack` |
| Schema | `publish-stack-component` |
| Job | `publish` (default) |
| Default profile | `dry-run` |
| Runner | `ubuntu-22.04`, timeout `20m`, no retries |
| Scope label | `delivery` |

## Steps and profiles

| # | Step | Capability (`publish-stack.`) | What it runs | `dry-run` | `verify` | `release` |
|---|---|---|---|:--:|:--:|:--:|
| 1 | `setup-orun` | `setup` | `sourceplane/orun-action@v1.1.0` | ✅ | ✅ | ✅ |
| 2 | `publish-dry-run` | `dry-run` | `orun publish --dry-run` — resolves the target and builds the archive, uploads nothing | ✅ | ✅ | ✅ |
| 3 | `publish` | `publish` | `orun publish` — builds and uploads | — | — | ✅ |

`dry-run` and `verify` are identical step sets with different intent: `dry-run` is the PR lane,
`verify` the staging lane. `release` adds the upload and carries `requireCleanGitTree: true`, so an
uncommitted working tree fails the profile policy before anything is pushed.

Both steps are `onFailure: stop`, so a packaging error in step 2 prevents the upload in step 3.

## What `orun publish` resolves

The steps take no arguments; everything comes from the stack manifest in the job's working directory
(the component's `path`). For this repo that is
[`stacks/stack-tectonic-flare/stack.yaml`](../../stack.yaml):

| Value | Source |
|---|---|
| Package name | `metadata.name` |
| Version / OCI tag | The matching git tag if the checkout is on one, otherwise `metadata.version` |
| Registry target | The `registry` block — `host`/`namespace`/`repository` |

```
$ orun publish --dry-run
  package    tectonic-flare
  version    2.1.0
  files      64
  registry   ghcr.io/sourceplane/saas-stack-tectonic-flare
  source     inferred from stack.yaml registry block
  ✓ dry run: no files uploaded
  → would push to ghcr.io/sourceplane/saas-stack-tectonic-flare:2.1.0
```

A `stack.yaml` (or `orun.yaml`) must sit in that directory — running from a repo root that has none
fails with `no stack.yaml or orun.yaml found`.

## Inputs

The schema accepts three optional inputs and sets `additionalProperties: true` on `inputs`:

| Input | Required | Status |
|---|:--:|---|
| `registry` | | Declared for forward compatibility. **Not read by the current job template** — the registry comes from `stack.yaml`. |
| `version` | | Declared for forward compatibility. **Not read by the current job template** — the version comes from the git tag or `stack.yaml`. |
| `root` | | Declared for forward compatibility. **Not read by the current job template** — `orun publish` runs in the component directory. |

To publish somewhere else or under a different version today, change `stack.yaml` (or tag the commit)
rather than setting these inputs.

## Registry credentials

The publish step needs a registry login in the runner environment before it runs. This repo's workflow
does that with `docker/login-action` against `ghcr.io` using the workflow `GITHUB_TOKEN`, and grants
`permissions: packages: write`:

```yaml
permissions:
  contents: read
  packages: write
- name: Log in to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

Without it, the upload fails with `oras push failed: ... 403: denied`. The dry-run lane needs no
credentials.

## Usage

```yaml
# stacks/<your-stack>/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: stack-tectonic
spec:
  type: publish-stack
  domain: platform-stack
  subscribe:
    environments:
      - name: dev
        profile: dry-run    # PRs validate packaging only
      - name: staging
        profile: release    # merging to main publishes
      - name: production
        profile: release
  inputs:
    name: stack-tectonic-flare
```

Verify a published tag:

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:sourceplane/saas-stack-tectonic-flare:pull&service=ghcr.io" | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" \
  https://ghcr.io/v2/sourceplane/saas-stack-tectonic-flare/tags/list | jq
```

Publishing a version that already exists in the registry re-pushes the same tag; bump
`metadata.version` with the change instead. See the [release process](../../README.md#versioning-and-publishing).
