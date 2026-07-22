from __future__ import annotations

from pathlib import Path

from gridguard_modbus_ingestor.clients import FixtureRegisterClient
from gridguard_modbus_ingestor.contract import load_register_map
from gridguard_modbus_ingestor.influx import line_protocol
from gridguard_modbus_ingestor.pipeline import read_register_values, telemetry_points

ROOT = Path(__file__).resolve().parents[3]
REGISTER_MAP = ROOT / "contracts/register-maps/ieee13-demo.json"
FIXTURE = ROOT / "contracts/register-maps/fixtures/ieee13-baseline-registers.json"


class RecordingClient(FixtureRegisterClient):
    def __init__(self) -> None:
        super().__init__(
            {
                0: 10112,
                1: 10086,
                2: 10093,
                10: 7214,
                11: 7188,
                12: 7242,
                20: 60002,
                30: 1842,
                31: 613,
            }
        )
        self.unit_ids: list[int] = []

    def read_holding_registers(self, *, start: int, count: int, unit_id: int) -> list[int]:
        self.unit_ids.append(unit_id)
        return super().read_holding_registers(start=start, count=count, unit_id=unit_id)


def test_fixture_registers_become_grid_telemetry_points() -> None:
    register_map = load_register_map(REGISTER_MAP)
    client = FixtureRegisterClient.from_file(FIXTURE)

    values = read_register_values(register_map=register_map, client=client)
    points = telemetry_points(
        register_map=register_map,
        register_values=values,
        source_id="modbus_fixture",
        timestamp_ns=1_700_000_000_000_000_000,
    )

    assert len(points) == len(register_map.registers)
    assert points[0]["measurement"] == "grid_telemetry"
    assert points[0]["tags"] == {
        "feeder": "ieee-13-demo",
        "bus": "650",
        "phase": "A",
        "scenario": "baseline-modbus",
        "signal": "voltage_pu",
        "source": "modbus_fixture",
    }
    assert points[0]["fields"] == {"value": 1.0112, "quality": 1, "attack_flag": 0}


def test_read_register_values_honors_unit_id_override() -> None:
    register_map = load_register_map(REGISTER_MAP)
    client = RecordingClient()

    read_register_values(register_map=register_map, client=client, unit_id=7)

    assert client.unit_ids == [7, 7, 7, 7]


def test_modbus_points_encode_to_influx_line_protocol() -> None:
    register_map = load_register_map(REGISTER_MAP)
    client = FixtureRegisterClient.from_file(FIXTURE)
    values = read_register_values(register_map=register_map, client=client)
    points = telemetry_points(
        register_map=register_map,
        register_values=values,
        source_id="modbus_fixture",
        timestamp_ns=1_700_000_000_000_000_000,
    )

    payload = line_protocol(points)
    first_line = payload.splitlines()[0]

    assert first_line.startswith("grid_telemetry,")
    assert "source=modbus_fixture" in first_line
    assert "signal=voltage_pu" in first_line
    assert "value=1.0112" in first_line
    assert "quality=1i" in first_line
    assert first_line.endswith(" 1700000000000000000")
