#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
composition_name="${1:?usage: verify-composition.sh <composition-name>}"
composition_dir="$repo_root/compositions/$composition_name"

python3 - "$composition_dir" "$composition_name" <<'PY'
from pathlib import Path
import re
import sys

comp_dir = Path(sys.argv[1])
name = sys.argv[2]

if not comp_dir.exists():
    raise SystemExit(f"missing composition directory: {comp_dir}")

contract_path = comp_dir / "compositions.yaml"
if not contract_path.exists():
    raise SystemExit(f"missing contract: {contract_path}")

contract_text = contract_path.read_text()

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)

require(
    re.search(rf"(?m)^  name:\s*{re.escape(name)}\s*$", contract_text) is not None,
    f"contract metadata.name does not match directory for {name}",
)
require(
    re.search(rf"(?m)^  type:\s*{re.escape(name)}\s*$", contract_text) is not None,
    f"contract spec.type does not match directory for {name}",
)

for relative_path in ("README.md", "examples/README.md", "tests/README.md"):
    require((comp_dir / relative_path).exists(), f"missing required file: {comp_dir / relative_path}")

def non_readme_files(directory: Path) -> list[Path]:
    return sorted(
        path
        for path in directory.rglob("*")
        if path.is_file() and path.name.lower() != "readme.md"
    )

example_assets = non_readme_files(comp_dir / "examples")
test_assets = non_readme_files(comp_dir / "tests")

require(example_assets, f"{name} is missing example assets beyond README.md")
require(test_assets, f"{name} is missing test assets beyond README.md")

def has_matching_component(directory: Path) -> bool:
    for path in directory.rglob("component.yaml"):
        text = path.read_text()
        if re.search(rf"(?m)^  type:\s*{re.escape(name)}\s*$", text):
            return True
    return False

require(has_matching_component(comp_dir / "examples"), f"{name} examples do not include a matching component.yaml")
require(has_matching_component(comp_dir / "tests"), f"{name} tests do not include a matching component.yaml")

print(
    f"{name}: {len(example_assets)} example assets, {len(test_assets)} test assets, "
    f"fixtures verified"
)
PY
