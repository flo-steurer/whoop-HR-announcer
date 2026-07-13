# WHOOP HR Announcer

A small iOS 17+ SwiftUI app that receives live heart-rate measurements from a WHOOP over Bluetooth and announces them without requiring a WHOOP login or backend.

## Run it on an iPhone

1. Open `WhoopHRAnnouncer.xcodeproj` in Xcode.
2. Select the **WhoopHRAnnouncer** target, choose your Apple Development team under Signing & Capabilities, and change the bundle identifier if Xcode asks for a unique one.
3. Connect an iPhone running iOS 17 or later and press Run. Core Bluetooth data is not available in the iOS Simulator.
4. In the official WHOOP app, open Device Settings and enable **Heart Rate Broadcast**.
5. In HR Announcer, tap **Choose WHOOP**, select the advertised device, configure the range, and tap **Start Announcing**.

The app declares the `bluetooth-central` background mode and restores its central manager after system termination. iOS does not relaunch Bluetooth apps after the user manually force-quits them; reopen the app before the next session.

## Behavior

- The minimum and maximum endpoints count as in range.
- A state change must remain stable for the configured confirmation time.
- In-range readings use the normal interval (60 seconds by default).
- Outside-range readings are announced on transition and every warning interval (10 seconds by default).
- Returning to the selected range is announced immediately after confirmation.
- Speech can duck other audio or mix with it. Old speech is cancelled before a newer reading is spoken.
- Settings, the selected peripheral, and active-session intent are stored locally. No workout history or health data is uploaded.

## Automated verification

The parser and announcement engine are exposed as a local Swift package so they can be tested without an iOS runtime:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Compile the complete unsigned iPhone target:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WhoopHRAnnouncer.xcodeproj \
  -scheme WhoopHRAnnouncer \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## Required physical-device checkpoint

Bluetooth and iOS background audio must be checked with the actual WHOOP and iPhone before relying on the app during a run:

- Receive live values with the screen locked.
- Hear a periodic and an outside-range announcement while backgrounded.
- Verify output through the intended headphones.
- Test both Duck and Mix while music or a podcast is playing.
- Run for at least 30 minutes and confirm reconnect behavior.
- Finally, perform a 60-minute walk/run while checking timing, battery use, and coexistence with the WHOOP app.
