# How to Find GPS Coordinates

Since the Geofence feature requires manual coordinate entry (for free operation without API keys), here are the easiest ways to find coordinates for your locations:

## Method 1: Google Maps (Easiest) 🗺️

### Desktop/Web:
1. Go to https://maps.google.com
2. Search for a location (e.g., "My Home")
3. Right-click on the map pin
4. A popup with coordinates appears at the top
5. Click to copy: `40.7128, -74.0060`
6. Paste into the app (Latitude: 40.7128, Longitude: -74.0060)

### Mobile Google Maps:
1. Open Google Maps app
2. Search for location
3. Long-press on the location
4. Tap the address bar showing coordinates
5. Coordinates copy to clipboard
6. Paste into geofence form

## Method 2: Your Device's Current Location 📍

1. On your ESP32 device with GPS:
   - Open serial monitor at 115200 baud
   - Wait for "GPS fix" message
   - Serial output shows: `Location: 40.7128, -74.0060`
2. Note these coordinates
3. Use them for a geofence (e.g., "Home")

## Method 3: Coordinates.io (Quick Web Tool) 🌐

1. Visit https://coordinates-io.web.app/ (or search "click on map for coordinates")
2. Click on the map where you want a geofence
3. Coordinates appear instantly
4. Copy and paste into app

## Method 4: OpenStreetMap 🗺️

1. Go to https://www.openstreetmap.org
2. Search for location or navigate map
3. Right-click on location → "Show Address"
4. Copy coordinates in decimal format
5. Paste into app

## Common Location Coordinates

Use these for testing:

**USA:**
- New York City: 40.7128, -74.0060
- Los Angeles: 34.0522, -118.2437
- San Francisco: 37.7749, -122.4194
- Chicago: 41.8781, -87.6298
- Miami: 25.7617, -80.1918

**International:**
- London, UK: 51.5074, -0.1278
- Paris, France: 48.8566, 2.3522
- Tokyo, Japan: 35.6762, 139.6503
- Sydney, Australia: -33.8688, 151.2093
- Dubai, UAE: 25.2048, 55.2708

## Coordinates Format Explained 📐

- **Latitude**: North-South position
  - Range: -90° (South Pole) to +90° (North Pole)
  - Negative = South, Positive = North
  - Example: 40.7128 = North latitude

- **Longitude**: East-West position
  - Range: -180° (West) to +180° (East)
  - Negative = West, Positive = East
  - Example: -74.0060 = West longitude

- **Decimal Format**: Used by geofence app
  - Example: 40.7128, -74.0060 ✅
  - **NOT**: 40°42'52.5"N, 74°00'21.6"W ❌

- **Accuracy**:
  - 1 decimal place = ~111 km accuracy
  - 2 decimal places = ~11 km accuracy
  - 3 decimal places = ~1.1 km accuracy
  - 4 decimal places = ~111 meters accuracy
  - 5 decimal places = ~11 meters accuracy
  - 6 decimal places = ~1.1 meter accuracy ← **Recommended for geofences**

## Practical Examples

### Example 1: Create a Home Geofence
1. Open Google Maps → Search "My Home" or your address
2. Right-click on your house location
3. See coordinates pop-up: `40.7142, -74.0064`
4. Use these values:
   - Name: "Home"
   - Latitude: 40.7142
   - Longitude: -74.0064
   - Radius: 300m (covers front/back yard)

### Example 2: Create a Work Geofence
1. Google Maps → Search your office building/address
2. Right-click → Copy coordinates
3. Set up:
   - Name: "Office"
   - Latitude: 40.7489
   - Longitude: -73.9680
   - Radius: 500m (covers parking lot)

### Example 3: Create a School Geofence
1. Find school on Google Maps
2. Check the coordinates: `40.7614, -73.9776`
3. Configure in app:
   - Name: "School"
   - Latitude: 40.7614
   - Longitude: -73.9776
   - Radius: 400m (includes parking area)

## Getting GPS from Your Device

The ESP32 with GPS module will continuously report its location via serial monitor. When you have a GPS fix:

```
[GEO FENCING] Location: 40.7128, -74.0060
```

You can use this current location to create a geofence:
1. Deploy the device at a location
2. Wait for GPS fix (1-3 minutes outdoors)
3. Read coordinates from serial monitor
4. Create a geofence in the app using those coordinates
5. Device will now monitor this zone

## Tips for Accurate Geofences 💡

1. **Use 6 decimal places**: More accurate (~1m precision)
   - 40.712845, -74.006045 ✅
   - 40.7128, -74.0060 ⚠️ (~11m precision)

2. **Verify with Google Maps**: Always double-check coordinates on map
   - Sometimes copy-paste swaps coordinates
   - Negative numbers for Western Hemisphere

3. **Account for GPS Drift**: 
   - GPS accuracy ±20-50m
   - Set radius 100-200m larger than needed
   - Example: If covering house (±20m), use 300m radius

4. **Test Coverage**:
   - After creating geofence, go to the location
   - Walk around the boundary
   - See if violations trigger at expected points

5. **Outdoor Testing**:
   - GPS works best outdoors
   - Weak signal near buildings/trees
   - Open sky = faster lock and better accuracy

## Coordinate Conversion Tools

If you have different formats:

- **DMS to Decimal**: https://www.rapidtables.com/convert/number/degrees-minutes-seconds-to-decimal.html
- **Decimal to DMS**: https://www.rapidtables.com/convert/number/decimal-to-degrees-minutes-seconds.html
- **Batch Coordinates**: https://batchgeo.com/

---

**Remember**: All coordinates are in **decimal degrees (DD)** format for the geofence app.
