from __future__ import annotations

import math
from dataclasses import dataclass, field

import pandapower as pp
from pandapower.auxiliary import pandapowerNet

BUS_NAMES = (
    "650", "632", "633", "634", "645", "646", "671",
    "680", "684", "611", "652", "692", "675",
)

# Deterministic hourly operating points make attack runs directly comparable.
LOAD_PROFILE = (
    0.68, 0.64, 0.61, 0.60, 0.62, 0.69, 0.78, 0.86,
    0.91, 0.94, 0.92, 0.90, 0.88, 0.87, 0.89, 0.94,
    1.01, 1.08, 1.12, 1.09, 1.01, 0.92, 0.82, 0.74,
)
PV_PROFILE = (
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.02, 0.12,
    0.30, 0.52, 0.72, 0.88, 1.0, 0.94, 0.78, 0.55,
    0.30, 0.10, 0.01, 0.0, 0.0, 0.0, 0.0, 0.0,
)


@dataclass(frozen=True)
class FeederSnapshot:
    voltage_pu: float
    load_kw: float
    power_kw: float
    solar_kw: float
    frequency_hz: float
    hour: int
    converged: bool
    telemetry: dict[str, float]


@dataclass
class FeederModel:
    base_load_kw: float = 2226.0
    solar_kw: float = 400.0
    net: pandapowerNet = field(init=False, repr=False)
    buses: dict[str, int] = field(init=False, repr=False)
    _base_p_mw: list[float] = field(init=False, repr=False)
    _base_q_mvar: list[float] = field(init=False, repr=False)
    _pv_index: int = field(init=False, repr=False)
    _source_line: int = field(init=False, repr=False)
    _bus_671_line: int = field(init=False, repr=False)

    def __post_init__(self) -> None:
        self.net, self.buses, self._source_line, self._bus_671_line = build_ieee13_feeder()
        self._base_p_mw = self.net.load.p_mw.astype(float).tolist()
        self._base_q_mvar = self.net.load.q_mvar.astype(float).tolist()
        self._pv_index = int(self.net.sgen.index[0])

    def voltage_for_hour(self, hour: int) -> float:
        return simulate_timestep(self, hour).voltage_pu


def _line(
    net: pandapowerNet,
    buses: dict[str, int],
    start: str,
    end: str,
    length_km: float,
) -> int:
    return pp.create_line_from_parameters(
        net,
        from_bus=buses[start],
        to_bus=buses[end],
        length_km=length_km,
        r_ohm_per_km=0.35,
        x_ohm_per_km=0.30,
        c_nf_per_km=0.0,
        max_i_ka=0.60,
        name=f"{start}-{end}",
    )


def build_ieee13_feeder() -> tuple[pandapowerNet, dict[str, int], int, int]:
    """Build a balanced positive-sequence approximation of the IEEE 13-node feeder."""
    net = pp.create_empty_network(name="GridGuard IEEE 13-node feeder", sn_mva=5.0, f_hz=60.0)
    buses = {
        name: pp.create_bus(net, vn_kv=0.48 if name == "634" else 4.16, name=name)
        for name in BUS_NAMES
    }
    pp.create_ext_grid(net, buses["650"], vm_pu=1.02, name="substation-650")

    source_line = _line(net, buses, "650", "632", 0.20)
    _line(net, buses, "632", "633", 0.15)
    _line(net, buses, "632", "645", 0.20)
    _line(net, buses, "645", "646", 0.10)
    bus_671_line = _line(net, buses, "632", "671", 0.60)
    _line(net, buses, "671", "680", 0.30)
    _line(net, buses, "671", "684", 0.15)
    _line(net, buses, "684", "611", 0.10)
    _line(net, buses, "684", "652", 0.25)
    _line(net, buses, "671", "692", 0.05)
    _line(net, buses, "692", "675", 0.20)

    pp.create_transformer_from_parameters(
        net,
        hv_bus=buses["633"],
        lv_bus=buses["634"],
        sn_mva=0.50,
        vn_hv_kv=4.16,
        vn_lv_kv=0.48,
        vk_percent=2.0,
        vkr_percent=1.0,
        pfe_kw=0.0,
        i0_percent=0.0,
        shift_degree=0.0,
        name="633-634",
    )

    loads = (
        ("634", 0.400, 0.290),
        ("645", 0.170, 0.125),
        ("646", 0.230, 0.132),
        ("671", 0.115, 0.066),
        ("675", 0.843, 0.462),
        ("611", 0.170, 0.080),
        ("652", 0.128, 0.086),
        ("692", 0.170, 0.151),
    )
    for bus, p_mw, q_mvar in loads:
        pp.create_load(net, buses[bus], p_mw=p_mw, q_mvar=q_mvar, name=f"load-{bus}")

    pp.create_shunt(net, buses["675"], q_mvar=-0.30, p_mw=0.0, name="capacitor-675")
    pp.create_shunt(net, buses["611"], q_mvar=-0.10, p_mw=0.0, name="capacitor-611")
    pp.create_sgen(net, buses["675"], p_mw=0.0, q_mvar=0.0, name="pv-675")
    return net, buses, source_line, bus_671_line


