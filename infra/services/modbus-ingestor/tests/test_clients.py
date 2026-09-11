from __future__ import annotations

import json
import struct

import pytest
from gridguard_modbus_ingestor.clients import (
    FixtureRegisterClient,
    ModbusProtocolError,
    ModbusTcpClient,
    _parse_read_holding_registers_response,
    _validate_mbap_response_length,
)


class FakeSocket:
    def __init__(self, response: bytes) -> None:
        self.response = bytearray(response)
        self.sent = b""
        self.timeout = 0.0

    def __enter__(self):
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def settimeout(self, timeout: float) -> None:
        self.timeout = timeout

    def sendall(self, payload: bytes) -> None:
        self.sent = payload

    def recv(self, size: int) -> bytes:
        chunk = bytes(self.response[:size])
        del self.response[:size]
        return chunk


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


@pytest.mark.parametrize("raw_value", [1.5, True, "42"])
def test_fixture_client_rejects_non_integer_values(tmp_path, raw_value: object) -> None:
    fixture_path = tmp_path / "registers.json"
    fixture_path.write_text(
        json.dumps({"registers": {"0": raw_value}}),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="must be an integer"):
        FixtureRegisterClient.from_file(fixture_path)


def test_fixture_client_rejects_normalized_duplicate_addresses(tmp_path) -> None:
    fixture_path = tmp_path / "registers.json"
    fixture_path.write_text('{"registers":{"1":10,"01":20}}', encoding="utf-8")

    with pytest.raises(ValueError, match="duplicate register address 1"):
        FixtureRegisterClient.from_file(fixture_path)


@pytest.mark.parametrize("length", [0, 1, 2, 4, 6, 8, 254, 65535])
def test_mbap_response_length_is_bounded(length: int) -> None:
    with pytest.raises(ModbusProtocolError, match="unexpected Modbus response length"):
        _validate_mbap_response_length(length=length, count=2)


@pytest.mark.parametrize("length", [3, 7])
def test_mbap_response_length_accepts_exception_or_exact_payload(length: int) -> None:
    _validate_mbap_response_length(length=length, count=2)


def test_parse_modbus_holding_register_response() -> None:
    response = bytes([0x03, 0x04, 0x27, 0x80, 0x00, 0x2A])

    assert _parse_read_holding_registers_response(response, count=2) == [10112, 42]


def test_parse_modbus_exception_response() -> None:
    response = bytes([0x83, 0x02])

    with pytest.raises(ModbusProtocolError, match="exception"):
        _parse_read_holding_registers_response(response, count=1)


def test_tcp_client_validates_and_parses_response(monkeypatch: pytest.MonkeyPatch) -> None:
    response_pdu = bytes([0x03, 0x04, 0x27, 0x80, 0x00, 0x2A])
    fake_socket = FakeSocket(struct.pack(">HHHB", 1, 0, 7, 1) + response_pdu)
    monkeypatch.setattr(
        "gridguard_modbus_ingestor.clients.socket.create_connection",
        lambda address, timeout: fake_socket,
    )

    client = ModbusTcpClient(host="power-sim", port=502, timeout_seconds=2.0)
    assert client.read_holding_registers(start=0, count=2, unit_id=1) == [10112, 42]
    assert fake_socket.sent == struct.pack(">HHHBBHH", 1, 0, 6, 1, 3, 0, 2)
    assert fake_socket.timeout == 2.0


def test_tcp_client_rejects_unbounded_response_before_body_read(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake_socket = FakeSocket(struct.pack(">HHHB", 1, 0, 65535, 1))
    monkeypatch.setattr(
        "gridguard_modbus_ingestor.clients.socket.create_connection",
        lambda address, timeout: fake_socket,
    )

    client = ModbusTcpClient(host="power-sim", port=502, timeout_seconds=2.0)
    with pytest.raises(ModbusProtocolError, match="unexpected Modbus response length"):
        client.read_holding_registers(start=0, count=2, unit_id=1)


def test_tcp_client_rejects_short_response(monkeypatch: pytest.MonkeyPatch) -> None:
    fake_socket = FakeSocket(struct.pack(">HHHB", 1, 0, 7, 1) + b"\x03")
    monkeypatch.setattr(
        "gridguard_modbus_ingestor.clients.socket.create_connection",
        lambda address, timeout: fake_socket,
    )

    client = ModbusTcpClient(host="power-sim", port=502, timeout_seconds=2.0)
    with pytest.raises(ModbusProtocolError, match="connection closed"):
        client.read_holding_registers(start=0, count=2, unit_id=1)
