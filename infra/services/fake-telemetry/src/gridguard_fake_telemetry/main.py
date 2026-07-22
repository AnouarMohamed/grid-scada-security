from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
import threading
import time
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from types import FrameType

from gridguard_fake_telemetry.config import IngestConfig, SourceConfig
from gridguard_fake_telemetry.generator import generate_snapshot
from gridguard_fake_telemetry.influx import (
    fetch_snapshot,
    snapshot_to_line_protocol,
    write_line_protocol,
)

LOG_FORMAT = "%(asctime)s %(levelname)s %(name)s %(message)s"
LOGGER = logging.getLogger("gridguard.fake_telemetry")


def request_path(raw_path: str) -> str:
    return urllib.parse.urlsplit(raw_path).path


class TelemetryHandler(BaseHTTPRequestHandler):
    server_version = "GridGuardFakeTelemetry/0.1"

    def do_GET(self) -> None:
        path = request_path(self.path)

        if path == "/healthz":
            self._write_json({"status": "ok"})
            return

        if path == "/measurements":
            config: SourceConfig = self.server.config  # type: ignore[attr-defined]
            snapshot = generate_snapshot(
                feeder_id=config.feeder_id,
                scenario=config.scenario,
            )
            self._write_json(snapshot)
            return

        self.send_error(HTTPStatus.NOT_FOUND, "unknown endpoint")

    def log_message(self, fmt: str, *args: object) -> None:
        LOGGER.debug("source_http " + fmt, *args)

    def _write_json(self, payload: dict[str, object]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def run_source() -> int:
    config = SourceConfig.from_env()
    server = ThreadingHTTPServer((config.host, config.port), TelemetryHandler)
    server.config = config  # type: ignore[attr-defined]
    shutdown_started = False

    def _stop(_signum: int, _frame: FrameType | None) -> None:
        nonlocal shutdown_started
        if shutdown_started:
            return
        shutdown_started = True
        LOGGER.info("source_shutdown_requested")
        threading.Thread(target=server.shutdown, name="source-shutdown", daemon=True).start()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    LOGGER.info(
        "source_started host=%s port=%s feeder=%s scenario=%s",
        config.host,
        config.port,
        config.feeder_id,
        config.scenario,
    )
    server.serve_forever(poll_interval=0.5)
    return 0


def run_ingestor() -> int:
    config = IngestConfig.from_env()
    should_stop = False

    def _stop(_signum: int, _frame: FrameType | None) -> None:
        nonlocal should_stop
        LOGGER.info("ingestor_shutdown_requested")
        should_stop = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    LOGGER.info(
        "ingestor_started source_url=%s influx_url=%s org=%s bucket=%s interval=%s",
        config.source_url,
        config.influx_url,
        config.org,
        config.bucket,
        config.interval_seconds,
    )

    while not should_stop:
        started = time.monotonic()
        try:
            snapshot = fetch_snapshot(config.source_url, config.request_timeout_seconds)
            line_protocol = snapshot_to_line_protocol(snapshot)
            if line_protocol:
                write_line_protocol(
                    influx_url=config.influx_url,
                    org=config.org,
                    bucket=config.bucket,
                    token=config.token,
                    line_protocol=line_protocol,
                    timeout_seconds=config.request_timeout_seconds,
                )
                config.status_file.write_text(str(time.time()), encoding="utf-8")
                LOGGER.info(
                    "ingestor_write_ok snapshot_id=%s points=%s",
                    snapshot.get("snapshot_id"),
                    snapshot.get("point_count"),
                )
        except Exception:
            LOGGER.exception("ingestor_write_failed")

        elapsed = time.monotonic() - started
        time.sleep(max(config.interval_seconds - elapsed, 0.2))

    return 0


def healthcheck_source() -> int:
    config = SourceConfig.from_env()
    url = f"http://127.0.0.1:{config.port}/healthz"
    try:
        with urllib.request.urlopen(url, timeout=2.0) as response:  # nosec B310
            return 0 if response.status == HTTPStatus.OK else 1
    except Exception:
        return 1


def healthcheck_ingestor() -> int:
    config = IngestConfig.from_env()
    try:
        last_success = float(config.status_file.read_text(encoding="utf-8").strip())
    except (FileNotFoundError, ValueError):
        return 1

    max_age_seconds = max(config.interval_seconds * 4, 20.0)
    return 0 if time.time() - last_success <= max_age_seconds else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="GridGuard fake telemetry service")
    parser.add_argument(
        "mode",
        choices=("source", "ingest", "healthcheck-source", "healthcheck-ingestor"),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
    args = build_parser().parse_args(argv)

    if args.mode == "source":
        return run_source()
    if args.mode == "ingest":
        return run_ingestor()
    if args.mode == "healthcheck-source":
        return healthcheck_source()
    if args.mode == "healthcheck-ingestor":
        return healthcheck_ingestor()

    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
