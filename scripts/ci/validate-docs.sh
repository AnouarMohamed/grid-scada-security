#!/usr/bin/env bash
set -euo pipefail

mapfile -t markdown_files < <(git ls-files --cached --others --exclude-standard -- '*.md')

if [[ "${#markdown_files[@]}" -eq 0 ]]; then
  echo "No Markdown files found; skipping docs validation."
  exit 0
fi

python3 - "$@" <<'PY'
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

link_pattern = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
reference_pattern = re.compile(r"^\[[^\]]+\]:\s+(\S+)", re.MULTILINE)
skip_schemes = (
    "http://",
    "https://",
    "mailto:",
    "tel:",
)

errors: list[str] = []
root = Path.cwd()

markdown_files = [
    Path(line.strip())
    for line in subprocess.check_output(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            "*.md",
        ],
        text=True,
    ).splitlines()
    if line.strip()
]

for path in markdown_files:
    text = path.read_text(encoding="utf-8")
    if text.count("```") % 2:
        errors.append(f"{path}: unbalanced fenced code block")

    links = [match.group(1) for match in link_pattern.finditer(text)]
    links.extend(match.group(1) for match in reference_pattern.finditer(text))

    for raw_link in links:
        link = raw_link.strip().strip("<>")
        if not link or link.startswith("#") or link.startswith(skip_schemes):
            continue

        target = unquote(link.split("#", 1)[0])
        if not target:
            continue

        resolved = (path.parent / target).resolve()
        try:
            resolved.relative_to(root)
        except ValueError:
            errors.append(f"{path}: link escapes repository root: {raw_link}")
            continue

        if not resolved.exists():
            errors.append(f"{path}: broken relative link: {raw_link}")

if errors:
    for error in errors:
        print(f"::error::{error}")
    sys.exit(1)

print(f"Validated {len(markdown_files)} Markdown files.")
PY
