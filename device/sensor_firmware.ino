/*
 * Industrial IoT Sensor Firmware
 * Arduino Uno R3 — TMP36 (temperature) + Piezo (vibration)
 *
 * Reads both sensors and outputs JSON telemetry over serial.
 * A Python bridge on the host PC forwards this to Azure IoT Hub.
 *
 * Wiring:
 *   TMP36: VCC→5V, GND→GND, OUT→A0
 *   Piezo: one leg→A1, other leg→GND (no resistor needed for reading)
 */

const int TEMP_PIN = A0;
const int PIEZO_PIN = A1;
const unsigned long SEND_INTERVAL_MS = 1000;  // 1 reading/sec

// Unique device identifier (change per device)
const char* DEVICE_ID = "arduino-uno-001";

unsigned long lastSendTime = 0;
unsigned long sequenceNum = 0;

void setup() {
  Serial.begin(9600);
  while (!Serial) { ; }
  
  // Startup message (not JSON — bridge ignores non-JSON lines)
  Serial.println("# IoT Sensor Firmware v1.0 started");
  Serial.print("# Device: ");
  Serial.println(DEVICE_ID);
}

float readTemperatureC() {
  int raw = analogRead(TEMP_PIN);
  float voltage = raw * (5.0 / 1023.0);
  // TMP36: 10mV/°C, 500mV offset at 0°C
  return (voltage - 0.5) * 100.0;
}

int readVibration() {
  // Piezo produces voltage on impact/vibration
  // Read multiple samples over a short window to capture peaks
  int maxVal = 0;
  for (int i = 0; i < 10; i++) {
    int val = analogRead(PIEZO_PIN);
    if (val > maxVal) maxVal = val;
    delayMicroseconds(200);
  }
  return maxVal;
}

void sendTelemetry(float tempC, int vibration) {
  // Output as JSON — one line per reading
  Serial.print("{\"device_id\":\"");
  Serial.print(DEVICE_ID);
  Serial.print("\",\"seq\":");
  Serial.print(sequenceNum);
  Serial.print(",\"temperature_c\":");
  Serial.print(tempC, 2);
  Serial.print(",\"vibration_raw\":");
  Serial.print(vibration);
  Serial.println("}");
  
  sequenceNum++;
}

void loop() {
  unsigned long now = millis();
  
  if (now - lastSendTime >= SEND_INTERVAL_MS) {
    lastSendTime = now;
    
    float tempC = readTemperatureC();
    int vibration = readVibration();
    
    sendTelemetry(tempC, vibration);
  }
}
