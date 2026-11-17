# Guardian Firmware v2.0.0 — Change Documentation

This document explains what changed from the original `guardian_firmware.ino` (v1.0.0), why, how the new firmware behaves, and what to do before flashing it.

**Files delivered**

| File | Purpose |
|---|---|
| `guardian_firmware.ino` | The new firmware (organised in 17 numbered sections) |
| `secrets.h` | Private settings template (Firebase URL, auth, optional BLE PIN). Must sit next to the `.ino`. |
| `CHANGES.md` | This document |

---

## 1. Verification status (please read)

| Checked | How |
|---|---|
| Code compiles cleanly (`-Wall -Wextra`, no warnings) | Syntax-checked on a PC against the **real** ArduinoJson 6.21.5 and TinyGPS++ sources, with stubs for ESP32-specific headers. Both authentication modes and `LOG_ENABLED 0` were checked. |
| Fall-detector, geofence and GPS-time logic behave as designed | 18 automated host tests, all passing (list in section 12). |

| **Not** checked | Why it matters |
|---|---|
| Compilation with the real ESP32 Arduino core 3.x | I had no ESP32 toolchain here. WiFiMulti / BLE / HTTPClient signatures differ slightly between core versions, so expect that **a small compile fix may be needed**. |
| Behaviour on real hardware | The GPS stop/start command, MPU6050 gyro standby, WiFi modem sleep and the fall thresholds all need to be tried on the device (checklist in section 12). |
| Battery life | Figures in section 5 are estimates, not measurements. |

---

## 2. Summary of changes

| # | Problem in v1.0.0 | Fix in v2.0.0 |
|---|---|---|
| 1 | Accelerometer sampled once every 2 s, so real impacts were almost never seen | IMU sampled at **100 Hz** in the sensing loop, independent of any network activity |
| 2 | MPU6050 left at ±2 g, so a 2.5 g threshold could never be measured | Range set to **±8 g** (divisor 4096) |
| 3 | A single magnitude spike counted as a fall | **Free-fall → impact → post-impact check**, plus a strong-impact path so falls without free-fall are not missed |
| 4 | Fall alert fired instantly, no chance to cancel | **15 s "I'm OK" window** (LED flashes; hold the button 2 s to cancel; short press sends now) |
| 5 | About 8 separate HTTPS calls every 2 s blocked the loop; the button could be missed | All networking moved to a **separate FreeRTOS task on core 0**; writes are **batched into one request**; SOS button uses an **interrupt** |
| 6 | Alert marked "sent" even if Firebase failed, never retried | Alert stays pending and is **retried until delivered**; LED shows "not delivered yet" |
| 7 | GPS on 100% of the time; data pushed constantly | **Event-driven design**: GPS duty-cycled, uploads only on events + slow heartbeat (section 4) |
| 8 | Device stuck in BLE mode forever if the router was briefly down | Boots into normal mode and **retries WiFi in the background** with back-off; BLE only when no WiFi is saved or fresh credentials fail |
| 9 | No way back into setup once WiFi was saved | **Hold the button 5 s while powering up** to erase saved WiFi and reopen setup |
| 10 | Only one WiFi network | Up to **3 saved networks** (e.g. home + caregiver phone hotspot); strongest is chosen |
| 11 | BLE stopped advertising after a phone disconnect | Advertising **restarts on disconnect** |
| 12 | BLE open indefinitely; WiFi password printed to serial | BLE closes after **5 min**; password is **never logged**; optional PIN check |
| 13 | Open (no-password) WiFi rejected | Empty password **allowed** |
| 14 | Firebase secret hard-coded in the sketch; deprecated Firebase library | Settings moved to **`secrets.h`**; optional **email/password sign-in**; Firebase library replaced by a small **REST client** |
| 15 | Geofence parsing used `strcpy` (buffer overflow risk) | `strlcpy` with bounds; vertex and fence limits enforced |
| 16 | Geofences only loaded once; push-id (object) format returned 0 fences | Refreshed every 10 min or on command; **array and object formats both accepted** |
| 17 | GPS jitter at a boundary caused spam events; stale fixes used; false "entered" at boot | **2-fix confirmation**, fix freshness + satellite check, first fix learns state silently; refresh keeps state |
| 18 | Violation keys used `millis()` (overwritten after reboot) | Written with **push IDs** plus GPS-time `eventUtc` |
| 19 | Lat/lng stored as `float` (~1 m resolution) | Stored as **double** |
| 20 | MPU6050 failure only printed once | **Fault detection**, automatic re-init every 30 s, `imuOk` reported to the app |
| 21 | Serial prints could block when no USB host is attached | `Serial.setTxTimeoutMs(0)`; logging can be switched off entirely (`LOG_ENABLED`) |
| 22 | No recovery if networking silently stalls | Reboot after 1 h with WiFi up but nothing delivered (never during an emergency) |

