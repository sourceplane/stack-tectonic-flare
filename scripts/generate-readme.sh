#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_mode="${1:-}"

python3 - "$repo_root" "$check_mode" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
check_mode = sys.argv[2] == "--check"
dirty: list[str] = []


def extract(pattern: str, text: str) -> str:
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise SystemExit(f"missing pattern: {pattern!r}")
    return match.group(1).strip()


def write_or_check(path: Path, content: str) -> None:
    normalized = content.rstrip() + "\n"
    current = path.read_text() if path.exists() else None
    if current == normalized:
        return
    dirty.append(str(path.relative_to(root)))
    if not check_mode:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(normalized)


def top_level_assets(directory: Path) -> list[str]:
    if not directory.exists():
        return []
    items: set[str] = set()
    for path in directory.rglob("*"):
        if not path.is_file() or path.name.lower() == "readme.md":
            continue
        rel = path.relative_to(directory)
        items.add(rel.parts[0])
    return sorted(items)


def render_asset_list(directory_name: str, items: list[str], empty_message: str) -> str:
    if not items:
        return f"- {empty_message}"
    return "\n".join(f"- `{directory_name}/{item}`" for item in items)


for contract in sorted((root / "compositions").glob("*/compositions.yaml")):
    text = contract.read_text()
    name = extract(r"^  name:\s*(.+)$", text)
    description = extract(r"^  description:\s*(.+)$", text)
    comp_dir = contract.parent
    example_items = top_level_assets(comp_dir / "examples")
    test_items = top_level_assets(comp_dir / "tests")
    example_list = render_asset_list("examples", example_items, "Add a sample fixture under examples/.")
    test_list = render_asset_list("tests", test_items, "Add a smoke or contract fixture under tests/.")

    readme = f"""# {name}

`{name}` is an exported Orun composition in the Stack Tectonic catalog.

## Purpose

{description}

## Contract

- **Type:** `{name}`
- **Path:** `{comp_dir.relative_to(root)}`
- **Definition:** `compositions.yaml`

## Example fixtures

These sample assets are excerpted or adapted from `example-platform-repo` so the contract is documented with realistic consumer-repo shapes.

{example_list}

## Test fixtures

{test_list}

## Verification

`./scripts/verify-composition.sh {name}` checks that this composition keeps its contract, fixture, and generated-doc scaffolding intact.
"""

    examples_readme = f"""# Examples for {name}

These fixtures are excerpted or adapted from `example-platform-repo` to show how `{name}` looks inside a consumer repository.

{example_list}
"""

    tests_readme = f"""# Tests for {name}

These files provide contract or smoke fixtures that CI can inspect for `{name}` without requiring a full consumer repository checkout.

{test_list}
"""

    write_or_check(comp_dir / "README.md", readme)
    write_or_check(comp_dir / "examples" / "README.md", examples_readme)
    write_or_check(comp_dir / "tests" / "README.md", tests_readme)

if check_mode and dirty:
    print("Generated composition docs are stale:")
    for item in dirty:
        print(f" - {item}")
    raise SystemExit(1)
PY
