# terraform

`terraform` is an exported Orun composition in the Stack Tectonic catalog.

## Purpose

Terraform validation jobs for infra components

## Contract

- **Type:** `terraform`
- **Path:** `compositions/terraform`
- **Definition:** `compositions.yaml`

## Example fixtures

These sample assets are excerpted or adapted from `example-platform-repo` so the contract is documented with realistic consumer-repo shapes.

- `examples/network-foundation`

## Test fixtures

- `tests/smoke`

## Verification

`./scripts/verify-composition.sh terraform` checks that this composition keeps its contract, fixture, and generated-doc scaffolding intact.
