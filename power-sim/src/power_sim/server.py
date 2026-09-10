from __future__ import annotations

import logging
import os
import socket
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from power_sim.attacks import Scenario, apply_scenario
from power_sim.feeder import FeederModel, simulate_timestep
from power_sim.registers import encode_registers, load_register_contract
from pymodbus.server import StartTcpServer
from pymodbus.simulator import DataType, SimData, SimDevice

LOGGER = logging.getLogger("gridguard.power_sim")


def _positive_float(name: str, default: float) -> float:
    value = float(os.getenv(name, str(default)))
    if value <= 0:
        raise ValueError(f"{name} must be greater than zero")
    return value


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    unit_id: int
    interval_seconds: float
    start_hour: int
    scenario: Scenario
    register_map: Path

    @classmethod
    def from_env(cls) -> ServerConfig:
        port = int(os.getenv("GRIDGUARD_MODBUS_PORT", "502"))
        unit_id = int(os.getenv("GRIDGUARD_MODBUS_UNIT_ID", "1"))
        start_hour = int(os.getenv("GRIDGUARD_SIM_START_HOUR", "0"))
        if not 1 <= port <= 65535:
            raise ValueError("GRIDGUARD_MODBUS_PORT must be between 1 and 65535")
        if not 1 <= unit_id <= 247:
            raise ValueError("GRIDGUARD_MODBUS_UNIT_ID must be between 1 and 247")
        return cls(
            host=os.getenv("GRIDGUARD_MODBUS_HOST", "0.0.0.0"),  # nosec B104
            port=port,
            unit_id=unit_id,
            interval_seconds=_positive_float("GRIDGUARD_SIM_INTERVAL_SECONDS", 2.0),
            start_hour=start_hour % 24,
            scenario=Scenario(os.getenv("GRIDGUARD_SCENARIO", Scenario.BASELINE.value)),
            register_map=Path(
                os.getenv("GRIDGUARD_REGISTER_MAP", "/etc/gridguard/register-map.json")
            ),
        )


class TelemetryState:
    def __init__(self, config: ServerConfig) -> None:
        self.config = config
        self.contract = load_register_contract(config.register_map)
        self.model = FeederModel()
        self._lock = threading.Lock()
        self._last_step = 0.0
        self._step = 0
        self._registers: dict[int, int] = {}
        self.refresh(force=True)

    def refresh(self, *, force: bool = False) -> dict[int, int]:
        with self._lock:
            now = time.monotonic()
            if not force and now - self._last_step < self.config.interval_seconds:
                return dict(self._registers)
            hour = (self.config.start_hour + self._step) % 24
            snapshot = simulate_timestep(self.model, hour)
            values = apply_scenario(snapshot.telemetry, self.config.scenario)
            self._registers = encode_registers(self.contract, values)
            self._last_step = now
            self._step += 1
            LOGGER.info(
                "simulation_step scenario=%s hour=%s load_kw=%s solar_kw=%s voltage_pu=%s",
                self.config.scenario,
                hour,
                snapshot.load_kw,
                snapshot.solar_kw,
                snapshot.voltage_pu,
            )
            return dict(self._registers)


def build_device(state: TelemetryState) -> SimDevice:
    max_address = max(int(register["address"]) for register in state.contract["registers"])

    async def update_registers(
        function_code: int,
        start_address: int,
        address: int,
        count: int,
        current_registers: list[int],
        set_values: list[int] | list[bool] | None,
    ) -> None:
        del address, count, set_values
        if function_code != 3:
            return
        for register_address, value in state.refresh().items():
            index = register_address - start_address
            if 0 <= index < len(current_registers):
                current_registers[index] = value

    return SimDevice(
        id=state.config.unit_id,
        simdata=SimData(
            address=0,
            count=max_address + 1,
            values=0,
            datatype=DataType.UINT16,
            readonly=True,
        ),
        action=update_registers,
    )


def serve(config: ServerConfig) -> None:
    state = TelemetryState(config)
    LOGGER.info(
        "modbus_server_started host=%s port=%s unit_id=%s scenario=%s",
        config.host,
        config.port,
        config.unit_id,
        config.scenario,
    )
    StartTcpServer(context=[build_device(state)], address=(config.host, config.port))


def healthcheck(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False
