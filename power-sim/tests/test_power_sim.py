from power_sim.detector import BaselineDetector
from power_sim.feeder import FeederModel, build_register_map, simulate_timestep


def test_simulate_timestep_returns_physical_voltage_and_power():
    feeder = FeederModel(base_load_kw=450.0, solar_kw=60.0)

    snapshot = simulate_timestep(feeder, hour=6)

    assert snapshot.voltage_pu > 0.95
    assert snapshot.voltage_pu < 1.05
    assert snapshot.power_kw > 0
    assert snapshot.load_kw > 0


def test_register_map_contains_expected_telemetry_fields():
    registers = build_register_map()

    assert "bus_voltage" in registers
    assert registers["bus_voltage"]["scale"] == 1000
    assert registers["bus_voltage"]["unit"] == "V"


def test_detector_flags_obvious_bad_value():
    detector = BaselineDetector(threshold=0.12)

    assert detector.evaluate("bus_voltage", 1.0, 0.85) is True
    assert detector.evaluate("bus_voltage", 1.0, 0.995) is False
