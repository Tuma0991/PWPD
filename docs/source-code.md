# Source Code — Key Files

Core implementation of the Guardian IoT Wearable Protection Device. Credentials and private keys live in `secrets.h` and are intentionally excluded.

## 1. Fall Detection & Emergency — ESP32 Firmware (`guardian_firmware.ino`)

```cpp
// 100 Hz IMU sampling: read acceleration, compute magnitude, feed detector.
static void imuSample(uint32_t now) {
  if (!imuOk) { /* retry init every 30 s */ return; }

  int16_t ax, ay, az;
  mpu.getAcceleration(&ax, &ay, &az);

  float x = ax / ACCEL_LSB_PER_G;
  float y = ay / ACCEL_LSB_PER_G;
  float z = az / ACCEL_LSB_PER_G;
  float g = sqrtf(x * x + y * y + z * z);   // acceleration magnitude (g)
  lastAx = x; lastAy = y; lastAz = z;

  if (fabsf(g - 1.0f) > MOTION_DEVIATION_G) lastMotionMs = now;
  fallDetectorUpdate(g, now);
}

// Two-phase fall detection: free-fall → impact → post-impact stillness.
static void fallDetectorUpdate(float g, uint32_t now) {
  if (emergencyActive || fallPending) { fallPhase = FALL_IDLE; return; }
  if ((int32_t)(now - fallIgnoreUntil) < 0) return;

  if (fallPhase == FALL_IDLE) {
    if (g < FREEFALL_G) {
      if (freeSamples < 255) freeSamples++;
      if (freeSamples >= FREEFALL_MIN_SAMPLES) { sawFreefall = true; lastFreefallAt = now; }
    } else {
      freeSamples = 0;
    }

    if (g > IMPACT_G) {
      bool afterFreefall = sawFreefall && (now - lastFreefallAt) <= FREEFALL_TO_IMPACT_MS;
      if (afterFreefall || g > IMPACT_STRONG_G) {
        fallPhase = FALL_POST_IMPACT;
        impactAt = now;
        postSamples = 0; postActive = 0;
        sawFreefall = false; freeSamples = 0;
      }
    }
    return;
  }

  // FALL_POST_IMPACT: judge the wearer's movement after the impact.
  uint32_t t = now - impactAt;
  if (t >= POST_IMPACT_SETTLE_MS) {
    postSamples++;
    if (fabsf(g - 1.0f) > POST_ACTIVE_G) postActive++;
  }
  if (t >= POST_IMPACT_SETTLE_MS + POST_IMPACT_WINDOW_MS) {
    fallPhase = FALL_IDLE;
    bool clearlyMoving = postSamples > 0 &&
                         ((float)postActive / (float)postSamples) > POST_ACTIVE_FRACTION;
    if (clearlyMoving) {
      fallIgnoreUntil = now + 1000;      // false alarm — wearer is moving
    } else {
      beginFallCancelWindow(now);        // 15 s "I'm OK" cancel window
    }
  }
}

// Confirm an emergency (SOS button or confirmed fall) and wake the network task.
static void triggerEmergency(const char* reason, bool fromFall, uint32_t now) {
  if (emergencyActive) return;

  portENTER_CRITICAL(&alertMux);
  strlcpy(alertReason, reason, sizeof(alertReason));
  fallFlag          = fromFall;
  alertDelivered    = false;
  emergencyStartMs  = now;
  emergencyActive   = true;
  alertPending      = true;
  portEXIT_CRITICAL(&alertMux);

  if (netTaskHandle) xTaskNotifyGive(netTaskHandle);   // wake the network task now
}

// Upload the emergency to Firebase Realtime Database.
static bool sendAlert() {
  GpsFix fix = getFix();
  // reason/fall are copied from the shared alert state under a mutex.

  StaticJsonDocument<768> doc;
  doc["emergency/active"] = true;
  doc["emergency/reason"] = reason;
  doc["emergency/triggeredAt"][".sv"] = "timestamp";
  doc["sensors/fallDetected"] = fall;
  if (fix.valid) {
    doc["emergency/lat"] = fix.lat;
    doc["emergency/lng"] = fix.lng;
  }
  String body;
  serializeJson(doc, body);
  return dbPatchDevice(body);
}

// POST the event to the Netlify function, which sends FCM push + SMS.
static void notifyEmergencyWebhook() {
  StaticJsonDocument<384> doc;
  doc["kind"]     = "emergency";
  doc["deviceId"] = deviceId;
  doc["reason"]   = reason;
  doc["type"]     = fall ? "fall" : "sos";
  if (fix.valid) { doc["lat"] = fix.lat; doc["lng"] = fix.lng; }

  String body;
  serializeJson(doc, body);
  notifyWebhook("emergency", body);   // HTTP POST to NOTIFY_WEBHOOK_URL
}
```

