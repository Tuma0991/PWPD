# UC03 — Monitor Fall Detection

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC03 |
| **Use Case Name** | Monitor Fall Detection |
| **Actor(s)** | Guardian / Parent |
| **Description** | The guardian monitors the protected person's real-time movement and sees whether a fall has been detected. |
| **Precondition** | The guardian is logged in and a device is paired. |
| **Postcondition** | The guardian sees live accelerometer data and the current fall detection state. |

**Normal Flow**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | Guardian | Navigate | Navigates to the Fall Detection tab. |
| 2 | System | Display | Displays an animated status circle: green when normal, red when a fall is detected. |
| 3 | System | Display | Shows real-time X, Y, and Z accelerometer bars with current values. |
| 4 | System | Display | Shows the computed movement magnitude for quick assessment. |
| 5 | System | Detect | If a fall is detected, the status circle turns red and a "Mark as Safe" button appears. |

**Alternative Flows**

| Step | Condition | Action Word/s | Action |
|------|-----------|--------------|--------|
| 5a | Guardian taps "Mark as Safe" | Dismiss | System clears the active emergency, saves the alert to history, and returns the status circle to green. |

| **Includes** | UC09 — Stream Sensor Data |
