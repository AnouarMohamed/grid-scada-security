from __future__ import annotations

from enum import StrEnum


class Scenario(StrEnum):
    BASELINE = "baseline-modbus"
    NAIVE = "naive-bad-value"
    STEALTHY = "stealthy-fdia"


def apply_scenario(values: dict[str, float], scenario: Scenario) -> dict[str, float]:
    attacked = dict(values)
    if scenario is Scenario.NAIVE:
        attacked["bus_650_a_voltage"] = 0.88
        attacked["bus_632_a_current"] *= 1.45
    elif scenario is Scenario.STEALTHY:
        for name in ("bus_650_a_voltage", "bus_650_b_voltage", "bus_650_c_voltage"):
            attacked[name] += 0.012
        for name in ("bus_632_a_current", "bus_632_b_current", "bus_632_c_current"):
            attacked[name] *= 1.04
        attacked["bus_671_total_real_power"] *= 1.04
        attacked["bus_671_total_reactive_power"] *= 1.04
    return {name: round(value, 5) for name, value in attacked.items()}


def is_attack(scenario: Scenario) -> bool:
    return scenario is not Scenario.BASELINE
