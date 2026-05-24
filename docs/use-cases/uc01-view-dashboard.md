# UC01 — View Dashboard

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC01 |
| **Use Case Name** | View Dashboard |
| **Actor(s)** | Guardian / Parent |
| **Description** | The guardian opens the app and sees a live overview of the protected person's status — sensor data, GPS coordinates, movement, fall detection, and device connectivity. |
| **Precondition** | The guardian is logged in and a device has been paired (UC04 includes device registration). |
| **Postcondition** | The dashboard continuously displays real-time data from the wearable device. |

**Normal Flow**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | Guardian | Open | Opens the app. The Dashboard tab loads by default. |
| 2 | System | Retrieve | Retrieves the guardian's linked device and begins receiving live sensor data. |
| 3 | System | Display | Displays status cards showing: current GPS coordinates, accelerometer readings, movement activity, fall detection status, and whether the device is online. |
| 4 | System | Update | Updates all cards in real time as new sensor data arrives from the device. |
| 5 | System | Alert | If an active emergency is detected, a red emergency banner appears at the top of the dashboard. The guardian can dismiss it directly from this screen. |

**Alternative Flows**

| Step | Condition | Action Word/s | Action |
|------|-----------|--------------|--------|
| 2a | No device has been paired yet | Prompt | System displays a "Set Up Device" prompt instead of the dashboard. |
| 4a | Device stops sending data for more than 10 seconds | Flag | System marks the device as offline and updates the connectivity card. |

| **Includes** | UC09 — Stream Sensor Data |
