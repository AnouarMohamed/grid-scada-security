from gridguard_modbus_ingestor.detection import detection_points


def _telemetry(*, value: float, attack_flag: int = 0) -> dict[str, object]:
    return {
        "measurement": "grid_telemetry",
        "tags": {
            "feeder": "ieee-13-demo",
            "bus": "650",
            "phase": "A",
            "scenario": "naive-bad-value",
            "signal": "voltage_pu",
            "source": "modbus_tcp",
        },
        "fields": {"value": value, "quality": 1, "attack_flag": attack_flag},
        "timestamp_ns": 1_700_000_000_000_000_000,
    }


def test_voltage_envelope_emits_detection_contract() -> None:
    detections = detection_points([_telemetry(value=0.88)])

    assert len(detections) == 1
    assert detections[0]["measurement"] == "grid_detection"
    assert detections[0]["tags"]["detector"] == "voltage-envelope"
    assert detections[0]["fields"]["alert_flag"] == 1
    assert detections[0]["fields"]["threshold"] == 0.95


def test_attack_flag_is_forwarded_independently_of_envelope() -> None:
    detections = detection_points([_telemetry(value=1.01, attack_flag=1)])

    assert len(detections) == 1
    assert detections[0]["tags"]["detector"] == "attack-flag-forwarder"


def test_baseline_telemetry_stays_quiet() -> None:
    assert detection_points([_telemetry(value=1.01)]) == []
