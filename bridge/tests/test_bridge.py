"""
Tests for the serial-to-IoT Hub bridge.
TDD: these tests define expected behavior before implementation.
"""
import json
import pytest
from unittest.mock import MagicMock, patch, AsyncMock
from bridge.parser import parse_serial_line, validate_telemetry
from bridge.forwarder import TelemetryForwarder


class TestParseSerialLine:
    """Parse raw serial input into telemetry dicts."""

    def test_valid_json_line(self):
        line = '{"device_id":"arduino-uno-001","seq":0,"temperature_c":23.45,"vibration_raw":12}'
        result = parse_serial_line(line)
        assert result is not None
        assert result["device_id"] == "arduino-uno-001"
        assert result["temperature_c"] == 23.45
        assert result["vibration_raw"] == 12

    def test_comment_line_ignored(self):
        line = "# IoT Sensor Firmware v1.0 started"
        result = parse_serial_line(line)
        assert result is None

    def test_empty_line_ignored(self):
        assert parse_serial_line("") is None
        assert parse_serial_line("   ") is None

    def test_invalid_json_returns_none(self):
        result = parse_serial_line("{broken json")
        assert result is None

    def test_strips_whitespace_and_newlines(self):
        line = '  {"device_id":"x","seq":1,"temperature_c":20.0,"vibration_raw":0}\r\n'
        result = parse_serial_line(line)
        assert result is not None
        assert result["device_id"] == "x"


class TestValidateTelemetry:
    """Validate that telemetry dicts have required fields."""

    def test_valid_message(self):
        msg = {"device_id": "arduino-uno-001", "seq": 0, "temperature_c": 22.5, "vibration_raw": 10}
        assert validate_telemetry(msg) is True

    def test_missing_device_id(self):
        msg = {"seq": 0, "temperature_c": 22.5, "vibration_raw": 10}
        assert validate_telemetry(msg) is False

    def test_missing_temperature(self):
        msg = {"device_id": "x", "seq": 0, "vibration_raw": 10}
        assert validate_telemetry(msg) is False

    def test_missing_vibration(self):
        msg = {"device_id": "x", "seq": 0, "temperature_c": 22.5}
        assert validate_telemetry(msg) is False

    def test_non_numeric_temperature_invalid(self):
        msg = {"device_id": "x", "seq": 0, "temperature_c": "hot", "vibration_raw": 10}
        assert validate_telemetry(msg) is False


class TestTelemetryForwarder:
    """Forwarder enriches messages and sends to IoT Hub."""

    def test_enrich_adds_timestamp(self):
        forwarder = TelemetryForwarder(iot_hub_client=MagicMock())
        msg = {"device_id": "x", "seq": 1, "temperature_c": 20.0, "vibration_raw": 5}
        enriched = forwarder.enrich(msg)
        assert "timestamp" in enriched
        assert "bridge_version" in enriched

    def test_enrich_preserves_original_fields(self):
        forwarder = TelemetryForwarder(iot_hub_client=MagicMock())
        msg = {"device_id": "x", "seq": 1, "temperature_c": 20.0, "vibration_raw": 5}
        enriched = forwarder.enrich(msg)
        assert enriched["device_id"] == "x"
        assert enriched["temperature_c"] == 20.0

    @pytest.mark.asyncio
    async def test_send_calls_iot_hub_client(self):
        mock_client = AsyncMock()
        forwarder = TelemetryForwarder(iot_hub_client=mock_client)
        msg = {"device_id": "x", "seq": 1, "temperature_c": 20.0, "vibration_raw": 5}

        await forwarder.send(msg)

        mock_client.send_message.assert_called_once()
        sent_payload = mock_client.send_message.call_args[0][0]
        data = json.loads(sent_payload)
        assert data["device_id"] == "x"
