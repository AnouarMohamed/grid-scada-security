from __future__ import annotations

import argparse
import json

from power_sim.feeder import FeederModel, simulate_timestep


def main() -> None:
    parser = argparse.ArgumentParser(description="Simulate a simple feeder snapshot")
    parser.add_argument("--hour", type=int, default=12, help="Hour of day to simulate")
    parser.add_argument("--base-load", type=float, default=450.0, help="Base load in kW")
    parser.add_argument("--solar", type=float, default=60.0, help="Solar generation in kW")
    args = parser.parse_args()

    model = FeederModel(base_load_kw=args.base_load, solar_kw=args.solar)
    snapshot = simulate_timestep(model, hour=args.hour)
    print(json.dumps(snapshot.__dict__, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
