# Troubleshooting and Lessons Learned

Issues encountered during development, their root causes, and solutions. Reference this before recreating or modifying the pipeline.

---

## IoT Hub

### F1 tier daily quota silently drops messages

**Symptom:** Bridge reports successful sends, but no new data appears in ADX or blob storage.

**Root cause:** F1 tier has a hard daily limit of 8,000 messages. Once exhausted, IoT Hub silently drops incoming messages — the device SDK does not surface quota errors.

**Solution:** Use S1 tier (400,000 messages/day, ~$25/month). F1 cannot be upgraded to S1 in-place; you must create a new hub, recreate device identities, and update all downstream connections (ADX data connection, ASA input, bridge `.env`).

**How to check:**
```powershell
az iot hub show --name <hub> --query "properties.state" -o tsv
# Check portal: IoT Hub → Overview → Daily message count
```

### Device identities are NOT ARM resources

**Symptom:** Bicep deployment fails with `Microsoft.Devices/IotHubs/devices is not a valid resource type`.

**Root cause:** Device identities exist in IoT Hub's device registry, not in ARM. They cannot be managed via Bicep/ARM templates.

**Solution:** Create device identities via Azure CLI after Bicep deployment:
```powershell
az iot hub device-identity create --hub-name <hub> --device-id sensor-dev-001
az iot hub device-identity connection-string show --hub-name <hub> --device-id sensor-dev-001 -o tsv
```

---

## Azure Data Explorer (ADX)

### Data connection shows 0 rows despite successful provisioning

**Symptom:** ADX data connection is provisioned and shows no errors, but `SensorReadings | count` returns 0.

**Root causes (check all):**

1. **IoT Hub consumer group exhausted.** If another consumer (e.g., ASA) is reading from the same consumer group, ADX may not get events. Use a dedicated consumer group (e.g., `$Default` for ADX, `asa-consumers` for ASA).

2. **Shared access policy lacks read permission.** The `service` policy does NOT have `ServiceConnect` (read) permission on the Events endpoint. Use `iothubowner` for the data connection.

3. **JSON mapping not specified.** Without `mappingRuleName` on the data connection, ADX won't auto-map JSON fields to table columns. Always create a JSON mapping and reference it.

4. **Batch ingestion delay.** Default batch policy is 5 minutes / 1000 items / 1 GB. For dev/test, reduce:
   ```kql
   .alter table SensorReadings policy ingestionbatching '{"MaximumBatchingTimeSpan": "00:00:30"}'
   ```

5. **IoT Hub quota exhausted (F1).** See above — no events means no ingestion.

**How to verify the connection works:**
```kql
// Manual inline ingest to confirm table + mapping are correct
.ingest inline into table SensorReadings <| "test-device",1,22.5,100,datetime(2024-01-01),"1.0"
```

### System property names are NOT camelCase

**Symptom:** ADX data connection deployment fails or `device_id` column is always null.

**Root cause:** System properties use hyphenated names, not camelCase:
- ✅ `iothub-connection-device-id`
- ❌ `iothubConnectionDeviceId`
- ✅ `iothub-enqueuedtime`
- ❌ `iothubEnqueuedTime`

### Bicep raw strings (`'''`) do NOT support interpolation

**Symptom:** KQL script in Bicep contains literal `${tableName}` instead of the variable value.

**Root cause:** Bicep `'''..'''` raw strings do not process `${var}` interpolation. Variables are treated as literal text.

**Solution:** Hardcode values in the KQL script, or use regular string concatenation with proper escaping.

---

## Stream Analytics (ASA)

### `WITH` clause must come FIRST in the query

**Symptom:** Job fails to start with `'with' clause is only allowed in the first select statement`.

**Root cause:** ASA requires CTE (`WITH`) clauses before any `SELECT ... INTO` statements. Unlike SQL Server, you cannot have a standalone `SELECT INTO` before a `WITH` block.

**Solution:** Structure the query as:
```sql
WITH CTE AS (...)
SELECT ... INTO [output1] FROM CTE
SELECT ... INTO [output2] FROM CTE WHERE ...
```

### ASA job stuck in "Failed" state cannot be stopped

**Symptom:** `az rest --method post .../stop` returns `Conflict` — job must be in `Idle, Processing, Degraded, Starting, Restarting, or Scaling` state.

**Solution:** Delete the job and recreate it. A job in `Failed` provisioning state cannot be stopped or restarted — only deleted.

