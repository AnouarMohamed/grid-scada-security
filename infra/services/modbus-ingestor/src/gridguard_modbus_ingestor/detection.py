from __future__ import annotations


def detection_points(
    telemetry: list[dict[str, object]],
) -> list[dict[str, object]]:
    detections: list[dict[str, object]] = []
    for point in telemetry:
        tags = dict(point["tags"])
        fields = dict(point["fields"])
        signal = str(tags["signal"])
        value = float(fields["value"])
        timestamp_ns = int(point["timestamp_ns"])

        if signal == "voltage_pu" and (value < 0.95 or value > 1.05):
            threshold = 0.95 if value < 0.95 else 1.05
            detections.append(
                _detection_point(
                    tags=tags,
                    timestamp_ns=timestamp_ns,
                    detector="voltage-envelope",
                    severity="critical",
                    score=value,
                    threshold=threshold,
                    message=f"voltage {value:.4f} pu is outside the 0.95-1.05 envelope",
                )
            )

        if int(fields.get("attack_flag", 0)) == 1:
            detections.append(
                _detection_point(
                    tags=tags,
                    timestamp_ns=timestamp_ns,
                    detector="attack-flag-forwarder",
                    severity="warning",
                    score=1.0,
                    threshold=1.0,
                    message="upstream scenario ground-truth flag is active",
                )
            )
    return detections


def _detection_point(
    *,
    tags: dict[str, object],
    timestamp_ns: int,
    detector: str,
    severity: str,
    score: float,
    threshold: float,
    message: str,
) -> dict[str, object]:
    return {
        "measurement": "grid_detection",
        "tags": {
            "detector": detector,
            "severity": severity,
            "source": tags["source"],
            "scenario": tags["scenario"],
            "feeder": tags["feeder"],
            "signal": tags["signal"],
            "bus": tags["bus"],
            "phase": tags["phase"],
        },
        "fields": {
            "score": score,
            "threshold": threshold,
            "alert_flag": 1,
            "message": message,
        },
        "timestamp_ns": timestamp_ns,
    }
