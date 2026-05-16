#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

./scripts/generate-readme.sh --check
./scripts/score.sh --check

for contract in "$repo_root"/compositions/*/compositions.yaml; do
  composition_name="$(basename "$(dirname "$contract")")"
  ./scripts/verify-composition.sh "$composition_name"
done

stack_version="$(awk '/^  version: /{print $2}' stack.yaml)"
test -n "$stack_version"

kiox -- orun publish "ghcr.io/sourceplane/stack-tectonic:${stack_version}" \
  --dry-run \
  --root . \
  --version "$stack_version"
