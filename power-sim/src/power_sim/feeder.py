from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class FeederSnapshot:
    voltage_pu: float
    load_kw: float
    power_kw: float
    hour: int


@dataclass
class FeederModel:
    base_load_kw: float = 450.0
    solar_kw: float = 60.0

    def voltage_for_hour(self, hour: int) -> float:
        base = 1.0 - 0.002 * max(0, hour - 12)
        solar_boost = 0.004 * max(0, 12 - abs(hour - 12))
        return round(max(0.96, min(1.02, base + solar_boost)), 3)


def simulate_timestep(model: FeederModel, hour: int) -> FeederSnapshot:
    voltage_pu = model.voltage_for_hour(hour)
    load_kw = max(50.0, model.base_load_kw - (hour - 12) * 12.0)
    power_kw = max(0.0, load_kw + model.solar_kw)
    return FeederSnapshot(
        voltage_pu=voltage_pu,
        load_kw=round(load_kw, 2),
        power_kw=round(power_kw, 2),
        hour=hour,
    )


def build_register_map() -> dict[str, dict[str, object]]:
    return {
        "bus_voltage": {
            "name": "bus_voltage",
            "scale": 1000,
            "unit": "V",
            "description": "Bus voltage in per-unit and scaled to volts",
        },
        "load_kw": {
            "name": "load_kw",
            "scale": 1,
            "unit": "kW",
            "description": "Load estimate",
        },
    }
