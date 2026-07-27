# terraform

Validate a Terraform stack: `fmt`, `init`, `validate`, `plan`. This composition is **validation-only** —
no shipped profile applies.

Use it for infrastructure that is reconciled by a separate apply workflow, or for modules you want
checked on every PR. Cloudflare Pages projects that Terraform owns end to end are covered by
[`cloudflare-pages-terraform`](../cloudflare-pages-terraform) and
[`cloudflare-pages-turbo-terraform`](../cloudflare-pages-turbo-terraform), which do apply on the
production branch.

| | |
|---|---|
| Composition type | `terraform` |
| Schema | `terraform-component` |
| Job | `terraform` (default), template `terraform-validate` |
| Default profile | `verify` |
| Runner | `ubuntu-22.04`, timeout `20m`, no retries |
| Scope label | `infra` |

## Steps and profiles

| # | Step (`id`) | Capability (`terraform.`) | What it runs | `pull-request` | `verify` | `release` |
|---|---|---|---|:--:|:--:|:--:|
| 1 | `setup-terraform` | `setup` | `hashicorp/setup-terraform@v4` at `terraformVersion`, wrapper off | ✅ | ✅ | ✅ |
| 2 | `terraform-context` | `context` | prints `terraform version` | ✅ | ✅ | ✅ |
| 3 | `terraform-fmt-check` | `fmt` | `terraform fmt -check` | ✅ | ✅ | ✅ |
| 4 | `terraform-init` | `init` | `terraform init` | ✅ | ✅ | ✅ |
| 5 | `terraform-validate` | `validate` | `terraform validate -no-color` | ✅ | ✅ | ✅ |
| 6 | `terraform-plan` | `plan` | `terraform plan -no-color` | ✅ | ✅ | ✅ |
| 7 | `terraform-apply` | `apply` | `terraform apply -no-color -auto-approve` | — | — | — |

Steps 3–7 prefix themselves with `cd "<terraformDir>" &&` when `terraformDir` is set, and run in the
component directory otherwise. Every step is `onFailure: stop`.

Step 7 is declared but selected by no shipped profile, so it never runs. It is kept so an apply-capable
profile can be added without changing the job template.

> **Changed in 2.1.0** — `verify` used to include `terraform.apply`, so a profile documented as
> "full non-mutating verification" planned `terraform apply -auto-approve`. `terraform.apply` was
> removed from that profile. If you were relying on `verify` to apply infrastructure, move that work to
> a dedicated apply workflow.

### Profile differences

| Profile | Purpose | Notable behaviour |
|---|---|---|
| `pull-request` | Fast PR signal | Overrides `terraform-init` to `terraform -chdir=<terraformDir> init -backend=false -input=false` (no backend credentials needed) and `terraform-plan` to `terraform -chdir=<terraformDir> plan -no-color -lock=false` (speculative, takes no state lock). |
| `verify` | Full non-mutating verification | Real `init` against the configured backend, then `validate` and `plan`. |
| `release` | Release-grade validation before an apply-capable workflow | Same steps as `verify`, plus policies: `requireCleanGitTree`, `requirePinnedTerraformVersion`, `requireApproval`. |

`pull-request` uses `stepOverrides`, which replace a step's `run` while keeping its position and
capability — the mechanism for lane-specific flags without duplicating the job template.

## Inputs

`additionalProperties: false` — an unrecognised key fails validation. The schema marks none of the
inner input fields as required, but in practice set at least `terraformDir` and `terraformVersion`.

| Input | Used by | Description |
|---|---|---|
| `terraformDir` | steps 3–7 | Directory holding the Terraform configuration, relative to the component. Unset ⇒ commands run in the component directory. |
| `terraformVersion` | step 1 | Version for `setup-terraform`. Pin it exactly — `release` policy requires a pinned version. |
| `stackName` | — | Free-form label for the stack. Accepted by the schema; not referenced by any step today. |
| `varFile` | — | Accepted by the schema; not referenced by any step today. Pass var files through the configuration or backend config instead. |
| `backendKey` | — | Accepted by the schema; not referenced by any step today. |

Backend configuration belongs in `terraformDir`: `verify` and `release` run a plain `terraform init`,
so whatever the backend block declares is what gets used.

## Credentials

This composition asserts no provider credentials of its own. `verify` and `release` run a real `init`
and `plan`, so the runner needs whatever the backend and providers require (for the Cloudflare
provider, `CLOUDFLARE_API_TOKEN`). `pull-request` runs `init -backend=false`, so it needs none.

## Usage

```yaml
# infra/network/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: network-foundation
spec:
  type: terraform
  subscribe:
    environments:
      - name: dev
        profile: pull-request
      - name: staging
        profile: verify
      - name: production
        profile: release
  inputs:
    stackName: network-foundation
    terraformDir: infra/network
    terraformVersion: 1.9.8
```

```bash
orun composition terraform -e
```
