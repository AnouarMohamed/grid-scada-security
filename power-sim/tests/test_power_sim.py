from pathlib import Path

import pytest
from power_sim.attacks import Scenario, apply_scenario
from power_sim.detector import BaselineDetector
from power_sim.feeder import (
    BUS_NAMES,
    FeederModel,
    build_register_map,
    simulate_day,
    simulate_timestep,
)
from power_sim.registers import encode_registers, load_register_contract
from power_sim.server import ServerConfig, TelemetryState

ROOT = Path(__file__).resolve().parents[2]
REGISTER_MAP = ROOT / "infra/contracts/register-maps/ieee13-demo.json"


@pytest.fixture(scope="module")
def feeder() -> FeederModel:
    return FeederModel()


def test_ieee13_model_converges_with_expected_topology(feeder: FeederModel) -> None:
    snapshot = simulate_timestep(feeder, hour=18)

    assert snapshot.converged is True
    assert set(feeder.net.bus.name) == set(BUS_NAMES)
    assert len(feeder.net.bus) == 13
    assert len(feeder.net.trafo) == 1
    assert 0.95 < min(feeder.net.res_bus.vm_pu) < 1.05


def test_day_profile_varies_load_and_pv(feeder: FeederModel) -> None:
    snapshots = simulate_day(feeder)

    assert len(snapshots) == 24
    assert all(snapshot.converged for snapshot in snapshots)
    assert snapshots[12].solar_kw > snapshots[8].solar_kw > snapshots[0].solar_kw
    assert snapshots[18].load_kw > snapshots[3].load_kw
    assert snapshots[12].power_kw < snapshots[18].power_kw


def test_register_map_contains_expected_telemetry_fields() -> None:
    registers = build_register_map()

    assert "bus_voltage" in registers
    assert registers["bus_voltage"]["scale"] == 10000
    assert registers["bus_voltage"]["unit"] == "pu"


def test_scenarios_are_deterministic_and_distinct(feeder: FeederModel) -> None:
    baseline = simulate_timestep(feeder, hour=12).telemetry
    naive = apply_scenario(baseline, Scenario.NAIVE)
    stealthy = apply_scenario(baseline, Scenario.STEALTHY)

    assert naive["bus_650_a_voltage"] == 0.88
    assert stealthy["bus_650_a_voltage"] > baseline["bus_650_a_voltage"]
    assert stealthy["bus_650_a_voltage"] < 1.05
    assert apply_scenario(baseline, Scenario.NAIVE) == naive


def test_snapshot_encodes_against_shared_register_contract(feeder: FeederModel) -> None:
    contract = load_register_contract(REGISTER_MAP)
    snapshot = simulate_timestep(feeder, hour=12)

    encoded = encode_registers(contract, snapshot.telemetry)

    assert set(encoded) == {0, 1, 2, 10, 11, 12, 20, 30, 31}
    assert encoded[0] == round(snapshot.telemetry["bus_650_a_voltage"] / 0.0001)


def test_telemetry_state_advances_operating_point() -> None:
    config = ServerConfig(
        host="127.0.0.1",
        port=1502,
        unit_id=1,
        interval_seconds=0.01,
        start_hour=12,
        scenario=Scenario.BASELINE,
        register_map=REGISTER_MAP,
    )
    state = TelemetryState(config)

    first = state.refresh()
    second = state.refresh(force=True)

    assert first != second


def test_detector_flags_obvious_bad_value() -> None:
    detector = BaselineDetector(threshold=0.12)

    assert detector.evaluate("bus_voltage", 1.0, 0.85) is True
    assert detector.evaluate("bus_voltage", 1.0, 0.995) is False
