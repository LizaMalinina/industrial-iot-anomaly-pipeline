"""
Serial-to-Azure IoT Hub Bridge

Reads JSON telemetry from Arduino over USB serial and forwards to Azure IoT Hub.
"""
import asyncio
import logging
import os
import sys

import serial
from azure.iot.device.aio import IoTHubDeviceClient
from dotenv import load_dotenv

from bridge.parser import parse_serial_line, validate_telemetry
from bridge.forwarder import TelemetryForwarder

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)


async def main():
    conn_str = os.environ.get("IOT_HUB_CONNECTION_STRING")
    serial_port = os.environ.get("SERIAL_PORT", "COM3")
    baud_rate = int(os.environ.get("SERIAL_BAUD", "9600"))

    if not conn_str:
        logger.error("IOT_HUB_CONNECTION_STRING env var not set")
        sys.exit(1)

    # Connect to IoT Hub
    client = IoTHubDeviceClient.create_from_connection_string(conn_str)
    await client.connect()
    logger.info("Connected to Azure IoT Hub")

    forwarder = TelemetryForwarder(iot_hub_client=client)

    # Open serial port
    ser = serial.Serial(serial_port, baud_rate, timeout=2)
    logger.info(f"Listening on {serial_port} @ {baud_rate} baud")

    sent_count = 0
    error_count = 0

    try:
        while True:
            raw_line = ser.readline().decode("utf-8", errors="replace")
            msg = parse_serial_line(raw_line)

            if msg is None:
                continue

            if not validate_telemetry(msg):
                error_count += 1
                logger.warning(f"Invalid telemetry (total errors: {error_count}): {raw_line.strip()}")
                continue

            try:
                await forwarder.send(msg)
                sent_count += 1
                if sent_count % 10 == 0:
                    logger.info(f"Sent {sent_count} messages (errors: {error_count})")
            except Exception as e:
                error_count += 1
                logger.error(f"Failed to send: {e}")

    except KeyboardInterrupt:
        logger.info(f"Shutting down. Sent: {sent_count}, Errors: {error_count}")
    finally:
        ser.close()
        await client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
