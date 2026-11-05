// lib/screens/user_manual_screen.dart

import 'package:flutter/material.dart';

/// In-app user manual covering every screen and the buttons on each.
///
/// Reachable from the dashboard's ⋮ menu (next to Settings, About Us and
/// Log out). Each section is collapsible so the whole guide lives on one
/// scrollable screen.
class UserManualScreen extends StatelessWidget {
  const UserManualScreen({super.key});

  static const _blue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _blue,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'User Manual',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _IntroCard(),
          SizedBox(height: 12),

          // ─── Getting started ──────────────────────────────────────────
          _ManualSection(
            icon: Icons.login,
            title: 'Getting Started — Sign In & Register',
            children: [
              _P(
                'When you open GuardianNako you land on the sign-in screen. '
                'Switch between the two tabs at the top of the white card.',
              ),
              _H('Sign In'),
              _B('Email address', 'Enter the email you registered with.'),
              _B('Password', 'Enter your password. Tap the eye icon to show or hide it.'),
              _B('Remember me', 'Saves your email so it is pre-filled next time.'),
              _B('Forgot password?', 'Sends a password-reset link to the email you entered.'),
              _B('Sign In', 'Logs you in and opens the dashboard.'),
              _B('Continue with Google', 'Signs you in using your Google account.'),
              _H('Register'),
              _P('Use the Register tab to create a new account.'),
              _B('Full Name', 'How your loved ones will see you.'),
              _B('Email address', 'Must be a valid email format.'),
              _B('Password', 'At least 8 characters with an uppercase letter, a lowercase letter, a number and a symbol.'),
              _B('Confirm Password', 'Must match the password above.'),
              _B('Create Account', 'Creates the account and opens the dashboard.'),
              _P(
                'If something is wrong, the field turns red with a short hint '
                'underneath (for example "Incorrect password" or "Email already registered").',
              ),
            ],
          ),

          // ─── Bottom navigation ────────────────────────────────────────
          _ManualSection(
            icon: Icons.view_agenda_outlined,
            title: 'Home Screen & Bottom Navigation',
            children: [
              _P(
                'After signing in you see the main home screen. Along the bottom '
                'are five tabs:',
              ),
              _B('Dashboard', 'The center button. A summary of device status and quick actions.'),
              _B('Map', 'Live GPS location, geofences and a route to the wearer.'),
              _B('Movement', 'Fall detection and the wearer’s current activity level.'),
              _B('Alerts', 'The history of emergency and geofence alerts.'),
              _B('Contacts', 'The people to notify during an emergency.'),
              _P('Tap a tab once to switch; the active tab is highlighted in blue.'),
            ],
          ),

          // ─── Dashboard ────────────────────────────────────────────────
          _ManualSection(
            icon: Icons.dashboard,
            title: 'Dashboard',
            children: [
              _P('The dashboard is the first tab. From top to bottom:'),
              _H('Top bar'),
              _B('Device switcher',
                  'The watch icon with a drop-down arrow (top-right). Tap it to switch '
                  'between paired devices, or choose "Manage devices" to add, rename or remove them.'),
              _B('⋮ menu (three dots)',
                  'Opens Settings, About Us, User Manual and Log out.'),
              _H('Welcome banner'),
              _B('Online / Offline badge',
                  'Green "Online" when the device is reporting; otherwise grey "Offline".'),
              _B('Battery',
                  'Shows the device battery level (estimated until the firmware reports a real value).'),
              _B('Status line',
                  'Shows whether the device is monitoring and the "last seen" time.'),
              _H('No device banner'),
              _P(
                'If no device is connected yet, an orange banner appears with a '
                '"Set Up" button that starts Bluetooth pairing.',
              ),
              _H('Device Status cards'),
              _B('GPS Location', 'The latest latitude/longitude, or "No signal".'),
              _B('Movement', 'Live X and Y accelerometer readings.'),
              _B('Movement Status', 'Shows "Normal" or "FALL DETECTED!".'),
              _B('Device Connectivity', 'Connected or Disconnected.'),
              _H('Quick Guide'),
              _P('Three short tiles explaining Fall Detection, GPS Tracking and Emergency Alerts.'),
              _H('Emergency banner'),
              _P(
                'When an emergency is active, a red banner appears with a '
                '"Mark as Safe" button. Tapping it confirms the wearer is okay '
                'and clears the alert.',
              ),
              _P('Pull down anywhere to refresh the view.'),
            ],
          ),

