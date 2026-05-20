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
3. Grant ADX Database **Ingestor** on the telemetry database
4. Grant ADX Database **Viewer** on the telemetry database (see below)
5. Wait 15+ seconds for propagation before starting the job

**How to verify:**
```powershell
az role assignment list --assignee <principalId> --query "[].roleDefinitionName" -o tsv
```

### ADX output requires BOTH Ingestor AND Viewer roles

**Symptom:** ASA shows `Forbidden (403): Principal 'aadapp=...' is not authorized to read database 'telemetry'`, with 2-4 errors/min and 0 output events to ADX. Blob output works fine.

**Root cause:** The **Ingestor** role only grants write/ingest permissions. ASA also needs to **read the table schema** to map output columns to the target table. Without **Viewer**, ASA cannot retrieve schema metadata and fails with a 403 on every attempt.

**Solution:** Grant **both** roles on the ADX database using the ASA managed identity's **application (client) ID** (not the object/principal ID):

```powershell
# 1. Get the ASA identity
az rest --method get --url ".../streamingjobs/<name>?api-version=2021-10-01-preview" --query "identity"
# Returns principalId (object ID) and tenantId

# 2. Find the app ID from the error message or Azure AD
# The error message shows: Principal 'aadapp=<APP_ID>;<TENANT_ID>'

# 3. Grant Ingestor
az rest --method put --url ".../databases/telemetry/principalAssignments/asa-ingestor?api-version=2023-08-15" \
  --body '{"properties":{"principalId":"<APP_ID>","principalType":"App","role":"Ingestor","tenantId":"<TENANT_ID>"}}'

# 4. Grant Viewer
az rest --method put --url ".../databases/telemetry/principalAssignments/asa-viewer?api-version=2023-08-15" \
  --body '{"properties":{"principalId":"<APP_ID>","principalType":"App","role":"Viewer","tenantId":"<TENANT_ID>"}}'
```

**Important:** The principal ID format differs between Azure AD and ADX:
- Azure AD / ARM uses the **object (principal) ID** (e.g., `cfedee86-...`)
- ADX principal assignments use the **application (client) ID** (e.g., `1e800cc2-...`)
- The error message reveals the app ID in the format `aadapp=<APP_ID>;<TENANT_ID>`

### ASA validates ALL configured outputs, even unused ones

**Symptom:** ASA shows errors even though the query doesn't write to a particular output.

**Root cause:** ASA periodically health-checks every configured output, regardless of whether the query's `SELECT INTO` references it. If any output has auth or connectivity issues, errors accumulate even when that output receives no data.

**Solution:** Either fix the output's permissions/connectivity, or delete the output from the job if it's not in use. There is no way to "disable" an output without removing it.

### ASA errors when ADX cluster is stopped

**Symptom:** ASA job shows 3-4 errors/min and 0 output events, even though the query is valid and blob output tests succeed.

**Root cause:** If the ADX output is configured on the ASA job but the ADX cluster is stopped, ASA periodically validates all configured outputs — including unused ones. The failed health checks count as errors and can block all output processing.

**Solution:** Always start the ADX cluster before starting the ASA job. If stopping ADX for cost savings, stop ASA first. On restart, start ADX → wait until Running → then start ASA.

**Startup order:**
1. `az rest --method post .../clusters/<name>/start` (ADX)
2. Wait for `properties.state == "Running"` (~5-10 min)
3. `az rest --method post .../streamingjobs/<name>/start` (ASA)
4. Start the Python bridge (messages must flow for ASA to process)

**Shutdown order** (reverse):
1. Stop the Python bridge
2. `az rest --method post .../streamingjobs/<name>/stop` (ASA)
3. `az rest --method post .../clusters/<name>/stop` (ADX) — saves ~$5/day on Dev/Test SKU

### AnomalyDetection_SpikeAndDip requires sustained data for anomalies

**Symptom:** `SensorAnomalies` table is empty even though ASA is processing events.

**Root cause:** The `AnomalyDetection_SpikeAndDip` function needs a baseline of normal data within its sliding window (120s for temperature, 60s for vibration) before it can flag deviations. Under steady conditions (constant room temperature, no vibration), the anomaly score stays at 0 and the `WHERE IsAnomaly = 1` filter produces no output.

**Solution:** To verify the anomaly path works:
- Touch the TMP36 sensor to spike temperature
- Tap or press the piezo disc for vibration spikes
- Check `SensorAnomalies | count` after 2–3 minutes

### ASA `JobStartTime` mode skips historical events

**Symptom:** You created a temperature spike, but `SensorAnomalies` is empty after restarting ASA.

**Root cause:** Starting ASA with `outputStartMode: "JobStartTime"` tells it to only process events arriving **after** the job starts. If the anomaly event occurred before the restart, ASA never sees it.

**Solution:** If you need to reprocess past events, use `outputStartMode: "LastOutputEventTime"` (resumes from where it left off) or `"CustomTime"` with a specific timestamp. Note that `"JobStartTime"` also means the anomaly detection function starts with no baseline — it needs ~2 minutes of steady data before it can detect deviations.

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

### Custom JSON import silently fails — use ADX-exported JSON

**Symptom:** Selecting a custom-built JSON file for import does nothing — no error, no dashboard.

**Root cause:** ADX dashboard import only accepts files exported from the ADX dashboard UI itself. Custom-generated JSON (even with correct-looking schema) is silently rejected.

**Solution:** Create the dashboard manually first (using "Pin to dashboard"), then export it via **Dashboard → Share → Export file**. The exported JSON can be re-imported on other clusters. An exported dashboard file is included at `dashboards/dashboard-Monitoring.json`.
