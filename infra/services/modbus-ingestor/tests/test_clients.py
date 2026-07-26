from __future__ import annotations

import pytest
from gridguard_modbus_ingestor.clients import (
    FixtureRegisterClient,
    ModbusProtocolError,
    _parse_read_holding_registers_response,
)


def test_fixture_client_reads_register_range() -> None:
    client = FixtureRegisterClient({0: 10112, 1: 10086, 2: 10093})

    assert client.read_holding_registers(start=0, count=3, unit_id=1) == [
        10112,
        10086,
        10093,
    ]


def test_fixture_client_reports_missing_register() -> None:
    client = FixtureRegisterClient({0: 10112})

    with pytest.raises(ValueError, match="missing register address 1"):
        client.read_holding_registers(start=0, count=2, unit_id=1)


def test_fixture_client_validates_read_bounds() -> None:
    client = FixtureRegisterClient({0: 10112})

    with pytest.raises(ValueError, match="read range"):
        client.read_holding_registers(start=65535, count=2, unit_id=1)


def test_parse_modbus_holding_register_response() -> None:
    response = bytes([0x03, 0x04, 0x27, 0x80, 0x00, 0x2A])

    assert _parse_read_holding_registers_response(response, count=2) == [10112, 42]


def test_parse_modbus_exception_response() -> None:
    response = bytes([0x83, 0x02])

    with pytest.raises(ModbusProtocolError, match="exception"):
        _parse_read_holding_registers_response(response, count=1)