---

## 3. Architecture

```
┌───────────────── loop()  (core 1, never blocked by the network) ─────────────────┐
│ GPS bytes → TinyGPS++   │ button (interrupt + polling)  │ IMU @100 Hz            │
│ fall detector           │ power-mode decision           │ GPS duty-cycle logic   │
│ geofence evaluation     │ status LED                    │                        │
└───────────────┬──────────────────────────────────────────────────────────────────┘
                │  flags + small queues (alert, geofence events, location)
┌───────────────▼────── netTask  (core 0) ─────────────────────────────────────────┐
│ WiFi reconnect/back-off │ Firebase REST (keep-alive) │ alert retry until delivered│
│ heartbeat │ location report │ geofence events │ command poll │ geofence refresh   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

The network task sleeps until there is something to do (a notification from the sensing loop wakes it immediately for alerts). The CPU runs at **80 MHz** and is raised to **160 MHz only during network bursts** (TLS handshakes are CPU-heavy, so finishing them faster keeps the radio on for less time).

### Power modes

| Mode | When | GPS | Network |
|---|---|---|---|
| **ACTIVE** | Wearer is moving | Short fix every 60 s (5 min if no geofences) | Event-only + heartbeat every 2 min |
| **RESTING** | No motion for 2 min | Short fix every 15 min | Heartbeat every 5 min |
| **EMERGENCY** | SOS, confirmed fall, or fall window open | Continuous for the first 10 min, then a fix every 30 s | Fast polling and location updates until cleared |

The **IMU is sampled at 100 Hz in every mode**, so a fall is never missed because the device was "resting".

---

## 4. Event-driven GPS

The receiver is switched off between short sessions using the u-blox `UBX-CFG-RST` "controlled GNSS stop/start" command over the TX wire you already have. **No hardware changes.**

- **Session starts when:** the schedule says so, the app sends "locate now", a fall window opens, or an emergency begins.
- **Session ends** as soon as a fix has settled (3 s after the first valid fix). Because the clock and satellite data are kept, restarts are normally fast hot starts.
- **Geofences are checked only when a new fix arrives.** If a fix suggests a boundary was crossed, GPS stays on for one more fix 5 s later to confirm before anything is uploaded.
- **Position is uploaded only if it moved ≥ 25 m**, on "locate now", or in the heartbeat.
- **Indoors / no sky view:** failed sessions back off (60 s → 2 min → 4 min → 8 min, capped at 20 min) so the GPS does not burn power searching.
- **Emergency:** the alert is sent immediately with the last known position (age included as `locAgeS`); the GPS is already warming up and fresh positions follow every 10 s.
- **Safety net:** after the first stop the firmware checks that fixes really stopped. If the module ignores the command, duty cycling disables itself and the GPS simply stays on (as in v1). Set `GPS_DUTY_CYCLE = false` to force that.

---

## 5. Expected power impact (estimates only)

| Item | v1.0.0 | v2.0.0 |
|---|---|---|
| WiFi radio | Busy almost continuously (~8 HTTPS writes every 2 s) | Associated in modem sleep; short bursts only |
| GPS | On 100% (~25–30 mA while tracking) | On a few seconds per minute when moving, rarely when resting |
| CPU | 240 MHz | 80 MHz (160 MHz in bursts) |
| MPU6050 gyro | On (~3 mA) | Standby (accelerometer only) |
| Rough average | ~120–150 mA | ~20–40 mA typical, lower when mostly resting |

These are ballpark figures from typical datasheet values. **Measure your own unit** (USB power meter or INA219) and tune the intervals in section 1 of the sketch.

---

## 6. Behaviour reference

### Button

| Action | Result |
|---|---|
| Press (normal) | SOS sent **immediately** |
| Press while an emergency is active | 4 quick blinks (acknowledged, nothing re-sent) |
| Fall window open — short press | Alert sent now |
| Fall window open — **hold 2 s** | "I'm OK": fall alert cancelled |
| Hold 5 s **while powering up** | Erase saved WiFi, open BLE setup |
| Press while in setup-idle (BLE closed, no WiFi saved) | Reopen BLE setup |

### LED

| Pattern | Meaning |
|---|---|
| 100 ms blink every 4 s | Running, WiFi connected |
| Double blink every 4 s | Running, **no WiFi** (events are queued) |
| 100 ms blink every 2 s | BLE setup mode |
| Fast flashing | Possible fall — hold button 2 s to cancel |
| Double blink every 1 s | **Alert not delivered yet** (still retrying) |
| 150 ms blink every 2 s | Alert delivered, help requested |
| ~4 quick blinks | Button press acknowledged |

### Fall detection (defaults)

1. Magnitude below **0.4 g** for ≥ 50 ms (free-fall), then above **2.5 g** within 800 ms; **or** a single impact above **3.5 g**.
2. 0.5 s later, the next 2 s are examined. If the wearer is clearly moving normally (> 70 % of samples deviate more than 0.3 g from 1 g) the event is discarded.
3. Otherwise the 15 s cancel window opens; if not cancelled, the alert is sent.
4. Impacts within 3 s of an SOS press are ignored (button jolt), and there is a 5 s cooldown after each event.

---

## 7. Firebase data model

Existing paths the app already reads are kept. **New or changed items are marked.**

**Written by the device**

| Path | Content | When |
|---|---|---|
| `emergency/active, reason, triggeredAt, lat, lng` | As before | Alert |
| `emergency/locAgeS`, `emergency/eventUtc` | **New** — age of the position in seconds; GPS time | Alert + updates |
| `sensors/fallDetected` | `true` from a fall alert until the app clears the emergency (**changed**: no longer a 5 s pulse) | Alert / clear |
| `sensors/gps/lat, lng` | Last fix | On movement ≥ 25 m, heartbeat, locate-now, emergency |
| `sensors/gps/fixUtc` | **New** — GPS time of the fix | With GPS |
| `sensors/online`, `sensors/timestamp` | As before (server time) | Heartbeat and events |
| `sensors/accelerometer/x,y,z` | **Changed** — snapshot with each heartbeat, no longer live | Heartbeat |
| `sensors/mode`, `hbIntervalS`, `rssi`, `imuOk`, `firmware` | **New** — diagnostics | Heartbeat |
| `geofence_violations/<pushId>` | `geofenceId, name, type, lat, lng, distance, timestamp` + **`eventUtc`** | Enter/exit (**changed**: push IDs instead of `millis()`) |

**Read by the device**

| Path | Content |
|---|---|
| `geofences` | Array **or** push-id object of `{id, name, vertices:[{lat,lng}]}` |
| `emergency/active` | Device treats `false` as "cleared from app" (unchanged behaviour) |
| `commands/locateNow` | **New, optional** — set `true` to request a fresh fix; the device resets it to `false` |
| `commands/refreshGeofences` | **New, optional** — set `true` to reload geofences now |

### Changes needed in the app

1. **Offline detection.** The device no longer sends data every 2 s. Treat it as offline when `sensors/timestamp` is older than **2.5 × `hbIntervalS`** (about 5 min while active, 12.5 min while resting). Do not rely on `sensors/online`, which stays `true` if the device dies.
2. **Live tracking.** The map shows the last reported position. For an on-demand position, write `devices/<id>/commands/locateNow = true` (response time is up to the command-poll interval: 30 s active / 60 s resting).
3. **Accelerometer display**, if any, now updates only with heartbeats.
4. **Optional:** show `sensors/imuOk = false` as a "sensor fault" warning, and `emergency/locAgeS` as "position is N seconds old".
5. **Optional:** if you enable `PROVISIONING_PIN`, send `"pin"` in the BLE WiFi JSON. Multiple WiFi networks are added by sending the same JSON again with another SSID.

---

## 8. Setup instructions

1. Install libraries: **TinyGPSPlus**, **MPU6050 (Electronic Cats)**, **ArduinoJson** (6.x recommended). Remove the old *Firebase ESP32 Client* dependency.
2. Put `guardian_firmware.ino` and `secrets.h` in the **same sketch folder**.
3. **Rotate the database secret.** The old one was in the file you shared. Create a new one in Firebase console → Project settings → Service accounts → Database secrets, delete the old one, and paste the new value in `secrets.h`. Add `secrets.h` to `.gitignore`.
4. Board: *ESP32S3 Dev Module*, esp32 core 3.x, USB CDC On Boot **Enabled**.
5. Upload. Open the serial monitor at 115200 to watch the `[STATUS]` line every 30 s.
6. Existing devices keep their device ID and their saved WiFi (migrated automatically from the v1 storage keys).

### Recommended: switch to per-device sign-in

1. Firebase console → Authentication → enable *Email/Password* → create a user for the device.
2. In `secrets.h`, comment out `FIREBASE_AUTH` and enable the three `FIREBASE_API_KEY / EMAIL / PASSWORD` lines.
3. Restrict the database rules to that account (merge into your existing rules rather than replacing them):

```json
{
  "rules": {
    "devices": {
      "$deviceId": {
        ".read":  "auth != null",
        ".write": "auth != null && auth.token.email == 'guardian@yourdomain.com'"
      }
    }
  }
}
```

Note: one account shared by all units is better than the admin secret, but it is not true per-device isolation. For that, each unit needs its own account, which means passing credentials during BLE setup (a future app change).

---

## 9. Tuning guide

Everything is in **section 1** of the sketch.

| Goal | Setting |
|---|---|
| More sensitive / fewer false falls | `IMPACT_G`, `IMPACT_STRONG_G`, `POST_ACTIVE_FRACTION` |
| Longer / shorter "I'm OK" window | `FALL_CANCEL_WINDOW_MS` |
| Faster geofence detection | `GPS_ACTIVE_INTERVAL_MS` (smaller = faster, more battery) |
| Longer battery life | Raise `GPS_ACTIVE_INTERVAL_MS`, `HEARTBEAT_*`, `COMMAND_POLL_*`; set `ENABLE_COMMAND_POLL = false` if the app does not use "locate now" |
| Faster "locate now" | Lower `COMMAND_POLL_ACTIVE_MS` / `COMMAND_POLL_RESTING_MS` |
| Always-on GPS | `GPS_DUTY_CYCLE = false` |
| Quieter production build | `LOG_ENABLED = 0` |

**Fall thresholds must be tuned on the real wearer's wrist.** Wrist-worn devices see large spikes from hand slams and arm swings. Use the `[FALL]` serial log to see what triggers, then adjust.

---

## 10. Known limitations and trade-offs

- **Alert latency** is typically 1–3 s when WiFi is connected; a TLS handshake after an idle period adds time. A fall adds the 15 s cancel window by design.
- **WiFi only.** Away from a saved network (including a phone hotspot) nothing can be uploaded. Events are queued (geofence events up to 8; the alert is retained) and sent when WiFi returns; the double-blink LED shows the offline state. A cellular module or BLE relay through the phone would be needed for true roaming protection.
- **TLS certificates are not verified** (`setInsecure()`): traffic is encrypted but the server's identity is not checked. Adding a root-certificate check is recommended before production use.
- **Event reboot caveat:** if the device reboots mid-emergency it does not resume it; the SOS can be pressed again.
- **First fix after a long GPS stop** (more than a few hours) can take 30–60 s instead of a few seconds.
- **Indoor GPS** will often fail; the device then reports the last known position (with its age) and backs off to save power.
- **Command polling** costs a small amount of power (a GET every 30/60 s). Disable it if "locate now" is not used.
- **Gyro standby** uses the internal MPU6050 oscillator. If acceleration readings look wrong, set `IMU_GYRO_STANDBY = false`.

---

## 11. Not changed

Pins, BLE service/characteristic UUIDs, BLE JSON format (`ssid` / `password`), device-ID format (`guardian_<mac>`), BLE name (`Guardian_XXXX`), and the Firebase paths listed as unchanged in section 7.

---

## 12. Test checklist

**Automated host tests (passed):** free-fall + impact + still opens the cancel window · strong impact alone detected · moderate bump ignored · impact followed by vigorous movement discarded · resting noise never triggers · impact right after SOS ignored · geofence array format parses · push-id object format parses · null / short polygons skipped · invalid JSON keeps old list · first fix learns state silently · single outside fix does not log · bounce back cancels pending exit · two outside fixes log exactly one exit · refresh keeps state · GPS date/time → correct Unix time · distance calculation.

**To verify on the device:**

1. Boot with no WiFi saved → BLE setup works; provision from the app; device reboots and connects.
2. Wrong password → device returns to setup mode.
3. Hold the button 5 s at power-up → saved WiFi erased.
4. Quick SOS tap while the loop is busy → alert still arrives; LED shows "sent".
5. Disconnect the router, press SOS → double-blink LED; reconnect → alert is delivered.
6. Drop-test onto a soft surface → cancel window opens; hold 2 s cancels; waiting sends the alert.
7. Walk with the device → no false alerts; slam the wrist onto a table → see what `[FALL]` logs.
8. Serial shows `[GPS] Duty cycling verified`. If it says "not supported", the GPS module ignores the stop command.
9. Leave the device still for 2+ minutes → `[MODE] active -> resting`; pick it up → back to active.
10. Cross a geofence boundary → exactly one event; check `eventUtc` and push-ID keys in Firebase.
11. App sets `commands/locateNow = true` → fresh position appears and the flag resets.
12. Measure current in resting, active and emergency modes and adjust intervals.
