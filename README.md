# Industrial IoT Streaming & Anomaly Detection Pipeline

A real-time data pipeline for industrial sensor data — from physical IoT devices through cloud analytics to a live dashboard — with built-in anomaly detection and production-grade observability.

## 🎯 Scenario

Monitor industrial equipment (e.g. factory machines) using vibration sensors (accelerometers) measuring x, y, z acceleration, connected via Wi-Fi-enabled Arduino/microcontroller.

**Goals:**
- Detect abnormal patterns (unusual vibrations, temperature spikes)
- Enable predictive maintenance — identify failures before they happen
- Deliver real-time anomaly alerts via live dashboards

---

## 🏗️ Architecture

```
Arduino / Sensors (vibration, temperature, pressure)
        ↓
Azure IoT Hub  (+DPS for device provisioning)
        ↓
Azure Stream Analytics
  • transformations (e.g. acceleration magnitude from x/y/z)
  • anomaly detection (AnomalyDetection_SpikeAndDip, sliding windows)
  • filtering & enrichment
        ↓                          ↓
Azure Blob / ADLS Gen2       Azure SQL / ADX
  (raw — bronze layer)       (curated — silver layer)
        ↓
Azure Functions (timer-triggered)
        ↓
Power BI / Custom Dashboard (real-time)
```

---

## 📊 Observability

### Pipeline Metrics & Logs
- **IoT Hub:** message count, connectivity events, throttling
- **Stream Analytics:** latency, dropped/late events
- Integrated with **Azure Monitor**

### Custom Instrumentation
- Azure Functions instrumented with **Application Insights** / **OpenTelemetry**
- Logs: anomaly events, device ID, processing latency, exceptions

### End-to-End Correlation
- Correlation via Device ID + timestamp/GUID
- Trace data across all pipeline stages

### Dashboards & Alerting
- **Azure Monitor Workbooks** + **Power BI**
- Alerts: no data from device, latency threshold exceeded, anomaly spikes

---

## ⚙️ Reliability & Scale

| Concern | Approach |
|---------|----------|
| **Throughput** | IoT Hub partitions by device; ASA scales via Streaming Units |
| **Out-of-order / late data** | ASA event-time processing, watermarking, late arrival tolerance |
| **Schema evolution** | Schemaless JSON in ADLS, flexible schema in SQL/ADX, dead-letter for unknown schema |
| **Fault tolerance** | At-least-once processing, retry on failures, raw data replay |
| **Availability** | IoT Hub 99.9% SLA, ASA 99.9% SLA, exponential backoff, serverless |

---

## 📦 Tech Stack

| Layer | Technology |
|-------|-----------|
| Devices | Arduino / microcontrollers, accelerometers |
| Ingestion | Azure IoT Hub, Device Provisioning Service |
| Stream Processing | Azure Stream Analytics |
| Storage (raw) | Azure Blob Storage / ADLS Gen2 |
| Storage (curated) | Azure SQL Database / Azure Data Explorer |
| Compute | Azure Functions |
| Visualization | Power BI (real-time dashboards) |
| Observability | Azure Monitor, Application Insights, OpenTelemetry |
| IaC | Terraform / Bicep |

---

## 🚀 Milestones

### 1 — Device & Ingestion
- Arduino sensor code (vibration telemetry)
- Connect to Azure IoT Hub
- Raw data landing in ADLS

### 2 — Stream Processing & Anomaly Detection
- ASA job with transformations
- Built-in anomaly detection (spike & dip)
- Output to SQL/ADX (curated layer)

### 3 — Observability
- Azure Monitor integration for pipeline metrics
- Application Insights in Azure Functions
- End-to-end correlation & alerting

### 4 — Dashboard & Visualization
- Power BI real-time streaming dataset
- Live metrics: vibration levels, anomaly alerts, trends

### 5 — Reliability & Production Hardening
- Late/out-of-order data handling
- Schema evolution strategy
- Replay & dead-letter patterns
- Load testing with device simulator

---

## 📁 Repo Structure (planned)

```
/device         — Arduino / sensor firmware (C++ / MicroPython)
/infra          — Terraform / Bicep deployment scripts
/stream-jobs    — ASA query definitions
/functions      — Azure Functions (timer-triggered processors)
/dashboard      — Power BI templates or custom web UI
/simulator      — Device simulator for load testing
/docs           — Architecture diagrams, design trade-offs
```

---

## 🧠 Design Trade-offs

| Decision | Rationale |
|----------|-----------|
| Managed services (IoT Hub, ASA) | Scalability + reliability + low ops burden |
| Lakehouse (raw + curated layers) | Flexibility for reprocessing + structured queries |
| Built-in anomaly detection (ASA) | Faster delivery; extensible to custom ML later |
| Failure-aware design | Handles offline devices, late data, retries |
| Telemetry-first mindset | SLO tracking and alerting from day one |
