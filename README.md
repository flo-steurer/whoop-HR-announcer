# WHOOP HR Announcer

A small iOS 17+ SwiftUI app that receives live heart-rate measurements from a WHOOP over Bluetooth and announces them without requiring a WHOOP login or backend.

## Run it on an iPhone

1. Open `WhoopHRAnnouncer.xcodeproj` in Xcode.
2. Select the **WhoopHRAnnouncer** target, choose your Apple Development team under Signing & Capabilities, and change the bundle identifier if Xcode asks for a unique one.
3. Connect an iPhone running iOS 17 or later and press Run. Core Bluetooth data is not available in the iOS Simulator.
4. In the official WHOOP app, open Device Settings and enable **Heart Rate Broadcast**.
5. In HR Announcer, tap **Choose WHOOP**, select the advertised device, then choose **Manual Range** or **Workout Plan** before starting.

The app declares both the `bluetooth-central` and `audio` background modes, and restores its central manager after system termination. This lets Bluetooth heart-rate notifications wake the app and lets spoken coaching play while another app is visible or the phone is locked. iOS does not relaunch Bluetooth apps after the user manually force-quits them; reopen the app before the next session.

## Behavior

- Manual Range preserves the original configurable minimum and maximum BPM workflow.
- Workout Plan sessions use sequential timed phases. Each phase supplies the active BPM range while the normal, outside-range, boundary-confirmation, and audio settings remain global.
- Plans can contain ordinary phases and repeat groups. A repeat group runs one or more phases in order for the configured number of repetitions.
- Workout timing uses monotonic system uptime. BLE readings, controls, restoration, and foreground activation evaluate progression; the visible one-second countdown is display-only.
- Delayed BLE readings advance through every expired phase. Only the phase that is actually current is announced, avoiding a backlog of obsolete coaching.
- Pausing freezes the workout timeline and silences coaching while keeping BLE connected and live HR visible. Previous and Next restart the destination phase at its full duration.
- Plans and active workout snapshots are stored locally. A same-boot relaunch catches up from monotonic time; a reboot or uncertain clock discontinuity restores the workout paused at its latest checkpoint.
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

- Create a short plan with 30–60 second phases and a repeated fast/recovery group. Confirm the displayed phase order, repeat iteration, upcoming phase, countdown, and overall progress.
- Start the plan, lock the screen, and verify that every phase transition is heard with its new target range while another app is foregrounded.
- Put the current HR outside the new phase range and confirm that boundary confirmation and the faster outside-range interval use that phase’s range.
- Pause and resume after unlocking. Confirm that HR remains visible while paused, coaching is silent, the countdown is frozen, and resume continues with the same remaining time.
- Use Previous and Next both while running and paused. Confirm that the destination phase restarts at full duration and that paused skips remain paused.
- Let a plan finish with the phone locked. Confirm the “Workout complete” announcement and that the announcing session stops.
- Interrupt or move the WHOOP out of range long enough to cross multiple short phases, then reconnect. Confirm that the app catches up directly to the current phase or completion without announcing expired phases.
- Allow iOS/Xcode to terminate the app without force-quitting it, then generate another WHOOP reading. Confirm Bluetooth restoration, workout catch-up, and persisted controls. Also verify that a manually force-quit app does not relaunch until opened again, as required by iOS.
- Verify output through the intended headphones and test both Duck and Mix while music or a podcast is playing.
- Run at least 30 minutes with a disconnect/reconnect, then complete a 60-minute walk/run while checking timing, battery use, locked-screen reliability, and coexistence with the WHOOP app.
