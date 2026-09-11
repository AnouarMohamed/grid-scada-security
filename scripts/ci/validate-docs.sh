#!/usr/bin/env bash
set -euo pipefail

mapfile -t markdown_files < <(git ls-files --cached --others --exclude-standard -- '*.md')

existing_markdown_files=()
for markdown_file in "${markdown_files[@]}"; do
  [[ -f "${markdown_file}" ]] || continue
  existing_markdown_files+=("${markdown_file}")
done

if [[ "${#existing_markdown_files[@]}" -eq 0 ]]; then
  echo "No Markdown files found; skipping docs validation."
  exit 0
fi

python3 - "$@" <<'PY'
import base64
import binascii
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote

link_pattern = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
reference_pattern = re.compile(r"^\[[^\]]+\]:\s+(\S+)", re.MULTILINE)
html_image_pattern = re.compile(r"<img\b[^>]*>", re.IGNORECASE)
html_src_pattern = re.compile(r"\bsrc=[\"']([^\"']+)[\"']", re.IGNORECASE)
responsive_width_pattern = re.compile(r"\bwidth=[\"']100%[\"']", re.IGNORECASE)
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
    if line.strip() and Path(line.strip()).is_file()
]

for path in markdown_files:
    text = path.read_text(encoding="utf-8")
    if text.count("```") % 2:
        errors.append(f"{path}: unbalanced fenced code block")

    links = [match.group(1) for match in link_pattern.finditer(text)]
    links.extend(match.group(1) for match in reference_pattern.finditer(text))

    for match in html_image_pattern.finditer(text):
        tag = match.group(0)
        src_match = html_src_pattern.search(tag)
        if src_match is None:
            errors.append(f"{path}: HTML image is missing src")
            continue
        src = src_match.group(1)
        links.append(src)
        if "gridguard-" in src and src.endswith(".svg"):
            if responsive_width_pattern.search(tag) is None:
                errors.append(
                    f'{path}: architecture image must declare width="100%"'
                )

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

diagram_dir = root / "docs" / "assets"
diagram_files = sorted(diagram_dir.glob("*.svg"))
required_diagrams = {
    "gridguard-architecture.svg",
    "gridguard-aws-deployment.svg",
    "gridguard-detection-flow.svg",
}
missing_diagrams = required_diagrams - {path.name for path in diagram_files}
for name in sorted(missing_diagrams):
    errors.append(f"docs/assets/{name}: required architecture diagram is missing")

svg_namespace = "http://www.w3.org/2000/svg"
for path in diagram_files:
    display_path = path.relative_to(root)
    try:
        svg = ET.parse(path).getroot()
    except ET.ParseError as exc:
        errors.append(f"{display_path}: invalid XML: {exc}")
        continue

    if svg.tag != f"{{{svg_namespace}}}svg":
        errors.append(f"{display_path}: root element is not an SVG")
        continue

    if svg.get("role") != "img":
        errors.append(f'{display_path}: root must declare role="img"')

    children = list(svg)
    if len(children) < 2:
        errors.append(f"{display_path}: missing title and description")
    else:
        title, description = children[0], children[1]
        if title.tag != f"{{{svg_namespace}}}title" or not (title.text or "").strip():
            errors.append(f"{display_path}: first child must be a non-empty title")
        if (
            description.tag != f"{{{svg_namespace}}}desc"
            or not (description.text or "").strip()
        ):
            errors.append(f"{display_path}: second child must be a non-empty desc")

    ids = [element_id for element in svg.iter() if (element_id := element.get("id"))]
    if len(ids) != len(set(ids)):
        errors.append(f"{display_path}: duplicate element IDs")

    labelled_by = (svg.get("aria-labelledby") or "").split()
    if len(labelled_by) != 2 or any(element_id not in ids for element_id in labelled_by):
        errors.append(
            f"{display_path}: aria-labelledby must resolve to the title and desc IDs"
        )

    view_box = (svg.get("viewBox") or "").split()
    try:
        _, _, view_width, view_height = [float(value) for value in view_box]
    except (TypeError, ValueError):
        errors.append(f"{display_path}: viewBox must contain four numeric values")
    else:
        if view_width <= 0 or view_height <= 0:
            errors.append(f"{display_path}: viewBox dimensions must be positive")
        if svg.get("width") != "100%" or svg.get("height") != "auto":
            errors.append(
                f'{display_path}: root must declare width="100%" and height="auto"'
            )
        if svg.get("preserveAspectRatio") != "xMidYMid meet":
            errors.append(f"{display_path}: root must preserve its centered aspect ratio")

    if svg.find(f".//{{{svg_namespace}}}foreignObject") is not None:
        errors.append(f"{display_path}: foreignObject is not portable")

    for image in svg.findall(f".//{{{svg_namespace}}}image"):
        href = image.get("href") or image.get(
            "{http://www.w3.org/1999/xlink}href", ""
        )
        prefix = "data:image/svg+xml;base64,"
        if not href.startswith(prefix):
            errors.append(f"{display_path}: image asset is not embedded")
            continue
        try:
            embedded = base64.b64decode(href.removeprefix(prefix), validate=True)
            ET.fromstring(embedded)
        except (binascii.Error, ET.ParseError) as exc:
            errors.append(f"{display_path}: invalid embedded SVG image: {exc}")

if errors:
    for error in errors:
        print(f"::error::{error}")
    sys.exit(1)

print(
    f"Validated {len(markdown_files)} Markdown files and "
    f"{len(diagram_files)} architecture diagrams."
)
PY
