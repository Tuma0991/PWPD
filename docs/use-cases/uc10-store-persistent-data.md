# UC10 — Store Persistent Data

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC10 |
| **Use Case Name** | Store Persistent Data |
| **Actor(s)** | System (supporting — Firebase Cloud Firestore) |
| **Description** | The persistent storage layer that keeps user profiles, contacts, geofence definitions, and alert history durably saved and available for queries. |
| **Precondition** | The guardian is authenticated. |
| **Postcondition** | Data is saved permanently and available to the app whenever needed. |

**Normal Flow**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | App | Request | Sends a save request (new contact, geofence change, alert log, device registration). |
| 2 | System | Store | Stores the data in the appropriate collection under the guardian's account. |
| 3 | App | Confirm | Receives confirmation that the data was saved. |
| 4 | App | Receive | If subscribed to live updates for this data, receives the change automatically. |

**Data Stored**

| Collection | Contents |
|-----------|----------|
| User Profile | Guardian's name, email, linked device ID, account creation date |
| Contacts | Each contact's name, phone number, relationship, and emergency priority flag |
| Geofence Definitions | Each zone's name, polygon boundary vertices, enabled/disabled status, creation and modification dates |
| Alert History | Each alert's type (SOS/fall/emergency), reason, message, device ID, timestamp, and GPS location |

| **Included by** | UC04 (Manage Geofences), UC05 (Manage Contacts), UC06 (View Alert History) |
