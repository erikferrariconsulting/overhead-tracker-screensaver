# Overhead Tracker macOS Screensaver

Real-time aircraft tracking screensaver for macOS. This screensaver answers: *"What planes are flying directly above me right now?"* by plotting live ADS-B aircraft positions, trajectories, and local airports onto a beautiful, dark-themed MapKit canvas.

It is part of the [Overhead Tracker](https://overheadtracker.com) system.

---

## Features

- **Live Aircraft Plotting:** Renders active flights in the local area dynamically.
- **Flight Heading Direction:** The airplane icons automatically rotate to align their nose with the true bearing/heading direction.
- **Yellow Trailing Paths:** Draws identical, solid yellow trailing lines behind all flights so you can see where they are coming from.
- **Geofence Boundary Constraint:** Filters out any aircraft outside the circular geofence boundary so they are never featured on the info card.
- **Airport Annotations:** Dynamically loads a global database of coordinates to plot and label local airports with their name and IATA/ICAO code (e.g., `Sydney (YSSY)`).
- **Collision-Avoidance Info Card:** Shows detailed flight card specs (callsign, altitude, speed, distance, aircraft type, and route). The card dynamically slides to the left or right side of the screen to avoid overlapping the plane's current position.
- **White Connector Anchor Line:** Draws a solid, semi-transparent white connector line directly from the featured plane to the flight information card.

---

## Getting Started

### Requirements
- macOS 14.0 or newer
- Xcode 15.0 or newer (for building from source)

### Local Debugging & Testing
You can run and preview the screensaver directly in a standard desktop window without installing it into macOS System Settings.

First, ensure the core framework has been built by Xcode:
```bash
xcodebuild build -scheme OverheadTrackerScreensaverCore
```

Then, compile the debug runner linking it against the framework with the correct runtime search path (`rpath`):
```bash
swiftc -parse-as-library \
  -I ~/Library/Developer/Xcode/DerivedData/OverheadTrackerScreensaver-*/Build/Products/Debug \
  -F ~/Library/Developer/Xcode/DerivedData/OverheadTrackerScreensaver-*/Build/Products/Debug \
  -framework OverheadTrackerScreensaverCore \
  -Xlinker -rpath -Xlinker ~/Library/Developer/Xcode/DerivedData/OverheadTrackerScreensaver-*/Build/Products/Debug \
  debug_runner.swift Screensaver/*.swift \
  -o debug_runner
```

Run the compiled executable:
```bash
./debug_runner
```

### Running Unit Tests
To run the project's unit tests:
```bash
xcodebuild test -scheme OverheadTrackerScreensaverCore -destination 'platform=macOS'
```

### Building & Installing
1. Open `OverheadTrackerScreensaver.xcodeproj` in Xcode.
2. Select the `OverheadTrackerScreensaver` scheme and configure the build destination to **My Mac**.
3. Build the project (`Product` -> `Build`, or `Cmd + B`).
4. Xcode will generate the compiled bundle `OverheadTrackerScreensaver.saver` inside the build products folder.
5. Copy the `.saver` bundle to your User Screen Savers directory:
   ```bash
   rm -rf "$HOME/Library/Screen Savers/OverheadTrackerScreensaver.saver"
   cp -R ~/Library/Developer/Xcode/DerivedData/OverheadTrackerScreensaver-*/Build/Products/Release/OverheadTrackerScreensaver.saver "$HOME/Library/Screen Savers/"
   ```
6. Force-restart the screensaver host engine to clear cached versions:
   ```bash
   killall -9 legacyScreenSaver
   ```
7. Open **System Settings** -> **Screen Saver** on your Mac to preview and select the screensaver.
