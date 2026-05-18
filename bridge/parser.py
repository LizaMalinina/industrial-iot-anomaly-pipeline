"""Parse and validate telemetry from Arduino serial output."""
import json
from typing import Optional


REQUIRED_FIELDS = {"device_id", "temperature_c", "vibration_raw"}


def parse_serial_line(line: str) -> Optional[dict]:
    """Parse a serial line into a telemetry dict, or None if not valid telemetry."""
    stripped = line.strip()

    if not stripped or stripped.startswith("#"):
        return None

    try:
        data = json.loads(stripped)
        return data if isinstance(data, dict) else None
    except (json.JSONDecodeError, ValueError):
        return None


def validate_telemetry(msg: dict) -> bool:
    """Check that a telemetry message has all required fields with correct types."""
    for field in REQUIRED_FIELDS:
        if field not in msg:
            return False

    if not isinstance(msg.get("temperature_c"), (int, float)):
        return False
    if not isinstance(msg.get("vibration_raw"), (int, float)):
        return False

    return True