          // ─── Map ──────────────────────────────────────────────────────
          _ManualSection(
            icon: Icons.map,
            title: 'Map — Live Location & Geofences',
            children: [
              _P('The Map tab shows the wearer’s position and lets you manage safe zones.'),
              _H('Top bar buttons'),
              _B('Locate now (crosshair)',
                  'Asks the device to turn on GPS and report its position immediately.'),
              _B('Zones (map pin)',
                  'Opens the "Saved Zones" list where you create and manage geofences.'),
              _B('Follow / Free toggle',
                  '"Following" keeps the map centered on the device; "Free" lets you pan manually. '
                  'Panning the map by hand switches it to Free automatically.'),
              _H('Markers on the map'),
              _B('Device marker', 'The wearer’s photo (or a person icon) at their location.'),
              _B('"You" marker', 'Your own phone’s location.'),
              _B('Geofence polygons', 'Colored shapes showing your saved safe zones.'),
              _B('Route line', 'A road-following route from you to the device.'),
              _H('Floating controls (top-left of the map)'),
              _B('Car / Walk toggle', 'Chooses driving or walking directions for the route.'),
              _B('Route button (road icon)',
                  'Shows or hides the route line. Tapping it when there is no route yet fetches one.'),
              _H('Bottom info card'),
              _P(
                'Shows the device name, its latitude/longitude, last-seen time, '
                'and a Live / Last Known / No Signal status pill. When a route is '
                'visible it also shows distance and estimated time.',
              ),
              _H('Emergency banner'),
              _P('If an emergency is active, a red "Mark as Safe" banner sits below the top bar.'),
              _H('Saved Zones (Zones button)'),
              _B('New', 'Starts drawing a new polygon zone.'),
              _B('Zone card',
                  'Each zone shows its name, number of points, a switch to enable/disable it, '
                  'and whether the device is currently inside or outside.'),
              _B('Edit', 'Re-opens the zone in drawing mode to change its shape or name.'),
              _B('Delete', 'Removes the zone after a confirmation.'),
              _H('Drawing a polygon'),
              _P('After tapping "New" the screen switches to drawing mode.'),
              _B('Tap the map', 'Place vertices (corners). You need at least 3.'),
              _B('Polygon Name', 'Give the zone a name such as "Home" or "School".'),
              _B('Undo', 'Removes the last placed point.'),
              _B('Clear', 'Removes all points.'),
              _B('Cancel', 'Discards the polygon and returns to the map.'),
              _B('Save Polygon / Update Polygon',
                  'Stores the zone and syncs it to the device. It becomes active only after saving.'),
            ],
          ),

          // ─── Movement ─────────────────────────────────────────────────
          _ManualSection(
            icon: Icons.sensors,
            title: 'Movement — Fall Detection',
            children: [
              _P(
                'This tab turns the raw accelerometer data into a plain-language '
                'status of what the wearer is doing right now.',
              ),
              _H('Hero status'),
              _B('SOS ALERT!', 'The emergency button was pressed on the device.'),
              _B('FALL DETECTED!', 'A possible fall was detected.'),
              _B('Staying Still', 'No movement right now.'),
              _B('Light Movement', 'Small movements like sitting or shifting.'),
              _B('Moving', 'Steady movement like walking.'),
              _B('Very Active', 'Strong movement like running.'),
              _B('Monitoring', 'Waiting for the first data from the device.'),
              _B('Device Offline', 'No live data; showing the last saved snapshot.'),
              _H('Info button (top-right)'),
              _B('How Fall Detection Works',
                  'Explains how the motion sensor detects falls and how the app receives the event.'),
              _H('Status card'),
              _P(
                'Shows a movement level bar (Still → Light → Moving → Intense), '
                'a short explanation of the current state, and guidance on what to do. '
                'If the wearer has been still, it also shows how long.',
              ),
              _H('Sensor readings'),
              _B('Expandable panel',
                  'Advanced view showing the raw X, Y and Z accelerometer axes with colored bars.'),
              _P(
                'Emergencies are cleared from the Map or Dashboard tab using "Mark as Safe", '
                'not from this screen.',
              ),
            ],
          ),

