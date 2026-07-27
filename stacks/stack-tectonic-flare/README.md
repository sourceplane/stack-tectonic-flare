# Tectonic Flare Platform Stack

Package identity, from [`stack.yaml`](stack.yaml):

| | |
|---|---|
| Stack name | `tectonic-flare` |
| Version | `2.1.0` |
| Owner | `sourceplane` |
| Registry | `ghcr.io/sourceplane/saas-stack-tectonic-flare` (public) |
| Compositions | 9 |

This directory is the publishable unit. `orun publish` reads `stack.yaml` from here, archives the
tree, and pushes it to the registry above under the tag in `metadata.version`.

## Anatomy of a composition

Every composition is four files that answer four separate questions:

| File | Kind | Question it answers |
|---|---|---|
| `composition.yaml` | `Composition` | What is this type called, which schema validates it, which jobs and profiles exist, and what are the defaults? |
| `schema.yaml` | `ComponentSchema` | What inputs may a component of this type set, and which are required? |
| `jobs/*.yaml` | `JobTemplate` | What is the complete, ordered list of steps — every step any profile could run? |
| `profiles/*.yaml` | `ExecutionProfile` | For a given lane, which of those steps actually run, and under what policy? |

The split matters: **the job template is written once, with every step**, and profiles subtract from it.
There is no `if PR then skip` logic in the step list. A step is selected purely by whether its
`capability` appears in the profile's `includeCapabilities`.

```yaml
# jobs/cloudflare-worker-verify-deploy.yaml  (excerpt)
steps:
  - id: build-worker
    capability: cloudflare-worker.build     # <- selector
    run: "{{.buildCommand}}"

# profiles/cloudflare-worker-pull-request.yaml  (excerpt)
jobs:
  verify-deploy:
    includeCapabilities:
      - cloudflare-worker.build             # <- included, so the step runs
      # cloudflare-worker.deploy omitted, so deploy is not planned at all
```

Capabilities are namespaced by composition type (`cloudflare-worker.build`, not `build`), so two
compositions in the same plan never collide.

## Profile lanes

Names are consistent across the catalog so a component can subscribe to the same lane everywhere:

| Lane | Present in | Meaning |
|---|---|---|
| `pull-request` | all deploy-capable compositions | Cheapest useful signal on a PR: set up, install, build, verify. Never mutates a remote. |
| `verify` | all | Full non-mutating verification. Same shape as `pull-request` plus anything slow but safe (Terraform `init` / `validate`). |
| `quick-check` | `turbo-package` | Structure-only smoke: install and check the package exists, skipping build and typecheck. |
| `deploy` | direct-upload compositions | `verify` plus provision and deploy. |
| `release` | Terraform-backed compositions, `publish-stack` | `verify` plus the mutating apply/publish, gated by profile policies. |
| `dry-run` | `publish-stack` | Validation-only publish (`orun publish --dry-run`). |

`release` profiles carry policies that the runner enforces before the mutating step:
`requireCleanGitTree`, `requirePinnedTerraformVersion`, `requireApproval`.

## Two layers of gating

Profiles decide **whether a mutating step is planned**. The steps themselves add a second guard, so a
misrouted plan still cannot deploy from the wrong place. Every deploy and apply step in this catalog
starts with:

```bash
if [ "{{.Environment}}" != "production" ] || [ "${GITHUB_REF:-}" != "refs/heads/{{.productionBranch}}" ]; then
  echo "Skipping ..."; exit 0
fi
```

So a live deploy requires **all** of: a profile that includes the deploy capability, the `production`
environment, and `GITHUB_REF` on the component's `productionBranch`. Anywhere else the step exits 0
with a skip notice. The Worker compositions add one more case: in the `dev` environment they run
`wrangler deploy --dry-run` instead of skipping outright, so PRs get real Wrangler validation.

Credentials are asserted only after that gate passes (`: "${CLOUDFLARE_API_TOKEN:?...}"`), which is why
the verify lanes run fine on forks and locally with no Cloudflare secrets present.

## Template context

Step `run` blocks are Go templates. Available keys:

| Key | Source |
|---|---|
| `{{.Environment}}` | The environment the job was planned into — `dev`, `staging`, `production` |
| `{{.Component}}` | The component's name, used in the log notices |
| `{{.anyInput}}` | Any input the component set, validated against `schema.yaml` |

Optional inputs are guarded with `{{if .foo}}…{{else}}…{{end}}` so an unset input degrades to a
documented default or an explicit skip, never to an empty command.

## Conventions to keep when adding a composition

1. **One job template per composition.** Add capabilities, not job templates, when a lane needs more.
2. **Name capabilities `<type>.<verb>`** and list every one of them in the template's `capabilities:`
   block as well as on the step.
3. **Required vs optional inputs.** Anything a step interpolates unconditionally belongs in the schema's
   `required:` list. Anything wrapped in `{{if}}` must not be required.
4. **`additionalProperties: false`** on `inputs` — a typo in a consumer's `component.yaml` should fail
   validation, not silently disappear.
5. **`onFailure: stop`** on every step that gates correctness.
6. **Gate mutating steps** on `{{.Environment}}` and `productionBranch` as shown above, even though the
   profile already excludes them from non-deploy lanes.
7. **Update the composition's `README.md`** in the same change — the profile/capability tables there are
   the consumer-facing contract.

## Versioning and publishing

`metadata.version` in `stack.yaml` is the published OCI tag. Bump it in the same PR that changes any
composition:

| Change | Bump |
|---|---|
| Docs, comments, descriptions | patch |
| New composition, new profile, new optional input | minor |
| Removed or renamed input/profile/capability, or a required input added | major |

Merging to `main` runs the `stack-tectonic · staging · Publish` check, which dry-runs and then publishes.
See the [repository README](../../README.md#releasing) for the full release and verification steps.

## Component contract for this repo

[`component.yaml`](component.yaml) declares the single component that publishes this catalog:

```yaml
spec:
  type: publish-stack
  subscribe:
    environments:
      - name: dev
        profile: dry-run    # PRs validate the package
      - name: staging
        profile: release    # merge to main publishes
      - name: production
        profile: release
```
