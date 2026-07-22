from __future__ import annotations

import time

from gridguard_modbus_ingestor.clients import RegisterClient
from gridguard_modbus_ingestor.contract import RegisterMap, required_ranges


def current_timestamp_ns() -> int:
    return time.time_ns()


def read_register_values(
    *,
    register_map: RegisterMap,
    client: RegisterClient,
    unit_id: int | None = None,
) -> dict[int, int]:
    effective_unit_id = unit_id if unit_id is not None else register_map.unit_id
    values: dict[int, int] = {}
    for start, count in required_ranges(register_map.registers):
        response = client.read_holding_registers(
            start=start,
            count=count,
            unit_id=effective_unit_id,
        )
        if len(response) != count:
            raise ValueError(f"expected {count} register(s) from {start}, got {len(response)}")
        values.update({start + index: value for index, value in enumerate(response)})
    return values


def telemetry_points(
    *,
    register_map: RegisterMap,
    register_values: dict[int, int],
    source_id: str,
    timestamp_ns: int | None = None,
) -> list[dict[str, object]]:
    sample_time_ns = timestamp_ns if timestamp_ns is not None else current_timestamp_ns()
    points: list[dict[str, object]] = []

    for register in register_map.registers:
        raw_registers = [
            register_values[address]
            for address in range(register.address, register.address + register.count)
        ]
        points.append(
            {
                "measurement": "grid_telemetry",
                "tags": {
                    "feeder": register_map.feeder,
                    "bus": register.bus,
                    "phase": register.phase,
                    "scenario": register_map.scenario,
                    "signal": register.signal,
                    "source": source_id,
                },
                "fields": {
                    "value": register.decode(raw_registers),
                    "quality": register.quality,
                    "attack_flag": register.attack_flag,
                },
                "timestamp_ns": sample_time_ns,
            }
        )

    return points
