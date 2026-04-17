# FakeCrypto — Flutter Android coin simulator

A fake-money crypto exchange that looks and feels like the real thing. Live prices come from the free CoinGecko public API. All balances are local to the device.

## Features

- Pick a starting class on first launch: Upper ($1M), Middle ($100K), Working ($10K), Lower ($1K).
- Single account per device, persisted with `shared_preferences`.
- Reset any time — your previous life is kept in the history log.
- "Start a game" lock disables reset until the game ends (prevents cheating in multiplayer).
- Every coin on CoinGecko's top market-cap pages (~500 coins).
- Price chart per coin with 1D / 7D / 30D / 90D / 1Y / MAX ranges.
- Search the market by symbol or name.
- Buy/Sell with a random 1–5s fill delay, just like a real exchange.
- Portfolio view with P/L vs. your starting balance.
- Dark Binance-style theme.

## Platform

Android only.

## Setup

You need the Flutter SDK installed (>=3.3). From this folder:

```
flutter create . --platforms=android --project-name=fake_crypto --org com.fakecrypto
flutter pub get
flutter run
```

The first `flutter create` call will generate the Android Gradle scaffolding without touching the existing `lib/`, `pubspec.yaml`, or the `AndroidManifest.xml` we ship.

## Building a release APK

```
flutter build apk --release
```

The APK will land at `build/app/outputs/flutter-apk/app-release.apk`.

## Notes

- CoinGecko's free endpoint is rate-limited. The app refreshes the market every 30 seconds and caches historical chart data per range.
- No servers, no accounts, no real money — all state is local.