## 2. FCM Registration & Alert Handling — Flutter

```dart
// firebase_service.dart — register this phone to receive push for a device.
Future<void> registerFcmToken(String deviceId) async {
  final userId = currentUser?.uid;
  if (userId == null || deviceId.isEmpty) return;

  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  await _rtdb.ref('devices/$deviceId/fcmTokens/$userId').set({
    'token': token,
    'platform': 'android',
    'registeredAt': ServerValue.timestamp,
  });
}

// firebase_service.dart — listen to the device's emergency field.
Stream<Map<String, dynamic>> listenToEmergencyAlert(String deviceId) {
  final ref = _rtdb.ref('devices/$deviceId/emergency');
  return ref.onValue.map((event) =>
      Map<String, dynamic>.from(event.snapshot.value as Map? ?? {}));
}

// main.dart — request permission and wire up FCM handlers.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
  FirebaseMessaging.onMessage.listen(_onForegroundMessage);
  messaging.onTokenRefresh.listen((_) =>
      FirebaseService().registerFcmTokenForAllDevices());

  runApp(const GuardianApp());
}

// home_screen.dart — react to an emergency alert from the device.
void _onEmergencyEvent(Map<String, dynamic> event) {
  if (!mounted) return;
  final isActive = event['active'] == true;
  final reason = event['reason'] as String? ?? '';

  if (!isActive) {
    _stopAlertSound();                 // cleared / "Mark as Safe"
    return;
  }

  if (reason.isEmpty || _emergencyDialogShown) return;
  _emergencyDialogShown = true;
  _startAlertSound();
  _showEmergencyDialog(reason);
}
```

## 3. Push Notification Function — Netlify (`notify.js`)

```javascript
// Send an FCM push to every registered guardian token for a device.
async function sendPush(deviceId, title, body, data) {
  const tokensSnap = await app()
    .database()
    .ref(`/devices/${deviceId}/fcmTokens`)
    .once("value");
  const tokens = tokensSnap.val();
  if (!tokens) return;

  const validTokens = Object.values(tokens)
    .map((d) => d.token)
    .filter(Boolean);
  if (validTokens.length === 0) return;

  await Promise.allSettled(
    validTokens.map(async (token) => {
      try {
        await app().messaging().send({
          token,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: {
              channelId: "geofence_alerts",
              sound: "default",
              priority: "high",
              visibility: "public",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          apns: {
            payload: {
              aps: { sound: "default", badge: 1, alert: { title, body } },
            },
          },
        });
      } catch (err) {
        console.error("FCM error:", err.message);
      }
    }),
  );
}

// Entry point — ESP32 POSTs { kind, deviceId, ... } here.
exports.handler = async (event) => {
  const payload = JSON.parse(event.body || "{}");
  const { kind, deviceId } = payload;

  if (kind === "emergency") {
    // push + SMS to emergency contacts
    await sendPush(deviceId, title, body, { type: isFall ? "fall" : "sos", deviceId });
  } else if (kind === "geofence") {
    await sendPush(deviceId, title, body, { type: `geofence_${type}`, deviceId });
  }
  return { statusCode: 200, body: JSON.stringify({ ok: true }) };
};
```
