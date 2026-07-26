from __future__ import annotations

import json
import socket
import struct
from pathlib import Path
from typing import Protocol


class RegisterClient(Protocol):
    def read_holding_registers(self, *, start: int, count: int, unit_id: int) -> list[int]:
        """Read holding registers using zero-based Modbus PDU addresses."""


class FixtureRegisterClient:
    def __init__(self, values: dict[int, int]) -> None:
        self.values = values

    @classmethod
    def from_file(cls, path: Path) -> FixtureRegisterClient:
        payload = json.loads(path.read_text(encoding="utf-8"))
        raw_registers = payload.get("registers")
        if not isinstance(raw_registers, dict):
            raise ValueError("fixture registers must be an object")

        values: dict[int, int] = {}
        for raw_address, raw_value in raw_registers.items():
            address = int(raw_address)
            value = int(raw_value)
            if address < 0 or address > 65535:
                raise ValueError(f"fixture address out of range: {address}")
            if value < 0 or value > 0xFFFF:
                raise ValueError(f"fixture value out of uint16 range at {address}: {value}")
            values[address] = value

        return cls(values)

    def read_holding_registers(self, *, start: int, count: int, unit_id: int) -> list[int]:
        _validate_read_request(start=start, count=count, unit_id=unit_id)
        del unit_id
        try:
            return [self.values[address] for address in range(start, start + count)]
        except KeyError as exc:
            raise ValueError(f"fixture missing register address {exc.args[0]}") from exc


class ModbusProtocolError(RuntimeError):
    pass


class ModbusTcpClient:
    def __init__(self, *, host: str, port: int, timeout_seconds: float) -> None:
        self.host = host
        self.port = port
        self.timeout_seconds = timeout_seconds
        self._transaction_id = 0

    def read_holding_registers(self, *, start: int, count: int, unit_id: int) -> list[int]:
        _validate_read_request(start=start, count=count, unit_id=unit_id)

        self._transaction_id = (self._transaction_id + 1) % 0x10000
        pdu = struct.pack(">BHH", 0x03, start, count)
        request = _mbap(self._transaction_id, unit_id, len(pdu)) + pdu

        with socket.create_connection(
            (self.host, self.port),
            timeout=self.timeout_seconds,
        ) as sock:
            sock.settimeout(self.timeout_seconds)
            sock.sendall(request)
            header = _read_exact(sock, 7)
            transaction_id, protocol_id, length, response_unit = struct.unpack(
                ">HHHB",
                header,
            )
            if transaction_id != self._transaction_id:
                raise ModbusProtocolError("unexpected Modbus transaction id")
            if protocol_id != 0:
                raise ModbusProtocolError("unexpected Modbus protocol id")
            if response_unit != unit_id:
                raise ModbusProtocolError("unexpected Modbus unit id")

            response_pdu = _read_exact(sock, length - 1)

        return _parse_read_holding_registers_response(response_pdu, count)


def _mbap(transaction_id: int, unit_id: int, pdu_length: int) -> bytes:
    protocol_id = 0
    length = pdu_length + 1
    return struct.pack(">HHHB", transaction_id, protocol_id, length, unit_id)


def _validate_read_request(*, start: int, count: int, unit_id: int) -> None:
    if unit_id < 1 or unit_id > 247:
        raise ValueError(f"Modbus unit id must be between 1 and 247, got {unit_id}")
    if start < 0 or start > 65535:
        raise ValueError(f"Modbus start address must be between 0 and 65535, got {start}")
    if count < 1 or count > 125:
        raise ValueError(f"Modbus read count must be between 1 and 125, got {count}")
    if start + count - 1 > 65535:
        raise ValueError("Modbus read range exceeds address 65535")


def _read_exact(sock: socket.socket, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise ModbusProtocolError("connection closed before full response")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _parse_read_holding_registers_response(response_pdu: bytes, count: int) -> list[int]:
    if not response_pdu:
        raise ModbusProtocolError("empty Modbus response")

    function_code = response_pdu[0]
    if function_code == 0x83:
        exception_code = response_pdu[1] if len(response_pdu) > 1 else 0
        raise ModbusProtocolError(f"Modbus exception response: {exception_code}")
    if function_code != 0x03:
        raise ModbusProtocolError(f"unexpected Modbus function code: {function_code}")
    if len(response_pdu) < 2:
        raise ModbusProtocolError("short Modbus response")

    byte_count = response_pdu[1]
    expected_byte_count = count * 2
    if byte_count != expected_byte_count:
        raise ModbusProtocolError(
            f"expected {expected_byte_count} data bytes, got {byte_count}"
        )
    if len(response_pdu) != byte_count + 2:
        raise ModbusProtocolError("Modbus response length does not match byte count")

    return [
        struct.unpack(">H", response_pdu[offset : offset + 2])[0]
        for offset in range(2, len(response_pdu), 2)
    ]
