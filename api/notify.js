// Vercel Function — Guardian alert notifications (FCM push + SMS).
//
// Runs on the free Firebase Spark plan + free Vercel Hobby tier.
//
// The ESP32 POSTs a JSON body here when an emergency or geofence event fires:
//   emergency: { kind, deviceId, reason, type, lat, lng }
//   geofence:  { kind, deviceId, type, name, geofenceId, lat, lng }
//
// Required env vars (set in Vercel > Project > Settings > Environment Variables):
//   FIREBASE_SERVICE_ACCOUNT  full service-account JSON (single line or multiline)
//   FIREBASE_DATABASE_URL     e.g. https://<project>-default-rtdb.firebaseio.com
//   TEXTBEE_API_KEY           your TextBee API key (textbee.dev dashboard)
//   TEXTBEE_DEVICE_ID         ID of the registered Android phone that sends the SMS

const admin = require("firebase-admin");

// ─── Rate limiting ──────────────────────────────────────────────────────────
const SMS_COOLDOWN_MS = 5 * 60 * 1000;

let _app = null;
function app() {
  if (_app) return _app;
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT env var is not set");
  }
  _app = admin.apps.length
    ? admin.app()
    : admin.initializeApp({
        credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)),
        databaseURL: process.env.FIREBASE_DATABASE_URL,
      });
  return _app;
}

// ─── SMS helpers ────────────────────────────────────────────────────────────

async function isInCooldown(deviceId, contactId) {
  const snap = await app()
    .database()
    .ref(`/devices/${deviceId}/smsCooldowns/${contactId}`)
    .once("value");
  const lastSent = snap.val();
  if (!lastSent) return false;
  return Date.now() - lastSent < SMS_COOLDOWN_MS;
}

async function setCooldown(deviceId, contactId) {
  await app()
    .database()
    .ref(`/devices/${deviceId}/smsCooldowns/${contactId}`)
    .set(Date.now());
}

// Normalizes a PH phone number to digits-only 639XXXXXXXXX (sendSms adds the "+").
// Handles 09…, 63…, +63… and bare 9… inputs.
function toPHNumber(phone) {
  let digits = String(phone).replace(/\D/g, "");
  if (digits.startsWith("0")) digits = "63" + digits.slice(1);
  if (digits.length === 10 && digits.startsWith("9")) digits = "63" + digits;
  return digits;
}

// Builds a Google Maps link from lat/lng. Returns "" when the coordinates are
// missing, non-numeric, or 0,0 (typical of a device with no GPS fix yet).
function mapsLink(lat, lng) {
  const la = parseFloat(lat);
  const ln = parseFloat(lng);
  if (!Number.isFinite(la) || !Number.isFinite(ln)) return "";
  if (la === 0 && ln === 0) return "";
  return `https://maps.google.com/?q=${la},${ln}`;
}

async function sendSms(phone, _carrier, body) {
  const digits = toPHNumber(phone);
  if (!digits.startsWith("63")) {
    console.warn(`Invalid PH number "${phone}" — skipping SMS`);
    return false;
  }

  const apiKey = process.env.TEXTBEE_API_KEY;
  const deviceId = process.env.TEXTBEE_DEVICE_ID;
  if (!apiKey || !deviceId) {
    console.error("TEXTBEE_API_KEY / TEXTBEE_DEVICE_ID env var is not set — skipping SMS");
    return false;
  }

  const url = `https://api.textbee.dev/api/v1/gateway/devices/${deviceId}/send-sms`;
  const payload = JSON.stringify({ recipients: ["+" + digits], message: body });

  // "fetch failed" is a network-level error (connection dropped / timed out),
  // not a rejection by TextBee. Retry transient failures a couple of times.
  const MAX_ATTEMPTS = 3;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-api-key": apiKey },
        body: payload,
        signal: AbortSignal.timeout(8000),
      });
      const raw = await res.text();
      if (res.ok) {
        console.log(`SMS queued to +${digits} (TextBee, attempt ${attempt})`);
        return true;
      }
      console.error(`TextBee failed for +${digits}: HTTP ${res.status} — ${raw}`);
      // Only 429 and 5xx are worth retrying; 400/401 need a config fix.
      if (res.status !== 429 && res.status < 500) return false;
    } catch (err) {
      const cause = err.cause ? ` (${err.cause.code || err.cause.message})` : "";
      console.error(`TextBee attempt ${attempt} failed for +${digits}: ${err.message}${cause}`);
    }
    if (attempt < MAX_ATTEMPTS) await new Promise((r) => setTimeout(r, 1000 * attempt));
  }
  return false;
}

