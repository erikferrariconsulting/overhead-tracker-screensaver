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

From the repository root, run the Swift debug runner script:
```bash
swift debug_runner.swift
```

### Building & Installing
1. Open `OverheadTrackerScreensaver.xcodeproj` in Xcode.
2. Select the `OverheadTrackerScreensaver` scheme and configure build destination to **My Mac**.
3. Build the project (`Product` -> `Build`, or `Cmd + B`).
4. Xcode will generate the compiled bundle `OverheadTrackerScreensaver.saver` inside the build products folder.
5. Copy the `.saver` bundle to your User Screen Savers directory:
   ```bash
   cp -R "/path/to/build/OverheadTrackerScreensaver.saver" "$HOME/Library/Screen Savers/"
   ```
6. Open **System Settings** -> **Screen Saver** on your Mac to preview and select the screensaver.
