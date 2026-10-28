const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// ─── Email-to-SMS gateway map ───────────────────────────────────────────────
// Must match the Dart-side carrierSmsGateways map in contact_model.dart.
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
// Max one SMS per contact per cooldown period to avoid spamming.
const SMS_COOLDOWN_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Check whether a contact was recently sent an SMS. Returns true if the
 * cooldown has NOT expired (i.e. we should skip sending).
 */
async function isInCooldown(deviceId, contactId) {
  const snap = await admin
    .database()
    .ref(`/devices/${deviceId}/smsCooldowns/${contactId}`)
    .once("value");
  const lastSent = snap.val();
  if (!lastSent) return false;
  return Date.now() - lastSent < SMS_COOLDOWN_MS;
}

async function setCooldown(deviceId, contactId) {
  await admin
    .database()
    .ref(`/devices/${deviceId}/smsCooldowns/${contactId}`)
    .set(Date.now());
}

// ─── Nodemailer transport (lazy) ────────────────────────────────────────────

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

// ─── SMS sender ─────────────────────────────────────────────────────────────

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
      subject: "", // SMS gateways ignore subject
      text: body,
    });
    console.log(`SMS sent to ${phone} (${carrier})`);
    return true;
  } catch (err) {
    console.error(`SMS failed for ${phone} (${carrier}):`, err.message);
    return false;
  }
}

// ─── Emergency contact lookup ───────────────────────────────────────────────

/**
 * Read the device owner's emergency contacts from Firestore.
 * Returns an array of { id, name, phone, carrier }.
 */
async function getEmergencyContacts(deviceId) {
  // Read owner userId from RTDB
  const ownerSnap = await admin
    .database()
    .ref(`/devices/${deviceId}/owner`)
    .once("value");
  const ownerId = ownerSnap.val();
  if (!ownerId) {
    console.warn(`No owner found for device ${deviceId}`);
    return [];
  }

  // Query Firestore for emergency contacts
  const contactsSnap = await admin
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

/**
 * Send an SMS alert to every emergency contact that has a carrier set and
 * isn't in cooldown.
 */
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
  console.log(
    `SMS alert: ${sent}/${contacts.length} delivered for device ${deviceId}`,
  );
}

// ─── FCM push helper ────────────────────────────────────────────────────────

const STALE_TOKEN_CODES = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-argument",
];

async function sendPush(deviceId, title, body, data) {
  const tokensSnap = await admin
    .database()
    .ref(`/devices/${deviceId}/fcmTokens`)
    .once("value");
  const tokens = tokensSnap.val();
  if (!tokens) return;

  const entries = Object.entries(tokens);
  const validTokens = entries
    .map(([, d]) => d.token)
    .filter(Boolean);
  if (validTokens.length === 0) return;

  const staleTokens = [];

  await Promise.allSettled(
    validTokens.map(async (token) => {
      try {
        await admin.messaging().send({
          token,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: {
              channelId: "geofence_alerts",
              sound: "default",
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

  // Clean up stale FCM tokens
  for (const [userId, data] of entries) {
    if (staleTokens.includes(data.token)) {
      await admin
        .database()
        .ref(`/devices/${deviceId}/fcmTokens/${userId}`)
        .remove();
      console.log(`Removed stale FCM token for user ${userId}`);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRIGGER 1 — Geofence violation → push + SMS (exit only)
// ═══════════════════════════════════════════════════════════════════════════

exports.onGeofenceViolation = functions.database.onValueCreated(
  "/devices/{deviceId}/geofence_violations/{violationId}",
  async (event) => {
    const { deviceId } = event.params;
    const violation = event.data.val();
    if (!violation) return null;

    const violationType = violation.type || "exited";
    const zoneName = violation.name || "Unknown zone";
    const isExit = violationType === "exited";

    const title = isExit ? "Geofence Breach" : "Device Returned";
    const body = isExit
      ? `Device has left "${zoneName}"`
      : `Device has entered "${zoneName}"`;

    // Push notification to all guardians
    await sendPush(deviceId, title, body, {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      type: `geofence_${violationType}`,
      geofenceId: String(violation.geofenceId || ""),
      geofenceName: zoneName,
      deviceId: String(deviceId),
      lat: String(violation.lat ?? ""),
      lng: String(violation.lng ?? ""),
    });

    // SMS only on exits (the important one)
    if (isExit) {
      await notifyEmergencyContacts(
        deviceId,
        `[Guardian Alert] Device has left geofence zone "${zoneName}". ` +
          `Check the app for location details.`,
      );
    }

    return null;
  },
);

// ═══════════════════════════════════════════════════════════════════════════
// TRIGGER 2 — Emergency (SOS / fall) → push + SMS
// ═══════════════════════════════════════════════════════════════════════════

exports.onEmergency = functions.database.onValueWritten(
  "/devices/{deviceId}/emergency",
  async (event) => {
    const { deviceId } = event.params;

    // Only act on a new emergency activation
    const before = event.data.before.val();
    const after = event.data.after.val();
    const wasActive = before && before.active === true;
    const isActive = after && after.active === true;
    if (!isActive || wasActive) return null;

    const reason = after.reason || "Emergency triggered";
    const isSOS = reason.includes("SOS");
    const isFall = reason.includes("Fall") || reason.includes("accelerometer");

    const title = isSOS
      ? "SOS Emergency"
      : isFall
        ? "Fall Detected"
        : "Emergency Alert";
    const body = `Device alert: ${reason}`;

    // Push notification
    await sendPush(deviceId, title, body, {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      type: isSOS ? "sos" : isFall ? "fall" : "emergency",
      deviceId: String(deviceId),
      reason,
      lat: String(after.lat ?? ""),
      lng: String(after.lng ?? ""),
    });

    // SMS to emergency contacts
    await notifyEmergencyContacts(
      deviceId,
      `[URGENT] Guardian alert: ${reason}. ` +
        `Open the app for location and details.`,
    );

    return null;
  },
);
