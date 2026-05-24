# Context Diagram — GuardianNako IoT Wearable Protection System

**Figure 1**

*Context Diagram of the GuardianNako System*

```mermaid
graph TB
    %% ─── External Entities ───────────────────────────────────────────
    Wearer["👤 Protected Person<br/><i>(Wearer)</i>"]
    Guardian["👤 Guardian / Parent<br/><i>(App User)</i>"]
    Contacts["📞 Emergency<br/>Contacts"]
    GPS["🛰️ GPS Satellites"]
    Firebase["☁️ Firebase Cloud"]

    %% ─── System ──────────────────────────────────────────────────────
    System["🛡️ GuardianNako System<br/><br/><i>ESP32 Wearable Device<br/>+ Flutter Mobile App</i>"]

    %% ─── Data Flows ──────────────────────────────────────────────────
    Wearer -->|"Movement<br/>SOS Button Press"| System
    System -->|"Status LED"| Wearer

    GPS -->|"GPS Coordinates"| System

    Guardian -->|"Credentials, Contacts<br/>Geofences, WiFi Setup<br/>Emergency Dismissal"| System
    System -->|"Live Dashboard<br/>GPS Map, Emergency Alerts<br/>Alert History"| Guardian

    System -->|"Sensor Data, Emergency State"| Firebase
    Firebase -->|"Real-time Streams<br/>Stored Data"| System

    System -->|"Phone Calls<br/>(tap-to-dial)"| Contacts
```

---

## What This Diagram Shows

The system sits between five external entities:

- **Protected Person (Wearer)** — the person being monitored. Wears the device. Their movement flows into the system; the system gives them visual feedback via an LED.
- **Guardian / Parent** — the caregiver using the mobile app. Sends configuration (contacts, geofences, WiFi credentials) to the system. Receives live monitoring data, GPS location, and emergency alerts.
- **GPS Satellites** — provide location coordinates to the wearable device.
- **Firebase Cloud** — the cloud backend. The system pushes sensor data and emergency state to Firebase; Firebase streams live data back to the mobile app.
- **Emergency Contacts** — people the guardian can call with one tap during an emergency.