async function getEmergencyContacts(deviceId) {
  const ownerSnap = await app()
    .database()
    .ref(`/devices/${deviceId}/owner`)
    .once("value");
  const ownerId = ownerSnap.val();
  if (!ownerId) {
    console.warn(`No owner found for device ${deviceId}`);
    return [];
  }

  const contactsSnap = await app()
    .firestore()
    .collection(`users/${ownerId}/contacts`)
    .where("isEmergencyContact", "==", true)
    .get();

  const contacts = [];
  contactsSnap.forEach((doc) => {
    const data = doc.data();
    if (data.phone) {
      contacts.push({
        id: doc.id,
        name: data.name || "Contact",
        phone: data.phone,
        carrier: data.carrier || "",
      });
    }
  });
  return contacts;
}

// Resolves the owner's chosen device name (or null if not set).
async function getDeviceName(deviceId) {
  try {
    const ownerSnap = await app()
      .database()
      .ref(`/devices/${deviceId}/owner`)
      .once("value");
    const ownerId = ownerSnap.val();
    if (!ownerId) return null;

    const devDoc = await app()
      .firestore()
      .collection("users")
      .doc(ownerId)
      .collection("devices")
      .doc(deviceId)
      .get();
    return devDoc.exists ? devDoc.data().deviceName : null;
  } catch (err) {
    console.error("getDeviceName error:", err.message);
    return null;
  }
}

async function notifyEmergencyContacts(deviceId, alertBody) {
  const contacts = await getEmergencyContacts(deviceId);
  if (contacts.length === 0) {
    console.log(`No emergency contacts for device ${deviceId}`);
    return;
  }

  let sent = 0;
  for (const contact of contacts) {
    if (await isInCooldown(deviceId, contact.id)) {
      console.log(`SMS cooldown active for ${contact.name}`);
      continue;
    }
    const ok = await sendSms(contact.phone, contact.carrier, alertBody);
    if (ok) {
      await setCooldown(deviceId, contact.id);
      sent++;
    }
  }
  console.log(`SMS alert: ${sent}/${contacts.length} delivered for device ${deviceId}`);
}

// ─── FCM push helper ────────────────────────────────────────────────────────

const STALE_TOKEN_CODES = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-argument",
];

// Bundled alert tones shipped with the app (see lib/models/alert_sound.dart).
// Maps the app's sound id to the Android raw resource name under res/raw/.
const SOUND_RESOURCES = {
  emergency: "emergency_alarm",
  siren: "alarm_siren",
  beep: "alarm_beep",
  chime: "alarm_chime",
};

// Resolves the owner's chosen alert sound to a raw resource name. Custom
// sounds can't be used as notification sounds, so they fall back to the alarm.
async function getAlertSound(deviceId) {
  try {
    const ownerSnap = await app()
      .database()
      .ref(`/devices/${deviceId}/owner`)
      .once("value");
    const ownerId = ownerSnap.val();
    if (!ownerId) return "emergency_alarm";

    const userDoc = await app()
      .firestore()
      .collection("users")
      .doc(ownerId)
      .get();
    const soundId = userDoc.exists ? userDoc.data().alertSound : null;
    return SOUND_RESOURCES[soundId] || "emergency_alarm";
  } catch (err) {
    console.error("getAlertSound error:", err.message);
    return "emergency_alarm";
  }
}

