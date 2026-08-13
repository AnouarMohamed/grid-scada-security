from __future__ import annotations


class BaselineDetector:
    def __init__(self, threshold: float = 0.1) -> None:
        self.threshold = threshold

    def evaluate(self, register: str, expected: float, observed: float) -> bool:
        if register != "bus_voltage":
            return False
        deviation = abs(expected - observed)
        return deviation >= self.threshold
