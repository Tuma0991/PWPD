# UC06 — View Alert History

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC06 |
| **Use Case Name** | View Alert History |
| **Actor(s)** | Guardian / Parent |
| **Description** | The guardian views a chronological history of all past emergency alerts with their type, reason, time, and location. |
| **Precondition** | The guardian is logged in and a device is paired. |
| **Postcondition** | The alert history is displayed as a scrollable list, most recent first. |

**Normal Flow**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | Guardian | Navigate | Navigates to the Alerts tab. |
| 2 | System | Display | Displays a summary bar showing counts of alerts by type (SOS, fall, geofence). |
| 3 | System | Display | Shows a chronological list of past alerts. Each entry displays: the alert type with an icon, the reason or message, the date and time it occurred, and the GPS location at the time of the event. |
| 4 | System | Update | Updates the list in real time as new alerts are logged. |

**Alternative Flows**

| Step | Condition | Action Word/s | Action |
|------|-----------|--------------|--------|
| 3a | No alerts exist yet | Inform | System displays an empty state message. |
| 4a | Duplicate alert received (same event, same timestamp) | Skip | System skips the duplicate to prevent repeated entries. |

| **Includes** | UC10 — Store Persistent Data |
