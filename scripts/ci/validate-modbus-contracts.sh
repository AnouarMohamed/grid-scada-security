#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

export PYTHONPATH="${ROOT_DIR}/infra/services/modbus-ingestor/src${PYTHONPATH:+:${PYTHONPATH}}"

python3 - <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

from gridguard_modbus_ingestor.clients import FixtureRegisterClient
from gridguard_modbus_ingestor.contract import load_register_map
from gridguard_modbus_ingestor.pipeline import read_register_values

root = Path.cwd()
contract_dir = root / "infra/contracts/register-maps"
fixture_dir = contract_dir / "fixtures"

map_paths = sorted(path for path in contract_dir.glob("*.json") if path.is_file())
fixture_paths = sorted(path for path in fixture_dir.glob("*.json") if path.is_file())
errors: list[str] = []

if not map_paths:
    errors.append("no register-map JSON files found")

for path in map_paths:
    try:
        register_map = load_register_map(path)
    except Exception as exc:
        errors.append(f"{path}: {exc}")
        continue

    print(
        "register-map ok: "
        f"path={path} name={register_map.name} "
        f"unit_id={register_map.unit_id} registers={len(register_map.registers)}"
    )

for path in fixture_paths:
    try:
        client = FixtureRegisterClient.from_file(path)
    except Exception as exc:
        errors.append(f"{path}: {exc}")
        continue

    print(f"register-fixture ok: path={path} registers={len(client.values)}")

default_map_path = contract_dir / "ieee13-demo.json"
default_fixture_path = fixture_dir / "ieee13-baseline-registers.json"
if default_map_path.exists() and default_fixture_path.exists():
    try:
        default_map = load_register_map(default_map_path)
        default_client = FixtureRegisterClient.from_file(default_fixture_path)
        values = read_register_values(register_map=default_map, client=default_client)
    except Exception as exc:
        errors.append(f"default Modbus fixture path failed: {exc}")
    else:
        print(
            "register-fixture coverage ok: "
            f"map={default_map_path} fixture={default_fixture_path} "
            f"values={len(values)}"
        )

if errors:
    for error in errors:
        print(f"::error::{error}")
    sys.exit(1)

print("Modbus contract validation passed.")
PY