async function sendPush(deviceId, title, body, data) {
  const tokensSnap = await app()
    .database()
    .ref(`/devices/${deviceId}/fcmTokens`)
    .once("value");
  const tokens = tokensSnap.val();
  if (!tokens) return;

  const entries = Object.entries(tokens);
  const validTokens = entries.map(([, d]) => d.token).filter(Boolean);
  if (validTokens.length === 0) return;

  const sound = await getAlertSound(deviceId);
  const staleTokens = [];

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
              sound,
              priority: "high",
              visibility: "public",
              notificationCount: 1,
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
                alert: { title, body },
              },
            },
          },
        });
      } catch (err) {
        if (STALE_TOKEN_CODES.includes(err.code)) {
          staleTokens.push(token);
        } else {
          console.error("FCM error:", err.message);
        }
      }
    }),
  );

  for (const [userId, data] of entries) {
    if (staleTokens.includes(data.token)) {
      await app()
        .database()
        .ref(`/devices/${deviceId}/fcmTokens/${userId}`)
        .remove();
    }
  }
}

// ─── Event handlers ─────────────────────────────────────────────────────────

async function handleEmergency(p) {
  const reason = p.reason || "Emergency triggered";
  const isSOS = reason.includes("SOS");
  const isFall = reason.includes("Fall") || reason.includes("accelerometer");

  const title = isSOS ? "SOS Emergency" : isFall ? "Fall Detected" : "Emergency Alert";
  const body = `Device alert: ${reason}`;

  await sendPush(p.deviceId, title, body, {
    type: isSOS ? "sos" : isFall ? "fall" : "emergency",
    deviceId: String(p.deviceId),
    reason,
    lat: String(p.lat ?? ""),
    lng: String(p.lng ?? ""),
  });

  const deviceName = (await getDeviceName(p.deviceId)) || "Guardian device";
  const link = mapsLink(p.lat, p.lng);
  await notifyEmergencyContacts(
    p.deviceId,
    `[URGENT] ${deviceName}: ${reason}.${link ? ` Location: ${link}` : ""}`,
  );
}

async function handleGeofence(p) {
  const type = p.type || "exited";
  const name = p.name || "Unknown zone";
  const isExit = type === "exited";

  const title = isExit ? "Geofence Breach" : "Device Returned";
  const body = isExit ? `Device has left "${name}"` : `Device has entered "${name}"`;

  await sendPush(p.deviceId, title, body, {
    type: `geofence_${type}`,
    geofenceId: String(p.geofenceId || ""),
    geofenceName: name,
    deviceId: String(p.deviceId),
    lat: String(p.lat ?? ""),
    lng: String(p.lng ?? ""),
  });

  if (isExit) {
    const deviceName = (await getDeviceName(p.deviceId)) || "Guardian device";
    const link = mapsLink(p.lat, p.lng);
    await notifyEmergencyContacts(
      p.deviceId,
      `[Guardian Alert] ${deviceName} has left geofence zone "${name}".${link ? ` Location: ${link}` : ""}`,
    );
  }
}

// ─── Vercel handler ─────────────────────────────────────────────────────────

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ ok: false, error: "Method not allowed" });
  }

  // Vercel parses JSON bodies automatically; fall back to manual parsing.
  let payload = req.body;
  if (typeof payload === "string") {
    try {
      payload = JSON.parse(payload || "{}");
    } catch (e) {
      return res.status(400).json({ ok: false, error: "Invalid JSON" });
    }
  }
  payload = payload || {};

  const { kind, deviceId } = payload;
  if (!deviceId) {
    return res.status(400).json({ ok: false, error: "Missing deviceId" });
  }

  try {
    if (kind === "emergency") {
      await handleEmergency(payload);
    } else if (kind === "geofence") {
      await handleGeofence(payload);
    } else {
      return res.status(400).json({ ok: false, error: `Unknown kind "${kind}"` });
    }
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error("notify error:", err);
    return res.status(500).json({ ok: false, error: err.message });
  }
};