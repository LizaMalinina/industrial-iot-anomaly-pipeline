"""Forward telemetry messages to Azure IoT Hub."""
import json
from datetime import datetime, timezone

BRIDGE_VERSION = "1.0.0"


class TelemetryForwarder:
    """Enriches telemetry and sends to Azure IoT Hub."""

    def __init__(self, iot_hub_client):
        self._client = iot_hub_client

    def enrich(self, msg: dict) -> dict:
        """Add bridge metadata (timestamp, version) to the message."""
        enriched = {**msg}
        enriched["timestamp"] = datetime.now(timezone.utc).isoformat()
        enriched["bridge_version"] = BRIDGE_VERSION
        return enriched

    async def send(self, msg: dict) -> None:
        """Enrich and send a telemetry message to IoT Hub."""
        enriched = self.enrich(msg)
        payload = json.dumps(enriched)
        await self._client.send_message(payload)
