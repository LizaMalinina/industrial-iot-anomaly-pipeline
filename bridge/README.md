# Bridge — Serial-to-Azure IoT Hub Forwarder

Reads JSON telemetry from Arduino over USB serial and forwards it to Azure IoT Hub.

## Setup

```bash
pip install -r requirements.txt
```

## Configuration

Set environment variables:
```bash
IOT_HUB_CONNECTION_STRING=HostName=<hub>.azure-devices.net;DeviceId=<id>;SharedAccessKey=<key>
SERIAL_PORT=COM3          # Windows — check Device Manager
SERIAL_BAUD=9600
```

## Run

```bash
python bridge.py
```

## Test (without hardware)

```bash
pytest tests/ -v
```
