from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def load_register_contract(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload.get("registers"), list):
        raise ValueError("register contract must define a registers list")
    return payload


def encode_registers(contract: dict[str, Any], telemetry: dict[str, float]) -> dict[int, int]:
    encoded: dict[int, int] = {}
    for register in contract["registers"]:
        name = str(register["name"])
        if name not in telemetry:
            raise ValueError(f"telemetry is missing contract value {name}")
        scale = float(register["scale"])
        offset = float(register.get("offset", 0.0))
        raw = round((telemetry[name] - offset) / scale)
        if register["data_type"] == "int16":
            if raw < -32768 or raw > 32767:
                raise ValueError(f"{name} is outside int16 range after scaling")
            raw &= 0xFFFF
        elif raw < 0 or raw > 0xFFFF:
            raise ValueError(f"{name} is outside uint16 range after scaling")
        encoded[int(register["address"])] = raw
    return encoded
