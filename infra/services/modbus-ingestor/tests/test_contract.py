from __future__ import annotations

from pathlib import Path

import pytest
from gridguard_modbus_ingestor.contract import (
    load_register_map,
    parse_register_map,
    required_ranges,
)

ROOT = Path(__file__).resolve().parents[3]
REGISTER_MAP = ROOT / "contracts/register-maps/ieee13-demo.json"


def test_load_register_map_contract() -> None:
    register_map = load_register_map(REGISTER_MAP)

    assert register_map.name == "ieee13-demo"
    assert register_map.feeder == "ieee-13-demo"
    assert register_map.unit_id == 1
    assert len(register_map.registers) == 9


def test_required_ranges_groups_contiguous_addresses() -> None:
    register_map = load_register_map(REGISTER_MAP)

    assert required_ranges(register_map.registers) == [(0, 3), (10, 3), (20, 1), (30, 2)]


def test_register_decode_applies_signed_scaling() -> None:
    register_map = load_register_map(REGISTER_MAP)
    real_power = next(
        register
        for register in register_map.registers
        if register.name == "bus_671_total_real_power"
    )

    assert real_power.decode([0xFFF6]) == -1.0


def test_register_map_rejects_duplicate_telemetry_keys() -> None:
    payload = {
        "schema_version": 1,
        "name": "bad-map",
        "description": "bad",
        "feeder": "test",
        "scenario": "test",
        "unit_id": 1,
        "addressing": "zero_based_pdu",
        "byte_order": "big",
        "word_order": "big",
        "registers": [
            {
                "name": "a",
                "address": 0,
                "reference": "40001",
                "function": "holding_register",
                "data_type": "uint16",
                "scale": 1,
                "offset": 0,
                "unit": "pu",
                "bus": "650",
                "phase": "A",
                "signal": "voltage_pu",
                "quality": 1,
                "attack_flag": 0,
            },
            {
                "name": "b",
                "address": 1,
                "reference": "40002",
                "function": "holding_register",
                "data_type": "uint16",
                "scale": 1,
                "offset": 0,
                "unit": "pu",
                "bus": "650",
                "phase": "A",
                "signal": "voltage_pu",
                "quality": 1,
                "attack_flag": 0,
            },
        ],
    }

    with pytest.raises(ValueError, match="bus, phase, and signal"):
        parse_register_map(payload)


def test_register_map_rejects_boolean_numeric_fields() -> None:
    payload = {
        "schema_version": 1,
        "name": "bad-map",
        "description": "bad",
        "feeder": "test",
        "scenario": "test",
        "unit_id": True,
        "addressing": "zero_based_pdu",
        "byte_order": "big",
        "word_order": "big",
        "registers": [],
    }

    with pytest.raises(ValueError, match="unit_id must be an integer"):
        parse_register_map(payload)