def simulate_timestep(model: FeederModel, hour: int) -> FeederSnapshot:
    hour %= 24
    load_scale = LOAD_PROFILE[hour] * (model.base_load_kw / 2226.0)
    pv_kw = model.solar_kw * PV_PROFILE[hour]

    model.net.load.loc[:, "p_mw"] = [value * load_scale for value in model._base_p_mw]
    model.net.load.loc[:, "q_mvar"] = [value * load_scale for value in model._base_q_mvar]
    model.net.sgen.at[model._pv_index, "p_mw"] = pv_kw / 1000.0
    model.net.ext_grid.at[0, "vm_pu"] = (
        1.012 - 0.006 * (load_scale - 0.85) + 0.003 * PV_PROFILE[hour]
    )
    pp.runpp(model.net, algorithm="nr", calculate_voltage_angles=True, numba=False)

    source_voltage = float(model.net.res_bus.at[model.buses["650"], "vm_pu"])
    source_current_a = float(model.net.res_line.at[model._source_line, "i_from_ka"]) * 1000.0
    real_power_kw = (
        abs(float(model.net.res_line.at[model._bus_671_line, "p_from_mw"])) * 1000.0
    )
    reactive_power_kvar = (
        abs(float(model.net.res_line.at[model._bus_671_line, "q_from_mvar"])) * 1000.0
    )
    total_load_kw = float(model.net.load.p_mw.sum()) * 1000.0
    frequency_hz = 60.0 + 0.012 * math.sin(hour * math.pi / 12.0)

    telemetry = {
        "bus_650_a_voltage": source_voltage,
        "bus_650_b_voltage": source_voltage * 0.9985,
        "bus_650_c_voltage": source_voltage * 1.0010,
        "bus_632_a_current": source_current_a * 1.015,
        "bus_632_b_current": source_current_a * 0.985,
        "bus_632_c_current": source_current_a,
        "feeder_frequency": frequency_hz,
        "bus_671_total_real_power": real_power_kw,
        "bus_671_total_reactive_power": reactive_power_kvar,
    }
    return FeederSnapshot(
        voltage_pu=round(source_voltage, 5),
        load_kw=round(total_load_kw, 2),
        power_kw=round(real_power_kw, 2),
        solar_kw=round(pv_kw, 2),
        frequency_hz=round(frequency_hz, 4),
        hour=hour,
        converged=bool(model.net.converged),
        telemetry={name: round(value, 5) for name, value in telemetry.items()},
    )


def simulate_day(model: FeederModel) -> list[FeederSnapshot]:
    return [simulate_timestep(model, hour) for hour in range(24)]


def build_register_map() -> dict[str, dict[str, object]]:
    return {
        "bus_voltage": {
            "name": "bus_voltage",
            "scale": 10000,
            "unit": "pu",
            "description": "Substation voltage in per unit",
        },
        "load_kw": {
            "name": "load_kw",
            "scale": 10,
            "unit": "kW",
            "description": "Feeder real power",
        },
    }
