# cloudflare-pages-turbo-terraform

Verify a **pnpm + Turborepo** Pages app locally, then reconcile its **Git-connected** Cloudflare Pages
project with Terraform.

The union of [`cloudflare-pages-turbo`](../cloudflare-pages-turbo) (workspace install, Turbo build) and
[`cloudflare-pages-terraform`](../cloudflare-pages-terraform) (Terraform owns the project, Cloudflare
runs the real build). CI never uploads assets.

| | |
|---|---|
| Composition type | `cloudflare-pages-turbo-terraform` |
| Schema | `cloudflare-pages-turbo-terraform-component` |
| Job | `verify-reconcile` (default) |
| Default profile | `verify` |
| Runner | `ubuntu-22.04`, timeout `35m`, no retries |
| Scope label | `infra` |

## Steps and profiles

| # | Step | Capability (`cloudflare-pages-turbo-terraform.`) | What it runs | `pull-request` | `verify` | `release` |
|---|---|---|---|:--:|:--:|:--:|
| 1 | `setup-node` | `setup-node` | `actions/setup-node@v4` at `nodeVersion` | ✅ | ✅ | ✅ |
| 2 | `setup-pnpm` | `setup-pnpm` | `pnpm/action-setup@v4` at `pnpmVersion` | ✅ | ✅ | ✅ |
| 3 | `install-workspace-dependencies` | `install` | `pnpm install --no-frozen-lockfile` | ✅ | ✅ | ✅ |
| 4 | `pre-build` | `pre-build` | `preBuildCommand`, or prints a skip notice | ✅ | ✅ | ✅ |
| 5 | `verify-pages-app-structure` | `verify-structure` | `test -f package.json` | ✅ | ✅ | ✅ |
| 6 | `build-pages-app` | `build` | `buildCommand`, default `pnpm exec turbo run build --filter=./` | ✅ | ✅ | ✅ |
| 7 | `verify-build-output` | `verify-output` | asserts `outputDir` exists, lists the first 20 files | ✅ | ✅ | ✅ |
| 8 | `setup-terraform` | `setup-terraform` | `hashicorp/setup-terraform@v4` at `terraformVersion`, wrapper off | ✅ | ✅ | ✅ |
| 9 | `terraform-context` | `terraform-context` | prints `terraform version` and the reconcile target | ✅ | ✅ | ✅ |
| 10 | `terraform-fmt-check` | `terraform-fmt` | `terraform -chdir=<terraformDir> fmt -check` | ✅ | ✅ | ✅ |
| 11 | `terraform-init` | `terraform-init` | `terraform init -input=false` (real backend) | — | ✅ | ✅ |
| 12 | `terraform-validate` | `terraform-validate` | `terraform validate -no-color` | — | ✅ | ✅ |
| 13 | `terraform-plan-or-apply` | `terraform-apply` | `plan` off the production branch, `apply -auto-approve` on it | — | — | ✅ |

`pull-request` stops before `init`, so PRs need no backend credentials. Every step is `onFailure: stop`.

## Inputs

`additionalProperties: false` — an unrecognised key fails validation.

| Input | Required | Description |
|---|:--:|---|
| `cloudflareBuildCommand` | ✅ | Build command **Cloudflare** runs for the Git-connected project. Passed as `build_command`. |
| `outputDir` | ✅ | Local build output, asserted by step 7. Verification only — not passed to Terraform. |
| `destinationDir` | ✅ | Output directory **Cloudflare** publishes, passed as `destination_dir`. Usually the same path expressed relative to `rootDir`. |
| `rootDir` | ✅ | Project root Cloudflare builds from, passed as `root_dir` (e.g. `apps/admin`). |
| `nodeVersion` | ✅ | Node version for `actions/setup-node`. Quote it. |
| `pnpmVersion` | ✅ | pnpm version for `pnpm/action-setup`. Quote it. |
| `terraformDir` | ✅ | Directory holding the Terraform configuration. |
| `terraformVersion` | ✅ | Exact Terraform version for `setup-terraform`. |
| `projectName` | ✅ | Cloudflare Pages project name, passed as `project_name`. |
| `productionBranch` | ✅ | Production branch, passed as `production_branch`; also the apply gate. |
| `repoOwner` | ✅ | GitHub owner for the Pages Git connection, passed as `repo_owner`. |
| `repoName` | ✅ | GitHub repository name, passed as `repo_name`. |
| `preBuildCommand` | | Runs before the structure check. Omitted ⇒ step prints `Skipping pre-build.` |
| `buildCommand` | | Overrides the default Turbo build used for local verification. |

`outputDir` vs `destinationDir` is the one input pair that trips people up: `outputDir` is what CI
checks after building in the workspace, `destinationDir` is what Cloudflare is told to publish relative
to `rootDir`. In a monorepo they are typically `apps/admin/dist` and `dist`.

## Terraform contract

The configuration in `terraformDir` must declare:

```hcl
variable "account_id" {}         # from CLOUDFLARE_ACCOUNT_ID
variable "project_name" {}       # projectName
variable "production_branch" {}  # productionBranch
variable "repo_owner" {}         # repoOwner
variable "repo_name" {}          # repoName
variable "build_command" {}      # cloudflareBuildCommand
variable "destination_dir" {}    # destinationDir
variable "root_dir" {}           # rootDir
```

## Apply gating

| Condition | Behaviour |
|---|---|
| `{{.Environment}}` is `production` **and** `GITHUB_REF` is `refs/heads/<productionBranch>` | Asserts both Cloudflare variables, then `terraform apply -auto-approve`. |
| Otherwise, with `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` both set | `terraform plan -lock=false -no-color`. |
| Otherwise | Prints a skip notice and exits 0. |

`account_id` falls back to a 32-zero placeholder on the plan path only.

## Usage

```yaml
# apps/admin/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: admin-console
spec:
  type: cloudflare-pages-turbo-terraform
  subscribe:
    environments:
      - name: dev
        profile: pull-request
      - name: staging
        profile: verify
      - name: production
        profile: release
  inputs:
    cloudflareBuildCommand: pnpm install && pnpm exec turbo run build --filter=admin-console
    outputDir: dist
    destinationDir: dist
    rootDir: apps/admin
    nodeVersion: "20"
    pnpmVersion: "9"
    terraformDir: infra/admin-console
    terraformVersion: 1.9.8
    projectName: tectonic-admin
    productionBranch: main
    repoOwner: sourceplane
    repoName: example-platform-repo
```

```bash
orun composition cloudflare-pages-turbo-terraform -e
```
