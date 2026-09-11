from __future__ import annotations

import argparse
import json
import logging
import os
import sys

from power_sim.attacks import Scenario, apply_scenario
from power_sim.health import healthcheck


def _snapshot(args: argparse.Namespace) -> int:
    from power_sim.feeder import FeederModel, simulate_timestep

    snapshot = simulate_timestep(
        FeederModel(base_load_kw=args.base_load, solar_kw=args.solar),
        hour=args.hour,
    )
    payload = {
        **snapshot.__dict__,
        "scenario": args.scenario,
        "telemetry": apply_scenario(snapshot.telemetry, Scenario(args.scenario)),
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


def _series(args: argparse.Namespace) -> int:
    from power_sim.feeder import FeederModel, simulate_day

    snapshots = simulate_day(FeederModel(base_load_kw=args.base_load, solar_kw=args.solar))
    print(json.dumps([snapshot.__dict__ for snapshot in snapshots], indent=2, sort_keys=True))
    return 0


def _serve(_args: argparse.Namespace) -> int:
    from power_sim.server import ServerConfig, serve

    serve(ServerConfig.from_env())
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="GridGuard IEEE 13-node power simulator")
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot = subparsers.add_parser("snapshot", help="solve and print one operating point")
    snapshot.add_argument("--hour", type=int, default=12)
    snapshot.add_argument("--base-load", type=float, default=2226.0)
    snapshot.add_argument("--solar", type=float, default=400.0)
    snapshot.add_argument(
        "--scenario",
        choices=[item.value for item in Scenario],
        default=Scenario.BASELINE.value,
    )
    snapshot.set_defaults(handler=_snapshot)

    series = subparsers.add_parser("series", help="solve and print all 24 hourly points")
    series.add_argument("--base-load", type=float, default=2226.0)
    series.add_argument("--solar", type=float, default=400.0)
    series.set_defaults(handler=_series)

    server = subparsers.add_parser("serve", help="serve live telemetry over Modbus TCP")
    server.set_defaults(handler=_serve)

    health = subparsers.add_parser("healthcheck", help="check the local Modbus listener")
    health.set_defaults(
        handler=lambda _args: 0
        if healthcheck(
            os.getenv("GRIDGUARD_HEALTH_HOST", "127.0.0.1"),
            int(os.getenv("GRIDGUARD_MODBUS_PORT", "502")),
        )
        else 1
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    args = build_parser().parse_args(argv)
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