          // ─── Alerts ───────────────────────────────────────────────────
          _ManualSection(
            icon: Icons.notifications_active,
            title: 'Alerts — Alert History',
            children: [
              _P('A running list of every emergency and geofence event.'),
              _H('Summary chips'),
              _B('Falls', 'Filters the list to fall alerts only.'),
              _B('SOS', 'Filters to SOS-button and emergency alerts.'),
              _B('Geo', 'Filters to geofence enter/exit alerts.'),
              _B('Total', 'Shows every alert. Tap a chip again to clear its filter.'),
              _H('Alert list'),
              _P(
                'Each alert shows a badge (FALL, SOS or GEO), a message and the time. '
                'Tap any alert to open its details.',
              ),
              _H('Alert details'),
              _B('Map', 'Shows the location where the alert happened, if available.'),
              _B('Message / Reason', 'What happened and why.'),
              _B('Device', 'Which device (or wearer) the alert came from.'),
              _B('Location', 'The exact latitude/longitude.'),
              _P(
                'Note: when the SOS button is pressed, the sudden jolt is also detected '
                'as a possible fall for a moment — the app suppresses this duplicate so '
                'only one SOS alert is logged.',
              ),
            ],
          ),

          // ─── Contacts ─────────────────────────────────────────────────
          _ManualSection(
            icon: Icons.contacts,
            title: 'Contacts — Emergency Contacts',
            children: [
              _P('Manage the people to notify during an emergency.'),
              _B('Add Contact (button)',
                  'Opens the form to add a new contact.'),
              _H('Sections'),
              _B('Emergency Contacts', 'Contacts marked for SMS notification during alerts.'),
              _B('Other Contacts', 'Everyone else.'),
              _H('Contact card'),
              _B('Call button (green phone)',
                  'Dials the contact’s number using your phone app.'),
              _B('⋮ menu',
                  'Edit or Delete the contact. Deleting asks for confirmation.'),
              _H('Add / Edit form'),
              _B('Full Name', 'The contact’s name.'),
              _B('Phone Number', 'Their phone number.'),
              _B('Relationship', 'Optional, e.g. Mother, Father, Sister.'),
              _B('Emergency Contact (switch)',
                  'When on, the contact receives SMS alerts and an extra '
                  '"Mobile Carrier" field appears (needed to send SMS by carrier gateway).'),
              _B('Add Contact / Save Changes', 'Stores the contact.'),
            ],
          ),

          // ─── Settings ─────────────────────────────────────────────────
          _ManualSection(
            icon: Icons.settings_outlined,
            title: 'Settings (from the ⋮ menu)',
            children: [
              _P('The ⋮ menu on the dashboard opens Settings with these items:'),
              _B('Account', 'Edit your name, email and password.'),
              _B('Device Settings', 'Set the wearer’s photo and name, and reconfigure the device.'),
              _B('Devices', 'Add, switch, rename or remove paired devices.'),
              _B('Language', 'Toggle between English and Filipino.'),
              _B('Alert sound', 'Choose the alarm tone for emergency alerts.'),
            ],
          ),

          // ─── Account ──────────────────────────────────────────────────
          _ManualSection(
            icon: Icons.account_circle_outlined,
            title: 'Account Settings',
            children: [
              _P('Manage your own account details.'),
              _B('Display name', 'Change how your name appears in the app.'),
              _B('Email address',
                  'Change your sign-in email. You must re-enter your current password, '
                  'then confirm the change from a verification link sent to the new address.'),
              _B('Password',
                  'Change your password. You must first enter your current password, '
                  'then a new one (same strength rules as registration).'),
            ],
          ),

          // ─── Device settings ──────────────────────────────────────────
          _ManualSection(
            icon: Icons.badge,
            title: 'Device Settings',
            children: [
              _P('Personalize the wearable associated with the active device.'),
              _B('Wearer photo',
                  'Tap the circular photo to choose a picture from your gallery. '
                  'It appears as the device marker on the map.'),
              _B('Wearer name', 'Set the name shown on the map and in alerts.'),
              _B('Device setup',
                  'Re-opens the Bluetooth setup flow to connect or reconfigure a wearable.'),
            ],
          ),

