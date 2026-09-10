# Power Simulator

The power track implements a balanced positive-sequence approximation of the
IEEE 13-node distribution feeder in `pandapower`. It preserves the standard
node names and the 633/634 distribution transformer, applies deterministic
24-hour demand and PV profiles, and publishes selected results through the
shared Modbus register contract.

The model is intended for repeatable cyber-range experiments. It is not an
unbalanced electromagnetic-transients reproduction of the reference feeder.

## Local Commands

```bash
python -m power_sim snapshot --hour 12
python -m power_sim series
```

The container starts a Modbus TCP server with `python -m power_sim serve`.
Runtime configuration:

| Variable | Default | Purpose |
| --- | --- | --- |
| `GRIDGUARD_MODBUS_HOST` | `0.0.0.0` | Listener address |
| `GRIDGUARD_MODBUS_PORT` | `502` | Listener port |
| `GRIDGUARD_MODBUS_UNIT_ID` | `1` | Modbus device ID |
| `GRIDGUARD_SIM_INTERVAL_SECONDS` | `2` | Seconds per simulated hour |
| `GRIDGUARD_SIM_START_HOUR` | `0` | First hour in the replay |
| `GRIDGUARD_SCENARIO` | `baseline-modbus` | Baseline, naive, or stealthy scenario |
| `GRIDGUARD_REGISTER_MAP` | `/etc/gridguard/register-map.json` | Shared contract path |

Supported scenarios are `baseline-modbus`, `naive-bad-value`, and
`stealthy-fdia`. The attack scenarios are deterministic so red/blue runs can
be compared directly.
