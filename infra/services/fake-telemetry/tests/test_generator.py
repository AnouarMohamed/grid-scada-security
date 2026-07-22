from __future__ import annotations

from gridguard_fake_telemetry.generator import BUSES, PHASES, generate_snapshot
from gridguard_fake_telemetry.influx import snapshot_to_line_protocol


def test_snapshot_has_expected_shape() -> None:
    snapshot = generate_snapshot(
        feeder_id="test-feeder",
        scenario="unit-test",
        timestamp_ns=1_700_000_000_000_000_000,
    )

    assert snapshot["feeder_id"] == "test-feeder"
    assert snapshot["scenario"] == "unit-test"
    assert snapshot["point_count"] == len(BUSES) * len(PHASES) * 5
    assert len(snapshot["points"]) == snapshot["point_count"]


def test_voltage_values_stay_in_operational_range() -> None:
    snapshot = generate_snapshot(
        feeder_id="test-feeder",
        scenario="unit-test",
        timestamp_ns=1_700_000_000_000_000_000,
    )

    voltages = [
        point["fields"]["value"]
        for point in snapshot["points"]
        if point["tags"]["signal"] == "voltage_pu"
    ]

    assert voltages
    assert min(voltages) >= 0.934
    assert max(voltages) <= 1.052


def test_snapshot_generation_is_deterministic_for_timestamp() -> None:
    first = generate_snapshot(
        feeder_id="test-feeder",
        scenario="unit-test",
        timestamp_ns=1_700_000_000_000_000_000,
    )
    second = generate_snapshot(
        feeder_id="test-feeder",
        scenario="unit-test",
        timestamp_ns=1_700_000_000_000_000_000,
    )

    assert first == second


def test_line_protocol_contains_tags_fields_and_timestamp() -> None:
    snapshot = generate_snapshot(
        feeder_id="test feeder",
        scenario="unit test",
        timestamp_ns=1_700_000_000_000_000_000,
    )

    line_protocol = snapshot_to_line_protocol(snapshot)
    first_line = line_protocol.splitlines()[0]

    assert first_line.startswith("grid_telemetry,")
    assert "feeder=test\\ feeder" in first_line
    assert "scenario=unit\\ test" in first_line
    assert "value=" in first_line
    assert "quality=1i" in first_line
    assert first_line.endswith(" 1700000000000000000")


def test_line_protocol_strips_line_breaks_from_tag_values() -> None:
    snapshot = generate_snapshot(
        feeder_id="test\nfeeder",
        scenario="unit\rtest",
        timestamp_ns=1_700_000_000_000_000_000,
    )

    line_protocol = snapshot_to_line_protocol(snapshot)

    assert line_protocol.count("\n") == snapshot["point_count"] - 1
    assert "feeder=test\\ feeder" in line_protocol
    assert "scenario=unit\\ test" in line_protocol
