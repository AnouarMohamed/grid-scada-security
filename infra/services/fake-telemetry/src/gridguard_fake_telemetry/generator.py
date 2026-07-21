from __future__ import annotations

import math
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

BUSES: tuple[str, ...] = (
    "650",
    "632",
    "633",
    "634",
    "645",
    "646",
    "671",
    "680",
    "684",
    "611",
    "652",
    "692",
    "675",
)

PHASES: tuple[str, ...] = ("A", "B", "C")


@dataclass(frozen=True)
class TelemetryPoint:
    measurement: str
    tags: dict[str, str]
    fields: dict[str, float | int]
    timestamp_ns: int

    def as_dict(self) -> dict[str, Any]:
        return {
            "measurement": self.measurement,
            "tags": self.tags,
            "fields": self.fields,
            "timestamp_ns": self.timestamp_ns,
        }


def current_timestamp_ns() -> int:
    return time.time_ns()


def _daily_load_shape(timestamp_ns: int) -> float:
    seconds = (timestamp_ns / 1_000_000_000) % 86_400
    hour = seconds / 3_600
    morning_ramp = 0.12 * math.sin((hour - 7.0) / 24.0 * 2.0 * math.pi)
    evening_peak = 0.18 * math.sin((hour - 17.0) / 24.0 * 2.0 * math.pi)
    return min(max(0.74 + morning_ramp + evening_peak, 0.48), 1.08)


def _pv_shape(timestamp_ns: int) -> float:
    seconds = (timestamp_ns / 1_000_000_000) % 86_400
    hour = seconds / 3_600
    if hour < 6.0 or hour > 18.5:
        return 0.0
    return math.sin((hour - 6.0) / 12.5 * math.pi) ** 1.7


def _phase_offset(phase: str) -> float:
    return {"A": 0.0025, "B": -0.0015, "C": -0.001}.get(phase, 0.0)


def _ripple(timestamp_ns: int, bus_index: int, phase_index: int) -> float:
    seconds = timestamp_ns / 1_000_000_000
    return 0.0015 * math.sin(seconds / 37.0 + bus_index * 0.71 + phase_index)


def _clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def generate_snapshot(
    *,
    feeder_id: str,
    scenario: str,
    timestamp_ns: int | None = None,
) -> dict[str, Any]:
    sample_time_ns = timestamp_ns if timestamp_ns is not None else current_timestamp_ns()
    sample_time = datetime.fromtimestamp(sample_time_ns / 1_000_000_000, UTC)
    load_shape = _daily_load_shape(sample_time_ns)
    pv_shape = _pv_shape(sample_time_ns)
    points: list[TelemetryPoint] = []

    for bus_index, bus in enumerate(BUSES):
        distance_drop = bus_index * 0.0019
        bus_load_factor = 0.86 + bus_index * 0.025

        for phase_index, phase in enumerate(PHASES):
            phase_multiplier = 1.0 + (phase_index - 1) * 0.018
            ripple = _ripple(sample_time_ns, bus_index, phase_index)
            voltage_pu = _clamp(
                1.017
                - distance_drop
                - (0.028 * load_shape * bus_load_factor)
                + (0.018 * pv_shape)
                + _phase_offset(phase)
                + ripple,
                0.934,
                1.052,
            )
            real_power_kw = (
                42.0 * bus_load_factor * phase_multiplier * load_shape
                - 18.0 * pv_shape * max(0.2, 1.0 - bus_index / len(BUSES))
            )
            reactive_power_kvar = max(real_power_kw * 0.32, 1.0)
            current_a = max(real_power_kw * 1.65 / max(voltage_pu, 0.92), 0.1)
            frequency_hz = 60.0 + 0.018 * math.sin(sample_time_ns / 1_000_000_000 / 53.0)

            common_tags = {
                "feeder": feeder_id,
                "bus": bus,
                "phase": phase,
                "scenario": scenario,
                "source": "synthetic",
            }

            signals = {
                "voltage_pu": voltage_pu,
                "current_a": current_a,
                "real_power_kw": real_power_kw,
                "reactive_power_kvar": reactive_power_kvar,
                "frequency_hz": frequency_hz,
            }

            for signal, value in signals.items():
                points.append(
                    TelemetryPoint(
                        measurement="grid_telemetry",
                        tags={**common_tags, "signal": signal},
                        fields={
                            "value": round(value, 6),
                            "quality": 1,
                            "attack_flag": 0,
                        },
                        timestamp_ns=sample_time_ns,
                    )
                )

    return {
        "snapshot_id": f"{feeder_id}-{sample_time_ns}",
        "timestamp": sample_time.isoformat(),
        "timestamp_ns": sample_time_ns,
        "feeder_id": feeder_id,
        "scenario": scenario,
        "point_count": len(points),
        "points": [point.as_dict() for point in points],
    }
