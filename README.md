# brAIn-mobile

Flutter companion app for [brAIn](https://github.com/tibzejoker/brAIn). Joins a brAIn NATS broker and exposes the phone's sensors, flash and TTS as bus topics — same model as `brain-agent` on desktop, with the phone's hardware in the role of "remote node."

> Works alongside `brAIn-essentials`, `brAIn-perception`, `brAIn-tools`, etc. — all of which contribute node types that can publish to or subscribe from the phone's topics.

## What it does

After scanning the QR shown in the brAIn dashboard's **Distributed** pane (or pasting the join URL manually), the app:

| Direction | Topic | Description |
|---|---|---|
| publish | `mobile.<id>.sensor.accel` | Accelerometer @ 10 Hz |
| publish | `mobile.<id>.sensor.gyro` | Gyroscope @ 10 Hz |
| publish | `mobile.<id>.sensor.magnetometer` | Magnetometer @ 5 Hz |
| publish | `mobile.<id>.sensor.light` | Ambient light (Android only — iOS has no public API) |
| publish | `mobile.<id>.sensor.battery` | Battery level + state every 30 s |
| subscribe | `mobile.<id>.flash` | `{on: true/false}` or `{blink: 200, n: 5}` |
| subscribe | `mobile.<id>.tts.speak` | `{text, voice?, rate?, pitch?, volume?}` |
| publish | `mobile.<id>.tts.voices` | Native voice catalog at boot |
| publish | `mobile.<id>.flash.status` · `mobile.<id>.tts.status` | State feedback |
| publish | `mobile.<id>.hello` | Identification on connect |

`<id>` is a stable UUID v4 generated on first launch and persisted in shared preferences.

## Quick start

### 1. Bootstrap the platform folders

The repo only ships `lib/` + `pubspec.yaml`. Generate the Android / iOS scaffolding once:

```bash
cd brAIn-mobile
flutter create . --org dev.brain --project-name brain_mobile
flutter pub get
```

> `flutter create .` is idempotent — it won't overwrite the Dart source.

### 2. Wire native permissions

Add the lines below before `flutter run`. They're not auto-generated.

**`android/app/src/main/AndroidManifest.xml`** — inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.FLASHLIGHT" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.flash" android:required="false" />
```

**`android/app/src/main/AndroidManifest.xml`** — inside `<application>` to allow plain `nats://` (cleartext) on the LAN:

```xml
android:usesCleartextTraffic="true"
```

**`ios/Runner/Info.plist`** — add:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan the brAIn join QR.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Not used directly — required by some Flutter plugins.</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key><true/>
</dict>
<key>NSLocalNetworkUsageDescription</key>
<string>Connect to the brAIn broker on your local network.</string>
```

### 3. Run

```bash
flutter run
```

In the dashboard: **Distributed → Open to LAN** so the broker accepts `0.0.0.0` connections, then scan the QR.

## Architecture

```
              ┌──────────────────────────┐
              │   brAIn API (laptop)     │
              │   embedded NATS:4222     │
              └────────┬─────────────────┘
                       │ nats://
        ┌──────────────┴──────────────┐
        │                             │
 ┌──────▼───────┐             ┌───────▼───────┐
 │ brain-agent  │             │ brAIn-mobile  │  ← this repo
 │  (laptop)    │             │  (phone)      │
 └──────────────┘             │  sensors/     │
                              │  flash/tts    │
                              └───────────────┘
```

`lib/services/`
- **`bus.dart`** — dart_nats wrapper, topic prefix, message envelope.
- **`sensors.dart`** — Throttled streams from `sensors_plus` + `light_sensor` + `battery_plus`.
- **`flash.dart`** — Subscribes to control, drives `torch_light`.
- **`tts.dart`** — Subscribes to control, drives `flutter_tts`.
- **`device_id.dart`** — Stable UUID per install.

`lib/screens/`
- **`connect_screen.dart`** — manual entry.
- **`scanner_screen.dart`** — `mobile_scanner` QR camera.
- **`home_screen.dart`** — sensor toggles + manual flash/TTS test + disconnect.

## Bus envelope

The mobile publishes brAIn-shaped messages so dashboard history / traces look identical to those produced by Node-side handlers:

```json
{
  "id": "1714945123456-sensor.accel",
  "from": "mobile.<deviceId>",
  "topic": "mobile.<deviceId>.sensor.accel",
  "type": "text",
  "criticality": 1,
  "payload": { "content": "{\"x\":0.1,\"y\":-9.8,\"z\":0.0,\"t\":...}" },
  "metadata": { "x": 0.1, "y": -9.8, "z": 0.0, "t": ... },
  "timestamp": 1714945123456
}
```

Both `payload.content` (string for legacy parsers) and `metadata` (typed) carry the same data — handlers can read whichever they prefer.

## License

MIT — same as the rest of the brAIn ecosystem.
