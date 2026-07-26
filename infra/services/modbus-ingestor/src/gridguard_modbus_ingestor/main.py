from __future__ import annotations

import argparse
import logging
import signal
import sys
import time
from types import FrameType

from gridguard_modbus_ingestor.clients import FixtureRegisterClient, ModbusTcpClient
from gridguard_modbus_ingestor.config import AppConfig
from gridguard_modbus_ingestor.contract import load_register_map
from gridguard_modbus_ingestor.influx import line_protocol, write_line_protocol
from gridguard_modbus_ingestor.pipeline import read_register_values, telemetry_points

LOG_FORMAT = "%(asctime)s %(levelname)s %(name)s %(message)s"
LOGGER = logging.getLogger("gridguard.modbus_ingestor")


def build_client(config: AppConfig):
    if config.mode == "fixture":
        return FixtureRegisterClient.from_file(config.register_fixture)
    return ModbusTcpClient(
        host=config.modbus_host,
        port=config.modbus_port,
        timeout_seconds=config.request_timeout_seconds,
    )


def run_once(config: AppConfig) -> int:
    register_map = load_register_map(config.register_map)
    client = build_client(config)
    effective_unit_id = (
        config.modbus_unit_id if config.modbus_unit_id is not None else register_map.unit_id
    )
    register_values = read_register_values(
        register_map=register_map,
        client=client,
        unit_id=effective_unit_id,
    )
    points = telemetry_points(
        register_map=register_map,
        register_values=register_values,
        source_id=config.source_id,
    )
    payload = line_protocol(points)
    if not payload:
        raise RuntimeError("no telemetry points produced from register map")

    write_line_protocol(
        influx_url=config.influx_url,
        org=config.influx_org,
        bucket=config.influx_bucket,
        token=config.influx_token,
        payload=payload,
        timeout_seconds=config.request_timeout_seconds,
    )
    config.status_file.write_text(str(time.time()), encoding="utf-8")
    LOGGER.info(
        "modbus_ingest_ok mode=%s source=%s feeder=%s unit_id=%s points=%s",
        config.mode,
        config.source_id,
        register_map.feeder,
        effective_unit_id,
        len(points),
    )
    return len(points)


def run_loop() -> int:
    config = AppConfig.from_env()
    should_stop = False

    def _stop(_signum: int, _frame: FrameType | None) -> None:
        nonlocal should_stop
        LOGGER.info("modbus_ingestor_shutdown_requested")
        should_stop = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    LOGGER.info(
        "modbus_ingestor_started mode=%s source=%s influx_url=%s bucket=%s interval=%s",
        config.mode,
        config.source_id,
        config.influx_url,
        config.influx_bucket,
        config.interval_seconds,
    )

    while not should_stop:
        started = time.monotonic()
        try:
            run_once(config)
        except Exception:
            LOGGER.exception("modbus_ingest_failed")

        elapsed = time.monotonic() - started
        time.sleep(max(config.interval_seconds - elapsed, 0.2))

    return 0


def validate_map() -> int:
    config = AppConfig.from_env()
    register_map = load_register_map(config.register_map)
    print(
        f"register-map ok: name={register_map.name} "
        f"unit_id={register_map.unit_id} registers={len(register_map.registers)}"
    )
    return 0


def healthcheck() -> int:
    config = AppConfig.from_env()
    try:
        last_success = float(config.status_file.read_text(encoding="utf-8").strip())
    except (FileNotFoundError, ValueError):
        return 1

    max_age_seconds = max(config.interval_seconds * 4, 20.0)
    return 0 if time.time() - last_success <= max_age_seconds else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="GridGuard Modbus ingestion service")
    parser.add_argument(
        "mode",
        choices=("ingest", "ingest-once", "validate-map", "healthcheck"),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
    args = build_parser().parse_args(argv)

    if args.mode == "ingest":
        return run_loop()
    if args.mode == "ingest-once":
        run_once(AppConfig.from_env())
        return 0
    if args.mode == "validate-map":
        return validate_map()
    if args.mode == "healthcheck":
        return healthcheck()

    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
