// Netlify Function — Guardian alert notifications (FCM push + SMS).
//
// Replaces the Cloud Functions version (functions/index.js) so the Guardian
// project can run on the free Firebase Spark plan + free Netlify tier.
//
// The ESP32 POSTs a JSON body here when an emergency or geofence event fires:
//   emergency: { kind, deviceId, reason, type, lat, lng }
//   geofence:  { kind, deviceId, type, name, geofenceId, lat, lng }
//
// Required env vars (set in Netlify > Site settings > Environment variables):
//   FIREBASE_SERVICE_ACCOUNT  full service-account JSON (single line or multiline)
//   FIREBASE_DATABASE_URL     e.g. https://<project>-default-rtdb.firebaseio.com
//   EMAIL_USER / EMAIL_PASS   Gmail account + App Password for email-to-SMS

const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// ─── Email-to-SMS gateway map ───────────────────────────────────────────────
// Must match the Dart-side carrierSmsGateways map in lib/models/contact_model.dart.
const CARRIER_GATEWAYS = {
  "Globe (PH)": "txt.globe.com.ph",
  "Smart (PH)": "isms.smart.com.ph",
  "Sun (PH)": "suncellular.com.ph",
  "DITO (PH)": "ditosms.com",
  "Verizon": "vtext.com",
  "AT&T": "txt.att.net",
  "T-Mobile": "tmomail.net",
  "Sprint": "messaging.sprintpcs.com",
};

// ─── Rate limiting ──────────────────────────────────────────────────────────
const SMS_COOLDOWN_MS = 5 * 60 * 1000;

let _app = null;
function app() {
  if (_app) return _app;
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT env var is not set");
  }
  _app = admin.initializeApp({
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

let _transport = null;
function getTransport() {
  if (_transport) return _transport;
  const user = process.env.EMAIL_USER;
  const pass = process.env.EMAIL_PASS;
  if (!user || !pass) {
    console.warn("EMAIL_USER / EMAIL_PASS not set — SMS disabled");
    return null;
  }
  _transport = nodemailer.createTransport({
    service: "gmail",
    auth: { user, pass },
  });
  return _transport;
}

async function sendSms(phone, carrier, body) {
  const gateway = CARRIER_GATEWAYS[carrier];
  if (!gateway) {
    console.warn(`Unknown carrier "${carrier}" — skipping SMS`);
    return false;
  }
  const transport = getTransport();
  if (!transport) return false;

  const to = `${phone}@${gateway}`;
  try {
    await transport.sendMail({
      from: process.env.EMAIL_USER,
      to,
      subject: "",
      text: body,
    });
    console.log(`SMS sent to ${phone} (${carrier})`);
    return true;
  } catch (err) {
    console.error(`SMS failed for ${phone} (${carrier}):`, err.message);
    return false;
  }
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
    if (data.phone && data.carrier) {
      contacts.push({
        id: doc.id,
        name: data.name || "Contact",
        phone: data.phone,
        carrier: data.carrier,
      });
    }
  });
  return contacts;
}

async function notifyEmergencyContacts(deviceId, alertBody) {
  const contacts = await getEmergencyContacts(deviceId);
  if (contacts.length === 0) {
    console.log(`No emergency contacts with carrier for device ${deviceId}`);
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

  await notifyEmergencyContacts(
    p.deviceId,
    `[URGENT] Guardian alert: ${reason}. Open the app for location and details.`,
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
    await notifyEmergencyContacts(
      p.deviceId,
      `[Guardian Alert] Device has left geofence zone "${name}". Check the app for location details.`,
    );
  }
}

// ─── Netlify handler ────────────────────────────────────────────────────────

exports.handler = async (event) => {
  const headers = { "Content-Type": "application/json" };

  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers, body: JSON.stringify({ ok: false, error: "Method not allowed" }) };
  }

  let payload;
  try {
    payload = JSON.parse(event.body || "{}");
  } catch (e) {
    return { statusCode: 400, headers, body: JSON.stringify({ ok: false, error: "Invalid JSON" }) };
  }

  const { kind, deviceId } = payload;
  if (!deviceId) {
    return { statusCode: 400, headers, body: JSON.stringify({ ok: false, error: "Missing deviceId" }) };
  }

  try {
    if (kind === "emergency") {
      await handleEmergency(payload);
    } else if (kind === "geofence") {
      await handleGeofence(payload);
    } else {
      return { statusCode: 400, headers, body: JSON.stringify({ ok: false, error: `Unknown kind "${kind}"` }) };
    }
    return { statusCode: 200, headers, body: JSON.stringify({ ok: true }) };
  } catch (err) {
    console.error("notify error:", err);
    return { statusCode: 500, headers, body: JSON.stringify({ ok: false, error: err.message }) };
  }
};
