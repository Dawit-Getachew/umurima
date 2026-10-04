# Umurima SMS gateway (Android)

Turns one Android phone with a SIM card into the SMS gateway for Umurima AI.
Farmers text a question from any basic phone. This app receives the SMS, asks the
[backend](../backend), and texts the answer back. Farmers need no smartphone, data
bundle or app.

## Features

- **Store and forward.** Every SMS is written to a local SQLite queue before upload. If the network drops, it is retried every 15 seconds and answered when the connection returns. Uploads stranded by a killed process are reclaimed.
- **Runs in the background.** A foreground service keeps answering with the app closed or the screen locked, until the operator stops it.
- **Operator dashboard.** Shows:
  - gateway and backend status, with knowledge, verified and cached answer counts;
  - totals for received, answered, waiting and failed messages;
  - each conversation with its reply and how it was produced (verified answer, cached, AI, urgent escalation, offline notes).

  Failed messages can be retried.
- **Test a question.** Sends a question to the backend in English or Kinyarwanda and shows the reply, its SMS length and the notes it came from, without sending an SMS.

## Run

```bash
flutter pub get
flutter run                                                    # Android device with a SIM
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000   # a local backend
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

On first start, tap **Start gateway** and allow the SMS and notification permissions,
plus the battery-optimization exemption so Android does not stop the service.

## Code layout

```
lib/
  main.dart                     app entry, theme
  screens/dashboard_screen.dart operator dashboard
  services/
    sms_service.dart            SMS listener; shared ingest path for foreground and background
    queue_service.dart          SQLite queue and message states
    api_service.dart            backend client (/sms, /health)
    reply_dispatcher.dart       parses backend replies and sends the SMS
    sync_service.dart           retry sweep and connectivity triggers
    background_service.dart     foreground service lifecycle
    outgoing_sender.dart        multipart SMS sending
  config/api_config.dart        API_BASE_URL
packages/telephony/             vendored fork of the telephony plugin (MIT)
```

## Build notes

- **SDK pins.** `compileSdk` is 36. Android Gradle plugin 9.0.1 cannot resolve the API 37 platform, which is installed as `android-37.0`. For the same reason:
  - `permission_handler_android` is pinned to 13.0.1 in `dependency_overrides`, because 14.x requires API 37;
  - the vendored `telephony` plugin compiles against API 36.

  Remove these pins after upgrading the Android Gradle plugin.
- **Plugin tests.** The vendored plugin's own tests need `mockito` and are not part of the app's `flutter test`. Run `flutter analyze lib test` to check only the app.

## Demo

1. Start the gateway on the relay phone.
2. From another phone, text the relay's number: `When should I plant maize?`
3. The reply arrives by SMS within seconds; the dashboard shows it as *Verified answer*.
4. Try `Ni ryari natera ibishyimbo?` (Kinyarwanda) and `My cow is not eating and has fever` (urgent escalation to the vet).

More questions: [docs/demo.md](../docs/demo.md).
