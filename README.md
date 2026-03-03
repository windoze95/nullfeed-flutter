# NullFeed

**A Self-Hosted YouTube Media Center -- iOS & tvOS App**

[![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.6+-0175C2.svg)](https://dart.dev)
[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-000000.svg)](https://developer.apple.com/ios/)
[![tvOS 17+](https://img.shields.io/badge/tvOS-17%2B-000000.svg)](https://developer.apple.com/tvos/)
[![License: Private](https://img.shields.io/badge/license-private-red.svg)](#license)

NullFeed is a self-hosted YouTube media center that delivers a **streaming-service-quality** browsing and playback experience for your personal YouTube library. The Flutter app targets **iOS** and **tvOS**, connecting to the [NullFeed backend](https://github.com/nullfeed/nullfeed-backend) running on Docker (Unraid or any Docker host).

Think Netflix, but for your YouTube subscriptions -- channel-centric navigation, resume-aware playback, multi-user profiles, and AI-powered discovery.

---

## Features

- **Channel-Centric Navigation** -- Browse your subscriptions like shows in a streaming app, with channel art, banners, and episode lists.
- **Resume-Aware Home Screen** -- Continue Watching, New Episodes, and Recently Added rows keep you up to date.
- **Native Video Playback** -- AVPlayer-backed playback with seeking, Picture-in-Picture (iOS), and Siri Remote gestures (tvOS).
- **Multi-User Profiles** -- Netflix-style profile picker with independent subscriptions, watch history, and recommendations per user.
- **AI-Powered Discover Tab** -- Claude-powered channel and video suggestions based on your subscription graph.
- **Real-Time Download Tracking** -- WebSocket-driven progress indicators for active downloads.
- **Adaptive Layout** -- Single codebase optimized for iPhone, iPad, and Apple TV with 10-foot UI considerations.
- **tvOS Focus Engine** -- Full Siri Remote navigation support with focus-aware interactive elements.
- **Offline Metadata Caching** -- Hive-based local storage for user sessions and cached metadata.
- **Dark Theme** -- Media-center-class dark UI with true black backgrounds and deep purple accents.

---

## Screenshots

_Coming soon._

<!-- Add screenshots here:
![Home Screen](screenshots/home.png)
![Channel Detail](screenshots/channel_detail.png)
![Video Player](screenshots/player.png)
![Discover](screenshots/discover.png)
-->

---

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.27+ (stable channel)
- [Xcode 26](https://developer.apple.com/xcode/) with iOS and tvOS SDKs
- [CocoaPods](https://cocoapods.org/) (installed via `gem install cocoapods` or bundled with Xcode)
- A running [NullFeed backend](https://github.com/nullfeed/nullfeed-backend) instance
- iOS 17+ device or simulator / tvOS 17+ Apple TV or simulator

---

## Getting Started

1. **Clone the repository:**

   ```bash
   git clone https://github.com/nullfeed/nullfeed-flutter.git
   cd nullfeed-flutter
   ```

2. **Install dependencies:**

   ```bash
   flutter pub get
   ```

3. **Run code generation** (Freezed models, Riverpod, JSON serialization):

   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Install iOS pods:**

   ```bash
   cd ios && pod install && cd ..
   ```

5. **Run on iOS Simulator:**

   ```bash
   flutter run
   ```

6. **Run on tvOS Simulator:**

   ```bash
   flutter run -d apple-tv
   ```

---

## Project Structure

```
nullfeed-flutter/
├── lib/
│   ├── main.dart                           # App entry point
│   ├── app.dart                            # Root widget and MaterialApp config
│   ├── config/
│   │   ├── constants.dart                  # App-wide constants and defaults
│   │   ├── routes.dart                     # go_router route definitions
│   │   └── theme.dart                      # Dark theme and typography
│   ├── models/
│   │   ├── channel.dart                    # Channel data model (Freezed)
│   │   ├── feed.dart                       # Feed response models
│   │   ├── recommendation.dart             # AI recommendation model
│   │   ├── subscription.dart               # Subscription model
│   │   ├── user.dart                       # User profile model
│   │   └── video.dart                      # Video data model (Freezed)
│   ├── providers/
│   │   ├── auth_provider.dart              # Authentication and profile state
│   │   ├── channel_provider.dart           # Channel data providers
│   │   ├── discover_provider.dart          # AI recommendations provider
│   │   ├── download_provider.dart          # Download queue and progress
│   │   ├── feed_provider.dart              # Home feed data providers
│   │   ├── settings_provider.dart          # App settings and preferences
│   │   ├── video_provider.dart             # Video metadata and playback
│   │   └── websocket_provider.dart         # WebSocket connection management
│   ├── screens/
│   │   ├── channel_detail_screen.dart      # Channel page with video list
│   │   ├── discover_screen.dart            # AI-powered suggestions
│   │   ├── downloads_screen.dart           # Download queue and status
│   │   ├── home_screen.dart                # Resume-aware home feed
│   │   ├── library_screen.dart             # All subscribed channels
│   │   ├── profile_picker_screen.dart      # Multi-user profile selection
│   │   ├── settings_screen.dart            # Server connection and preferences
│   │   └── video_player_screen.dart        # Full-screen video player
│   ├── services/
│   │   ├── api_service.dart                # Dio HTTP client and API methods
│   │   ├── storage_service.dart            # Hive local storage
│   │   └── websocket_service.dart          # WebSocket client
│   └── widgets/
│       ├── adaptive_layout.dart            # iOS/tvOS adaptive layout wrapper
│       ├── channel_card.dart               # Channel artwork card
│       ├── content_row.dart                # Horizontal scrolling content row
│       ├── download_progress_indicator.dart # Download progress UI
│       ├── focus_wrapper.dart              # tvOS focus engine wrapper
│       ├── progress_bar.dart               # Video watch progress bar
│       ├── video_card.dart                 # Video thumbnail card
│       └── video_list_tile.dart            # Video list row item
├── ios/
│   ├── Podfile                             # CocoaPods dependencies
│   ├── Runner/
│   │   ├── AppDelegate.swift               # iOS app delegate
│   │   ├── Assets.xcassets/                # App icon assets
│   │   └── Info.plist                      # iOS configuration
│   └── Runner.xcodeproj/
│       └── project.pbxproj                 # Xcode project file
├── test/
│   └── widget_test.dart                    # Widget tests
├── analysis_options.yaml                   # Dart analyzer configuration
└── pubspec.yaml                            # Flutter package manifest
```

---

## Architecture

NullFeed follows a clean, provider-based architecture with clear separation of concerns.

### State Management -- Riverpod

All application state is managed through [Riverpod](https://riverpod.dev/) providers with code generation (`riverpod_generator`). Providers are organized by domain:

| Provider                   | Responsibility                              |
|----------------------------|---------------------------------------------|
| `authStateProvider`        | User session and profile management         |
| `channelsProvider`         | Channel list with subscribe/unsubscribe     |
| `homeFeedProvider`         | Aggregated home feed data                   |
| `discoverProvider`         | AI recommendation state                     |
| `downloadProvider`         | Real-time download progress                 |
| `videoProvider`            | Video metadata and playback state           |
| `settingsProvider`         | Server URL and quality preferences          |
| `webSocketConnectionProvider` | WebSocket lifecycle tied to auth state   |

### Routing -- go_router

Declarative routing via [go_router](https://pub.dev/packages/go_router) with support for deep linking and tab-based navigation across five main sections:

1. **Home** -- Resume-aware feed with Continue Watching, New Episodes, Recently Added rows
2. **Library** -- All subscribed channels in a grid layout
3. **Discover** -- AI-powered channel recommendations
4. **Downloads** -- Active and completed download queue
5. **Settings** -- Server connection, quality preferences, profile management

### Networking -- Dio

All backend communication uses [Dio](https://pub.dev/packages/dio) with interceptors for request logging, retry logic, and user session headers. WebSocket connections are managed separately via `web_socket_channel` for real-time events: download progress, completion notifications, new episode alerts, and recommendation refresh signals.

### Data Models -- Freezed

Immutable data models generated by [Freezed](https://pub.dev/packages/freezed) with JSON serialization via `json_serializable`. Models map directly to the backend API contract.

### Local Storage -- Hive

[Hive](https://pub.dev/packages/hive) provides lightweight local persistence for user sessions, server connection details, and cached metadata for offline resilience.

### Platform Adaptation

The `adaptive_layout.dart` widget and `focus_wrapper.dart` handle the differences between iOS (touch) and tvOS (focus engine / Siri Remote) interaction models. On tvOS, the app applies larger typography, higher-contrast cards, and couch-friendly spacing.

---

## Building

### iOS

```bash
flutter build ios --release
```

Open `ios/Runner.xcworkspace` in Xcode to archive and distribute via TestFlight or the App Store.

### tvOS

```bash
flutter build ios --release --target-platform tvos
```

tvOS builds share the same codebase. Platform-specific adaptations are handled at runtime through Flutter's platform detection and the adaptive layout widgets.

### Code Generation

After modifying any Freezed model, Riverpod provider, or JSON-annotated class:

```bash
dart run build_runner build --delete-conflicting-outputs
```

For continuous rebuilds during development:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

---

## Configuration

On first launch, the app prompts you to enter your NullFeed server address:

- **Server URL**: `http://<server-ip>:8484` (or your custom port)

This is stored locally via Hive and can be changed at any time in **Settings**. The settings screen includes a connection test to verify the backend is reachable.

After connecting, select or create a user profile to begin using the app.

---

## Dependencies

### Runtime

| Package                | Version  | Purpose                              |
|------------------------|----------|--------------------------------------|
| `flutter_riverpod`     | ^2.6.1   | State management                     |
| `riverpod_annotation`  | ^2.6.1   | Riverpod code generation annotations |
| `dio`                  | ^5.7.0   | HTTP client                          |
| `video_player`         | ^2.9.2   | Native video playback (AVPlayer)     |
| `hive` / `hive_flutter`| ^2.2.3  | Local key-value storage              |
| `go_router`            | ^14.8.1  | Declarative routing                  |
| `cached_network_image` | ^3.4.1   | Image caching and placeholders       |
| `web_socket_channel`   | ^3.0.1   | WebSocket client                     |
| `freezed_annotation`   | ^2.4.4   | Immutable model annotations          |
| `json_annotation`      | ^4.9.0   | JSON serialization annotations       |
| `intl`                 | ^0.19.0  | Date/number formatting               |
| `shimmer`              | ^3.0.0   | Loading placeholder animations       |

### Dev

| Package                | Version  | Purpose                              |
|------------------------|----------|--------------------------------------|
| `flutter_lints`        | ^5.0.0   | Lint rules                           |
| `build_runner`         | ^2.4.13  | Code generation runner               |
| `freezed`              | ^2.5.7   | Immutable model code generation      |
| `json_serializable`    | ^6.9.0   | JSON serialization code generation   |
| `riverpod_generator`   | ^2.6.2   | Riverpod provider code generation    |

---

## License

Private -- All rights reserved.
