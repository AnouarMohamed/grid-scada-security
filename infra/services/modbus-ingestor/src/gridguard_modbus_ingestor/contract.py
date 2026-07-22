from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SUPPORTED_DATA_TYPES = {"uint16", "int16"}
SUPPORTED_FUNCTIONS = {"holding_register"}


@dataclass(frozen=True)
class RegisterDefinition:
    name: str
    address: int
    reference: str
    function: str
    data_type: str
    scale: float
    offset: float
    unit: str
    bus: str
    phase: str
    signal: str
    quality: int
    attack_flag: int

    @property
    def count(self) -> int:
        return 1

    def decode(self, registers: list[int]) -> float:
        if len(registers) != self.count:
            raise ValueError(
                f"{self.name} expects {self.count} register(s), got {len(registers)}"
            )

        raw_value = registers[0]
        if raw_value < 0 or raw_value > 0xFFFF:
            raise ValueError(f"{self.name} register value must fit uint16, got {raw_value}")

        if self.data_type == "int16" and raw_value >= 0x8000:
            raw_value -= 0x10000

        return round((raw_value * self.scale) + self.offset, 6)


@dataclass(frozen=True)
class RegisterMap:
    schema_version: int
    name: str
    description: str
    feeder: str
    scenario: str
    unit_id: int
    addressing: str
    byte_order: str
    word_order: str
    registers: tuple[RegisterDefinition, ...]


def load_register_map(path: Path) -> RegisterMap:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return parse_register_map(payload)


def parse_register_map(payload: dict[str, Any]) -> RegisterMap:
    schema_version = _int(payload, "schema_version")
    if schema_version != 1:
        raise ValueError(f"Unsupported register-map schema_version {schema_version!r}")

    register_map = RegisterMap(
        schema_version=schema_version,
        name=_str(payload, "name"),
        description=_str(payload, "description"),
        feeder=_str(payload, "feeder"),
        scenario=_str(payload, "scenario"),
        unit_id=_bounded_int(payload, "unit_id", 1, 247),
        addressing=_str(payload, "addressing"),
        byte_order=_str(payload, "byte_order"),
        word_order=_str(payload, "word_order"),
        registers=tuple(_parse_register(item) for item in _list(payload, "registers")),
    )

    _validate_register_map(register_map)
    return register_map


def required_ranges(registers: tuple[RegisterDefinition, ...]) -> list[tuple[int, int]]:
    addresses = sorted({register.address for register in registers})
    if not addresses:
        return []

    ranges: list[tuple[int, int]] = []
    start = previous = addresses[0]

    for address in addresses[1:]:
        if address == previous + 1:
            previous = address
            continue

        ranges.append((start, previous - start + 1))
        start = previous = address

    ranges.append((start, previous - start + 1))
    return ranges


def _parse_register(payload: dict[str, Any]) -> RegisterDefinition:
    register = RegisterDefinition(
        name=_str(payload, "name"),
        address=_bounded_int(payload, "address", 0, 65535),
        reference=_str(payload, "reference"),
        function=_str(payload, "function"),
        data_type=_str(payload, "data_type"),
        scale=_float(payload, "scale"),
        offset=_float(payload, "offset"),
        unit=_str(payload, "unit"),
        bus=_str(payload, "bus"),
        phase=_str(payload, "phase"),
        signal=_str(payload, "signal"),
        quality=_bounded_int(payload, "quality", 0, 1),
        attack_flag=_bounded_int(payload, "attack_flag", 0, 1),
    )

    if register.function not in SUPPORTED_FUNCTIONS:
        raise ValueError(f"{register.name} uses unsupported function {register.function!r}")
    if register.data_type not in SUPPORTED_DATA_TYPES:
        raise ValueError(f"{register.name} uses unsupported data_type {register.data_type!r}")
    if register.scale == 0:
        raise ValueError(f"{register.name} scale must not be zero")

    return register


def _validate_register_map(register_map: RegisterMap) -> None:
    if register_map.addressing != "zero_based_pdu":
        raise ValueError("addressing must be zero_based_pdu")
    if register_map.byte_order != "big":
        raise ValueError("byte_order must be big")
    if register_map.word_order != "big":
        raise ValueError("word_order must be big")
    if not register_map.registers:
        raise ValueError("register map must contain at least one register")

    names = [register.name for register in register_map.registers]
    if len(names) != len(set(names)):
        raise ValueError("register names must be unique")

    telemetry_keys = [
        (register.bus, register.phase, register.signal) for register in register_map.registers
    ]
    if len(telemetry_keys) != len(set(telemetry_keys)):
        raise ValueError("bus, phase, and signal combinations must be unique")


def _str(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} must be a non-empty string")
    return value


def _int(payload: dict[str, Any], key: str) -> int:
    value = payload.get(key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{key} must be an integer")
    return value


def _bounded_int(payload: dict[str, Any], key: str, minimum: int, maximum: int) -> int:
    value = _int(payload, key)
    if value < minimum or value > maximum:
        raise ValueError(f"{key} must be between {minimum} and {maximum}")
    return value


def _float(payload: dict[str, Any], key: str) -> float:
    value = payload.get(key)
    if not isinstance(value, int | float) or isinstance(value, bool):
        raise ValueError(f"{key} must be numeric")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{key} must be finite")
    return number


def _list(payload: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = payload.get(key)
    if not isinstance(value, list):
        raise ValueError(f"{key} must be a list")
    if not all(isinstance(item, dict) for item in value):
        raise ValueError(f"{key} must contain objects")
    return value
