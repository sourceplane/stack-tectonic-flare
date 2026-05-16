#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_mode="${1:-}"

python3 - "$repo_root" "$check_mode" <<'PY'
from pathlib import Path
import json
import re
import sys

root = Path(sys.argv[1])
check_mode = sys.argv[2] == "--check"

stack_text = (root / "stack.yaml").read_text()
stack_name = re.search(r"(?m)^  name:\s*(.+)$", stack_text).group(1).strip()
stack_title = re.search(r"(?m)^  title:\s*(.+)$", stack_text).group(1).strip()
stack_version = re.search(r"(?m)^  version:\s*(.+)$", stack_text).group(1).strip()
semver = bool(re.fullmatch(r"\d+\.\d+\.\d+", stack_version))

verify_exists = (root / ".github/workflows/verify.yml").exists()
release_exists = (root / ".github/workflows/release.yml").exists()
scorecard_exists = (root / ".github/workflows/scorecard.yml").exists()


def extract(pattern: str, text: str) -> str:
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise SystemExit(f"missing pattern: {pattern!r}")
    return match.group(1).strip()


def category_for(name: str) -> str:
    if "terraform" in name and "cloudflare-pages" in name:
        return "platform"
    if "cloudflare-pages" in name:
        return "hosting"
    if "cloudflare-worker" in name:
        return "edge"
    if name.startswith("terraform"):
        return "infrastructure"
    if name.startswith("helm"):
        return "kubernetes"
    return "developer-experience"


def tags_for(name: str) -> list[str]:
    tags = set(name.split("-"))
    tags.add(category_for(name))
    if "cloudflare" in name:
        tags.add("cloudflare")
    if "turbo" in name:
        tags.add("turbo")
    return sorted(tags)


def grade_for(score: int) -> str:
    if score >= 90:
        return "A+"
    if score >= 80:
        return "A"
    if score >= 65:
        return "B"
    if score >= 50:
        return "C"
    return "D"


def docs_good(readme: Path) -> bool:
    return readme.exists() and len(readme.read_text().strip()) >= 240


def count_assets(directory: Path) -> int:
    if not directory.exists():
        return 0
    return sum(1 for path in directory.rglob("*") if path.is_file() and path.name.lower() != "readme.md")


compositions = []
for contract in sorted((root / "compositions").glob("*/compositions.yaml")):
    text = contract.read_text()
    name = extract(r"^  name:\s*(.+)$", text)
    description = extract(r"^  description:\s*(.+)$", text)
    comp_dir = contract.parent
    readme = comp_dir / "README.md"
    example_assets = count_assets(comp_dir / "examples")
    test_assets = count_assets(comp_dir / "tests")

    score = 0
    if readme.exists():
        score += 10
    if example_assets:
        score += 15
    if test_assets:
        score += 25
    if verify_exists and release_exists:
        score += 20
    if semver:
        score += 10
    if docs_good(readme):
        score += 10
    if scorecard_exists:
        score += 10

    grade = grade_for(score)
    compositions.append(
        {
            "name": name,
            "kind": "composition",
            "path": str(comp_dir.relative_to(root)),
            "description": description,
            "category": category_for(name),
            "verified": score >= 80,
            "score": score,
            "grade": grade,
            "tags": tags_for(name),
            "signals": {
                "readme": readme.exists(),
                "exampleAssets": example_assets,
                "testAssets": test_assets,
                "verifyWorkflow": verify_exists,
                "releaseWorkflow": release_exists,
                "scorecardWorkflow": scorecard_exists,
                "semver": semver,
                "docsGood": docs_good(readme),
            },
        }
    )


blueprints = []
for blueprint in sorted((root / "blueprints").glob("*/blueprint.yaml")):
    text = blueprint.read_text()
    name = extract(r"^  name:\s*(.+)$", text)
    summary = extract(r"^  summary:\s*(.+)$", text)
    uses = re.findall(r"(?m)^    -\s*(.+)$", text)
    bp_dir = blueprint.parent
    readme = bp_dir / "README.md"
    example_assets = count_assets(bp_dir / "examples")

    score = 0
    if readme.exists():
        score += 10
    if len(uses) >= 2:
        score += 20
    if example_assets:
        score += 15
    if verify_exists and release_exists:
        score += 20
    if semver:
        score += 10
    if docs_good(readme):
        score += 10
    if scorecard_exists:
        score += 10

    blueprints.append(
        {
            "name": name,
            "kind": "blueprint",
            "path": str(bp_dir.relative_to(root)),
            "description": summary,
            "uses": uses,
            "verified": score >= 80,
            "score": score,
            "grade": grade_for(score),
        }
    )


index = {
    "stack": {
        "name": stack_name,
        "title": stack_title,
        "version": stack_version,
        "oci": f"oci://ghcr.io/sourceplane/{stack_name}:{stack_version}",
    },
    "catalog": {
        "compositions": compositions,
        "blueprints": blueprints,
    },
}

rendered = json.dumps(index, indent=2, sort_keys=False) + "\n"
index_path = root / "registry/index.json"
current = index_path.read_text() if index_path.exists() else None

if check_mode:
    if current != rendered:
        print("registry/index.json is stale")
        raise SystemExit(1)
else:
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(rendered)
PY