          // ─── Devices ──────────────────────────────────────────────────
          _ManualSection(
            icon: Icons.devices,
            title: 'Devices',
            children: [
              _P('Lists all wearables paired to your account.'),
              _B('Tap a device', 'Makes it the active device the whole app monitors.'),
              _B('Active badge', 'A green "Active" label marks the current device.'),
              _B('⋮ menu → Rename', 'Change the device’s display name.'),
              _B('⋮ menu → Remove', 'Unpair the device (asks for confirmation).'),
              _B('Add device', 'Starts Bluetooth pairing for a new wearable.'),
            ],
          ),

          // ─── Device setup ─────────────────────────────────────────────
          _ManualSection(
            icon: Icons.bluetooth,
            title: 'Device Setup (Bluetooth Pairing)',
            children: [
              _P(
                'Pairs a Guardian wearable and connects it to your WiFi. You may be '
                'asked to allow Bluetooth and Location permissions.',
              ),
              _H('Steps'),
              _B('1. Scan', 'The app scans for nearby devices. Guardian devices are marked "GUARDIAN".'),
              _B('2. Select device', 'Tap a Guardian device to continue.'),
              _B('3. Enter WiFi', 'Type the network name (SSID) and password, then "Send to Device".'),
              _B('4. Wait', 'The credentials are sent and the device restarts automatically.'),
              _B('5. Done', 'A success screen shows the new Device ID.'),
              _H('Buttons'),
              _B('Scan Again', 'Restarts the scan.'),
              _B('Choose different device', 'Goes back to the scan list.'),
              _B('Try Again', 'Retries after a failed setup.'),
              _B('Cancel / close (X)', 'Leaves the setup screen.'),
            ],
          ),

          // ─── Alert sound ──────────────────────────────────────────────
          _ManualSection(
            icon: Icons.music_note,
            title: 'Alert Sound',
            children: [
              _P('Choose the tone that plays on your phone when an emergency alert arrives.'),
              _B('Preview (play icon)',
                  'Plays the tone so you can hear it before choosing. Tap again to stop.'),
              _B('Bundled sounds', 'Tap a sound to select it.'),
              _B('Custom sound', 'Choose an audio file from your device.'),
            ],
          ),

          // ─── Emergencies ──────────────────────────────────────────────
          _ManualSection(
            icon: Icons.emergency,
            title: 'Emergency Alerts — How They Work',
            children: [
              _P('GuardianNako raises three kinds of alerts:'),
              _B('SOS button',
                  'When the wearer presses the emergency button, the app shows a full-screen '
                  'SOS ALERT with options to "View Map" or dismiss.'),
              _B('Fall detection',
                  'When the device detects a fall, it shows a FALL DETECTED alert.'),
              _B('Geofence violation',
                  'When the device enters or leaves a saved zone, a notification and a '
                  'history entry are created (also saved under Alerts).'),
              _P(
                'During an active emergency the chosen alert sound loops and the device '
                'is shown on the map. The alert stays active until someone taps '
                '"Mark as Safe" on the Dashboard, Map, Movement, Alerts or Contacts tab.',
              ),
              _B('Mark as Safe',
                  'Confirms the wearer is okay, stops the alarm, and clears the emergency.'),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Intro card ──────────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          Icon(Icons.menu_book, color: Colors.white, size: 30),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'This guide walks you through every screen in GuardianNako and '
              'explains each button. Tap a section to expand it.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Collapsible section ─────────────────────────────────────────────────────

class _ManualSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _ManualSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF1565C0), size: 18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2340),
              fontSize: 14,
            ),
          ),
          iconColor: const Color(0xFF1565C0),
          collapsedIconColor: const Color(0xFF9EA8C2),
          children: children,
        ),
      ),
    );
  }
}

// ─── Text helpers ────────────────────────────────────────────────────────────

class _H extends StatelessWidget {
  final String text;
  const _H(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1565C0),
        ),
      ),
    );
  }
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF5C6B7A),
          height: 1.5,
        ),
      ),
    );
  }
}

class _B extends StatelessWidget {
  final String title;
  final String? body;
  const _B(this.title, [this.body]);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF1565C0)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF5C6B7A),
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A2340),
                    ),
                  ),
                  if (body != null)
                    TextSpan(text: ' — $body'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
