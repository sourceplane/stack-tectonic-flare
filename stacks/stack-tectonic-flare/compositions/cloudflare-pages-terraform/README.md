# cloudflare-pages-terraform

Build a static site locally for verification, then reconcile a **Git-connected** Cloudflare Pages
project with Terraform.

The difference from [`cloudflare-pages`](../cloudflare-pages): CI never uploads assets. It proves the
site still builds, then hands the Pages project — repo connection, build command, output directory —
to Terraform. Cloudflare does the real build on push. For a monorepo app, use
[`cloudflare-pages-turbo-terraform`](../cloudflare-pages-turbo-terraform).

| | |
|---|---|
| Composition type | `cloudflare-pages-terraform` |
| Schema | `cloudflare-pages-terraform-component` |
| Job | `verify-reconcile` (default) |
| Default profile | `verify` |
| Runner | `ubuntu-22.04`, timeout `30m`, no retries |
| Scope label | `infra` |

## Steps and profiles

| # | Step | Capability (`cloudflare-pages-terraform.`) | What it runs | `pull-request` | `verify` | `release` |
|---|---|---|---|:--:|:--:|:--:|
| 1 | `setup-node` | `setup-node` | `actions/setup-node@v4` at `nodeVersion` | ✅ | ✅ | ✅ |
| 2 | `install-site-dependencies` | `install` | `cd siteDir && <installCommand>` | ✅ | ✅ | ✅ |
| 3 | `build-site` | `build` | `cd siteDir && <buildCommand>` | ✅ | ✅ | ✅ |
| 4 | `verify-build-output` | `verify` | asserts `outputDir` exists under `siteDir` | ✅ | ✅ | ✅ |
| 5 | `setup-terraform` | `setup-terraform` | `hashicorp/setup-terraform@v4` at `terraformVersion`, wrapper off | ✅ | ✅ | ✅ |
| 6 | `terraform-context` | `terraform-context` | prints `terraform version` and the reconcile target | ✅ | ✅ | ✅ |
| 7 | `terraform-fmt-check` | `terraform-fmt` | `terraform -chdir=<terraformDir> fmt -check` | ✅ | ✅ | ✅ |
| 8 | `terraform-init` | `terraform-init` | `terraform init -input=false` (real backend) | — | ✅ | ✅ |
| 9 | `terraform-validate` | `terraform-validate` | `terraform validate -no-color` | — | ✅ | ✅ |
| 10 | `terraform-plan-or-apply` | `terraform-apply` | `plan` off the production branch, `apply -auto-approve` on it | — | — | ✅ |

`pull-request` deliberately stops before `init`, so PRs need no backend credentials and stay fast.
Every step is `onFailure: stop`.

## Inputs

All thirteen inputs are required, and `additionalProperties: false`.

| Input | Description |
|---|---|
| `siteDir` | Directory containing the site; steps 2–4 `cd` here. |
| `installCommand` | Install command run in `siteDir`, e.g. `npm ci`. |
| `buildCommand` | Local verification build, e.g. `npm run build`. |
| `cloudflareBuildCommand` | Build command Cloudflare runs for the Git-connected project. Passed to Terraform as `build_command`. Often differs from `buildCommand` — it runs from `rootDir`, not `siteDir`. |
| `outputDir` | Build output directory. Verified locally under `siteDir` **and** passed to Terraform as `destination_dir`. |
| `rootDir` | Project root Cloudflare builds from, passed as `root_dir` (e.g. `apps/docs`, or `/` for repo root). |
| `nodeVersion` | Node version for `actions/setup-node`. Quote it. |
| `terraformDir` | Directory holding the Terraform configuration for this project. |
| `terraformVersion` | Exact Terraform version for `setup-terraform`. |
| `projectName` | Cloudflare Pages project name, passed as `project_name`. |
| `productionBranch` | Production branch, passed as `production_branch`; also the apply gate. |
| `repoOwner` | GitHub owner for the Pages Git connection, passed as `repo_owner`. |
| `repoName` | GitHub repository name, passed as `repo_name`. |

## Terraform contract

Step 10 always passes the same variables, so the configuration in `terraformDir` must declare:

```hcl
variable "account_id" {}         # from CLOUDFLARE_ACCOUNT_ID
variable "project_name" {}       # projectName
variable "production_branch" {}  # productionBranch
variable "repo_owner" {}         # repoOwner
variable "repo_name" {}          # repoName
variable "build_command" {}      # cloudflareBuildCommand
variable "destination_dir" {}    # outputDir
variable "root_dir" {}           # rootDir
```

Backend configuration is the component's own concern — step 8 runs a plain `init -input=false`, so put
the backend block in `terraformDir`.

## Apply gating

Step 10 has three outcomes:

| Condition | Behaviour |
|---|---|
| `{{.Environment}}` is `production` **and** `GITHUB_REF` is `refs/heads/<productionBranch>` | Asserts both Cloudflare variables, then `terraform apply -auto-approve`. |
| Otherwise, with `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` both set | `terraform plan -lock=false -no-color` — a speculative plan that never takes state locks. |
| Otherwise | Prints a skip notice and exits 0. |

When plan runs without an account id, `account_id` falls back to a 32-zero placeholder so the plan can
render; it is never used on the apply path, where `CLOUDFLARE_ACCOUNT_ID` is required.

| Variable | Needed by |
|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | apply (required), plan (optional — absent ⇒ skip) |
| `CLOUDFLARE_API_TOKEN` | apply (required), plan (optional — absent ⇒ skip). Also read by the Cloudflare Terraform provider. |

## Usage

```yaml
# apps/docs/component.yaml
apiVersion: sourceplane.io/v1
kind: Component
metadata:
  name: docs-site
spec:
  type: cloudflare-pages-terraform
  subscribe:
    environments:
      - name: dev
        profile: pull-request
      - name: staging
        profile: verify
      - name: production
        profile: release
  inputs:
    siteDir: apps/docs
    installCommand: npm ci
    buildCommand: npm run build
    cloudflareBuildCommand: npm run build
    outputDir: dist
    rootDir: apps/docs
    nodeVersion: "20"
    terraformDir: infra/docs-site
    terraformVersion: 1.9.8
    projectName: tectonic-docs
    productionBranch: main
    repoOwner: sourceplane
    repoName: example-platform-repo
```

```bash
orun composition cloudflare-pages-terraform -e
```