### ADX output requires newer API version

**Symptom:** `az stream-analytics output create` rejects `Microsoft.Kusto/clusters/databases` as unsupported.

**Root cause:** The `stream-analytics` CLI extension uses API version `2020-03-01` which doesn't support ADX output.

**Solution:** Use `az rest` with API version `2021-10-01-preview`:
```powershell
az rest --method put --url ".../outputs/adxAnomalies?api-version=2021-10-01-preview" --body "@output.json"
```

### MSI role assignments must be verified after job recreation

**Symptom:** ASA job produces 0 output events and accumulates errors. Blob container stays empty after initial burst.

**Root cause:** Each time the ASA job is deleted and recreated, it gets a **new managed identity (principal ID)**. Previous role assignments (Storage Blob Data Contributor, ADX Ingestor) do not carry over.

**Solution:** After every ASA job recreation:
1. Get the new principal ID: `az rest --method get ... --query "identity.principalId"`
2. Grant Storage Blob Data Contributor on the storage account
3. Grant ADX Ingestor on the telemetry database
4. Wait 15+ seconds for propagation before starting the job

**How to verify:**
```powershell
az role assignment list --assignee <principalId> --query "[].roleDefinitionName" -o tsv
```

### ASA errors when ADX cluster is stopped

**Symptom:** ASA job shows 3-4 errors/min and 0 output events, even though the query is valid and blob output tests succeed.

**Root cause:** If the ADX output is configured on the ASA job but the ADX cluster is stopped, ASA periodically validates all configured outputs — including unused ones. The failed health checks count as errors and can block all output processing.

**Solution:** Always start the ADX cluster before starting the ASA job. If stopping ADX for cost savings, stop ASA first. On restart, start ADX → wait until Running → then start ASA.

**Startup order:**
1. `az rest --method post .../clusters/<name>/start` (ADX)
2. Wait for `properties.state == "Running"` (~5-10 min)
3. `az rest --method post .../streamingjobs/<name>/start` (ASA)

### AnomalyDetection_SpikeAndDip requires sustained data for anomalies

**Symptom:** `SensorAnomalies` table is empty even though ASA is processing events.

**Root cause:** The `AnomalyDetection_SpikeAndDip` function needs a baseline of normal data within its sliding window (120s for temperature, 60s for vibration) before it can flag deviations. Under steady conditions (constant room temperature, no vibration), the anomaly score stays at 0 and the `WHERE IsAnomaly = 1` filter produces no output.

**Solution:** To verify the anomaly path works:
- Touch the TMP36 sensor to spike temperature
- Tap or press the piezo disc for vibration spikes
- Check `SensorAnomalies | count` after 2–3 minutes

---

## Python Bridge

### Module name conflict with `parser` standard library

**Symptom:** `ImportError` or `AttributeError` when running the bridge.

**Root cause:** The bridge module `bridge/parser.py` shadows Python's built-in `parser` module if you run from inside the `bridge/` directory.

**Solution:** Always run from the **repository root**:
```powershell
python -m bridge.bridge    # Correct
cd bridge && python bridge.py  # WRONG — causes import conflict
```

---

## Git / GitHub

### Push fails with "Repository not found" (404)

**Symptom:** `git push` returns 404 despite the repo existing.

**Root cause:** The `GITHUB_TOKEN` environment variable (set for work account) overrides `gh` CLI's keyring-stored personal token. The work account doesn't have access to the personal repo.

**Solution:**
```powershell
$env:GITHUB_TOKEN = $null
git -c credential.helper= -c "credential.helper=!gh auth git-credential" push
```

### Git identity must be personal account

**Symptom:** Commits show the Microsoft work email in git history.

**Solution:** Before committing, always verify and set:
```powershell
git config user.email "<your-github-email>"
git config user.name "<your-github-username>"
```

---

## ADX Dashboards

### JSON import silently fails

**Symptom:** Selecting a JSON file for import does nothing — no error, no dashboard.

**Root cause:** ADX dashboard import only accepts files exported from the ADX dashboard UI itself. Custom-generated JSON (even with correct-looking schema) is silently rejected.

**Solution:** Create dashboards manually using the "Pin to dashboard" workflow:
1. Run a KQL query in the web UI
2. Click **Pin to dashboard** in the toolbar
3. Choose the dashboard and visual type

Dashboard KQL queries are documented in `dashboards/README.md`.
