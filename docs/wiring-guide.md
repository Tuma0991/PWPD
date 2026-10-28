# GuardianNako — Hardware Wiring Guide

Step-by-step wiring for the wrist-worn GuardianNako device. All pins below
match the current firmware (`esp32_firmware/guardian_firmware/guardian_firmware.ino`).
Companion docs: `hardware-requirements.md` (BOM + power notes) and
`device-case/guardiannako_watch_source.scad` (enclosure).

---

## 1. Pin map (matches firmware)

| Component | Component pin | → | ESP32-S3 SuperMini |
|-----------|--------------|---|--------------------|
| **MPU6050 (GY-521)** | VCC | → | **3.3V** |
| | GND | → | **GND** |
| | SDA | → | **GPIO8** |
| | SCL | → | **GPIO9** |
| **GT-U8 GPS** | VCC | → | **3.3V** |
| | GND | → | **GND** |
| | TX | → | **GPIO5** (UART2 RX) |
| | RX | → | **GPIO6** (UART2 TX) |
| **SOS button** | leg 1 | → | **GPIO4** |
| | leg 2 | → | **GND** |
| **Status LED** | GPIO2 → **220 Ω** → anode; cathode | → | **GND** |

Firmware references: `Wire.begin(8, 9)` (SDA=8, SCL=9), `GPS_RX_PIN 5` /
`GPS_TX_PIN 6`, `SOS_BUTTON_PIN 4` (active LOW, internal pull-up), `LED_PIN 2`.

---

## 2. Power chain (build in this order)

```
LiPo 3.7V ──► TP4056 (B+ / B-)
                OUT+ ──► [power switch] ──► boost IN+
                OUT- ─────────────────────► boost IN-   (common ground)

boost OUT+ (5V) ──► ESP32 5V pin
boost OUT- (GND) ──► ESP32 GND pin

ESP32 3.3V ──► MPU6050 VCC + GT-U8 VCC
ESP32 GND  ──► both modules' GND
```

- **TP4056** terminals: `B+` / `B-` → battery, `OUT+` / `OUT-` → boost input.
  Charge through the TP4056's own USB-C port.
- **Power switch** (required) goes in series on the **positive** line between
  the charging module (`TP4056 OUT+`) and the boost converter (`IN+`) — it
  cuts power to the device when off, while the battery can still charge.

---

## 3. Status LED (GPIO2)

The LED is a single-color external LED on GPIO2 — it replaces the onboard
WS2812 RGB pixel on the SuperMini. It is the device's only visual feedback and
has three roles in the firmware:

1. **Heartbeat** — toggles every ~2 s during normal operation. Slow steady
   blink = device is alive and connected.
2. **Emergency flash** — 10 rapid blinks (100 ms toggle) when an SOS press or
   fall is detected. Fast blink = alert was triggered and sent to Firebase.
3. **Provisioning mode** — a short periodic blink while the device waits for
   WiFi credentials over BLE.

---

## 4. Critical gotchas before powering anything

1. **Set the boost to 5 V FIRST.** The mini boost ships switched to **12 V** —
   wiring the ESP32 at 12 V will destroy it. Switch to 5 V, verify ~5.0–5.1 V
   with a multimeter, *then* connect the ESP32.
2. **One common ground.** Battery −, TP4056, boost, ESP32, and both modules
   must all share GND.
3. **Power the GPS from 3.3 V, not 5 V** — keeps its TX logic level safe for
   the ESP32's 3.3 V GPIO input.
4. **No external I2C pull-ups needed** — the GY-521 already has onboard
   4.7 kΩ pull-ups on SDA/SCL.
5. **Battery polarity** — reversing it damages the TP4056. Red = +, black = −.
6. **GPS needs sky** — the ceramic patch antenna must face outward (the SCAD
   already thins the front wall for it) and you need outdoor/clear view for the
   first fix. After wiring, check raw 9600-baud output for `$GPGGA` / `$GPRMC`
   (not only `$BDGGA`) so TinyGPS++ parses it.

---

## 5. Suggested build order

1. Flash + verify firmware over USB (serial monitor at 115200 — enable
   **USB CDC On Boot** on the S3 SuperMini).
2. Breadboard the power chain: LiPo → TP4056 → boost → ESP32, with the boost
   set to 5 V and meter-verified.
3. Confirm boot + data pushing to Firebase on battery.
4. Test charging (TP4056 red = charging, blue = full).
5. Solder onto perfboard and drop into the printed base (the base's standoff
   ledge keeps the LiPo + PCB off the floor).

---

## 6. Pre-solder check

Measure your exact **GT-U8 antenna** before soldering — the SCAD GPS window is
24×14 mm, but the module's ceramic patch is commonly ~25×20 mm. If yours is
bigger, adjust `gps_window_l` / `gps_window_w` in the SCAD.
