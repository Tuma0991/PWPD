# UC04 — Manage Geofences

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC04 |
| **Use Case Name** | Manage Geofences |
| **Actor(s)** | Guardian / Parent |
| **Description** | The guardian creates and manages virtual safe zones on a map. The system monitors whether the protected person enters or leaves these zones. |
| **Precondition** | The guardian is logged in and a device is paired. |
| **Postcondition** | Geofence changes are saved and automatically synced to the device for enforcement. |

**Normal Flow — Viewing**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | Guardian | Navigate | Navigates to the Geofences tab. |
| 2 | System | Display | Displays the list of saved geofences, each with a name and an on/off toggle. |
| 3 | System | Display | Shows any recent geofence violations (entered or exited events) below the list. |

**Normal Flow — Creating**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 4 | Guardian | Initiate | Taps "Add Geofence" and draws a boundary on the map by tapping points. |
| 5 | Guardian | Enter | Enters a name for the zone (e.g., "Home", "School") and taps save. |
| 6 | System | Validate | Validates the boundary (must have at least 3 points) and saves it. |
| 7 | System | Sync | Collects all enabled geofences, converts each polygon to a simplified format for the device, and sends the list to the wearable so it can enforce the zones. |

**Normal Flow — Editing or Deleting**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 8 | Guardian | Modify | Selects an existing geofence, modifies the boundary or name, and saves — or taps delete and confirms. |
| 9 | System | Update | Updates or removes the geofence and re-syncs the updated list to the device. |

**Normal Flow — Device Enforcement**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 10 | ESP32 | Enforce | Receives the synced geofence list and checks for enter/exit violations every 30 seconds. |

**Alternative Flows**

| Step | Condition | Action Word/s | Action |
|------|-----------|--------------|--------|
| 6a | Boundary has fewer than 3 points | Reject | System shows a validation error and asks the guardian to add more points. |
| 7a | No geofences are enabled | Clear | System sends an empty list, and the device stops checking violations. |
| 9a | Guardian toggles a geofence off | Disable | The zone is kept but disabled. It is removed from the device sync list until re-enabled. |

| **Includes** | UC10 — Store Persistent Data |
