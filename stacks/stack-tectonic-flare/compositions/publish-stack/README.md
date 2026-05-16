# publish-stack

`publish-stack` is an exported Orun composition in the Stack Tectonic catalog.

## Purpose

Publish an Orun stack to an OCI registry with dry-run validation

## Contract

- **Type:** `publish-stack`
- **Path:** `compositions/publish-stack`
- **Definition:** `compositions.yaml`

## Example fixtures

These sample assets are excerpted or adapted from `example-platform-repo` so the contract is documented with realistic consumer-repo shapes.

- `examples/component.yaml`
- `examples/config.yaml`

## Test fixtures

- `tests/smoke`
- `tests/test.yaml`

## Verification

`./scripts/verify-composition.sh publish-stack` checks that this composition keeps its contract, fixture, and generated-doc scaffolding intact.
