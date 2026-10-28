# Gap of the Problem — GuardianNako IoT Wearable Protection System

## Problem

- Caregivers of elderly, children, and at-risk individuals need to know **where** their loved one is, **if** they are in danger, and be **alerted instantly** when something goes wrong
- Existing safety solutions are either too expensive, too limited, or too technical — no single product covers all three needs affordably

---

## What Exists & Why It Falls Short

- **Medical alert services** (Life Alert, Medical Guardian) — $30–60/month, landline-bound, no GPS, no geofencing, call-center dependent
- **Smartwatches** (Apple Watch, Galaxy Watch) — $300–800 + cellular plan, daily charging, confusing UI for elderly/children, no polygonal geofencing
- **GPS trackers** (Jiobit, AngelSense, Tile) — location only, no fall detection, no SOS button, no multi-contact alerting, proprietary subscription required
- **Smart home sensors** — indoor only, privacy-invasive, useless once the person steps outside
- **DIY/research prototypes** — serial monitor output, no mobile app, no user accounts, no alert history, no BLE setup wizard, manual code edits for WiFi

---

## Six Gaps

- **Affordability** — No solution delivers fall detection + GPS + geofencing + alerting at a one-time cost under $30 with zero subscription
- **Integration** — Caregivers must juggle multiple products and apps; no single unified hardware-software platform exists
- **Notification** — Existing systems notify through one channel only; no simultaneous push notification + SMS cascade to multiple emergency contacts
- **Geofence management** — Commercial products offer only circular radius zones; no freehand-drawn polygonal geofences with device-side enforcement
- **Usability** — DIY prototypes require technical skills to configure; no guided BLE provisioning or intuitive mobile interface for non-technical caregivers
- **Data persistence** — Prototypes stream ephemeral data with no alert history, no contact database, no user authentication — preventing incident review

---

## How GuardianNako Bridges Each Gap

- **Affordability** — BOM under $15 (ESP32-S3 + MPU6050 + GT-U8 GPS + button + LED). Free Firebase Spark tier, OpenStreetMap tiles, email-to-SMS gateways. Zero recurring fees
- **Integration** — One wearable + one app delivers: automated fall detection (2.5g threshold), live GPS map, polygonal geofence drawing and enforcement, SOS button, emergency contact management with tap-to-dial, push + SMS alerting, and persistent alert history
- **Notification** — Three-channel cascade: FCM push notification to guardian phone, email-to-SMS via carrier gateways to all emergency contacts, Firestore alert log for later review, with 5-minute rate limiting
- **Geofence management** — Guardians draw polygonal safe zones on OpenStreetMap. Full polygon vertices synced to ESP32 via RTDB. Device-side point-in-polygon ray-casting enforcement every 30 seconds — works even during WiFi gaps
- **Usability** — BLE provisioning wizard scans, connects, and configures WiFi in-app. Material 3 UI with color-coded status cards, animated sensor bars, glanceable indicators. No code or terminal required
- **Data persistence** — Firebase Auth secures per-user accounts. Firestore stores contacts, geofence definitions, and timestamped alert history. RTDB handles live sensor streams. All events queryable and auditable

---

## Summary

- Caregivers need location awareness, incident detection, and instant notification in one affordable system
- Existing solutions are fragmented across five categories, each with critical shortcomings
- Six gaps identified: affordability, integration, notification, geofencing, usability, data persistence
- GuardianNako closes all six with a $15 ESP32 wearable + Flutter app + Firebase backend
- Key differentiators: device-side polygon enforcement, free multi-channel alerting (push + SMS), guided BLE setup, authenticated persistent storage
