# Development Guide - Synheart Core SDK

This guide helps you set up your local development environment for the Synheart Core SDK.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Project Structure](#project-structure)
- [Running the Project](#running-the-project)
- [Testing](#testing)
- [Debugging](#debugging)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)

## 🔧 Prerequisites

### Required Software

- **Flutter SDK**: 3.10.0 or higher
  ```bash
  flutter --version
  ```
- **Dart SDK**: 3.0.0 or higher (included with Flutter)
- **Git**: Latest version

### Platform-Specific Requirements

#### iOS Development
- **macOS**: Required for iOS development
- **Xcode**: 15.0 or higher
- **CocoaPods**: For iOS dependencies
  ```bash
  sudo gem install cocoapods
  ```

#### Android Development
- **Android Studio**: Latest version
- **Android SDK**: API level 26+ (Android 8.0+)
- **Java Development Kit (JDK)**: 11 or higher

#### Web Development (Optional)
- **Chrome**: For web testing

## 🚀 Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/synheart/synheart-core-flutter.git
cd synheart-core-flutter
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Verify Flutter Setup

```bash
flutter doctor
```

Fix any issues reported by `flutter doctor`.

### 4. Platform-Specific Setup

#### iOS Setup

```bash
cd ios
pod install
cd ..
```

**Note:** If you encounter CocoaPods issues:
```bash
sudo gem install cocoapods
pod repo update
```

#### Android Setup

1. Open Android Studio
2. Open the `android` folder
3. Let Gradle sync complete
4. Ensure Android SDK is properly configured

### 5. Run Tests

```bash
flutter test
```

If all tests pass, your setup is complete!

## 📁 Project Structure

```
synheart-core-flutter/
├── lib/                          # Main library code
│   ├── hsi_flutter.dart         # Public API entry point
│   └── src/
│       ├── modules/             # Module implementations
│       │   ├── base/            # Base classes
│       │   ├── capabilities/    # Capabilities module
│       │   ├── consent/         # Consent module
│       │   ├── wear/            # Wear module (uses synheart_wear)
│       │   ├── phone/           # Phone module
│       │   ├── behavior/        # Behavior module
│       │   ├── hsi_runtime/     # HSI Runtime module
│       │   └── cloud/           # Cloud Connector module
│       ├── core/                # Core functionality
│       ├── models/              # Data models
│       └── services/            # Services (auth, etc.)
├── test/                        # Test files
│   ├── unit/                   # Unit tests
│   └── integration/            # Integration tests
├── example/                     # Example apps
├── docs/                        # Documentation
│   ├── core-sdk-prd.md         # Product requirements
│   ├── core-sdk-module.md      # Module specifications
│   ├── internal-module.md      # Internal architecture
│   ├── native-module-mirror-status.md  # Cross-platform status
│   └── NATIVE_IMPLEMENTATIONS.md       # iOS/Android info
├── TASKS.md                     # Task list
├── CONTRIBUTING.md              # Contribution guide
├── DEVELOPMENT.md               # This file
└── README.md                    # Project overview
```

## 🔗 Related Repositories

This Flutter implementation is part of a multi-platform SDK:

- **Flutter:** `synheart-core-flutter` (this repository)
- **iOS:** `../synheart-core-ios` (Swift implementation)
- **Android:** `../synheart-core-android` (Kotlin implementation)

All three implementations share the same modular architecture. See [docs/NATIVE_IMPLEMENTATIONS.md](docs/NATIVE_IMPLEMENTATIONS.md) for details.

## 🏃 Running the Project

### Run Example App

```bash
flutter run -d <device-id>
```

List available devices:
```bash
flutter devices
```

### Run on Specific Platform

```bash
# iOS Simulator
flutter run -d ios

# Android Emulator
flutter run -d android

# Web
flutter run -d chrome
```

### Run with Debug Mode

```bash
flutter run --debug
```

### Run in Release Mode

```bash
flutter run --release
```

## 🧪 Testing

### Run All Tests

```bash
flutter test
```

### Run Specific Test File

```bash
flutter test test/modules/wear/wear_module_test.dart
```

### Run Tests with Coverage

```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Run Integration Tests

```bash
flutter test integration_test/
```

### Watch Mode (Auto-run tests on changes)

```bash
flutter test --watch
```

## 🐛 Debugging

### Debug Mode

Run in debug mode for breakpoints and debugging:
```bash
flutter run --debug
```

### Logging

The SDK uses structured logging. Set log level in configuration:

```dart
final config = SynheartConfig(
  logLevel: LogLevel.debug, // or info, warn, error
);
```

### Print Debugging

Add debug prints (will only show in debug mode):
```dart
debugPrint('Debug message: $variable');
```

### Platform-Specific Debugging

#### iOS
- Use Xcode for native iOS debugging
- Set breakpoints in Swift/Objective-C code
- View logs in Xcode console

#### Android
- Use Android Studio for native Android debugging
- Set breakpoints in Kotlin/Java code
- View logs with `adb logcat`

## 🔨 Common Tasks

### Add a New Module

1. Create module directory: `lib/src/modules/my_module/`
2. Create module class extending `BaseSynheartModule`
3. Implement required interfaces
4. Register module in `ModuleManager`
5. Add tests: `test/modules/my_module/my_module_test.dart`
6. Update documentation

### Add a New Data Model

1. Create model file: `lib/src/models/my_model.dart`
2. Add JSON serialization (use `json_annotation`)
3. Generate code: `flutter pub run build_runner build`
4. Add tests
5. Update documentation

### Update Dependencies

```bash
# Update dependencies
flutter pub upgrade

# Add new dependency
flutter pub add package_name

# Remove dependency
flutter pub remove package_name
```

### Generate Code

If using code generation (e.g., `json_serializable`):

```bash
flutter pub run build_runner build
```

Watch mode (auto-regenerate on changes):
```bash
flutter pub run build_runner watch
```

### Format Code

```bash
flutter format lib/ test/
```

### Analyze Code

```bash
flutter analyze
```

## 🔍 Troubleshooting

### Common Issues

#### Flutter Doctor Issues

**Issue:** Flutter doctor shows warnings
**Solution:** Follow the instructions provided by `flutter doctor`

#### iOS Build Issues

**Issue:** CocoaPods errors
```bash
cd ios
pod deintegrate
pod install
cd ..
```

**Issue:** Xcode version mismatch
- Update Xcode to latest version
- Run `flutter clean` and rebuild

#### Android Build Issues

**Issue:** Gradle sync fails
- Check Android SDK is installed
- Check Java/JDK version
- Run `flutter clean` and rebuild

**Issue:** Build errors
```bash
flutter clean
flutter pub get
cd android
./gradlew clean
cd ..
flutter run
```

#### Dependency Issues

**Issue:** Package not found
```bash
flutter pub get
flutter pub upgrade
```

**Issue:** Version conflicts
- Check `pubspec.yaml` for version constraints
- Update conflicting packages

#### Test Failures

**Issue:** Tests fail locally but pass in CI
- Run `flutter clean`
- Run `flutter pub get`
- Check for platform-specific issues

### Getting Help

1. Check [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) (if exists)
2. Search existing issues on GitHub
3. Ask in discussions
4. Create a new issue with:
   - Flutter/Dart version
   - Platform (iOS/Android/Web)
   - Error messages
   - Steps to reproduce

## 📚 Additional Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Documentation](https://dart.dev/guides)
- [Effective Dart](https://dart.dev/guides/language/effective-dart)
- [Project Documentation](docs/)

## 🎯 Next Steps

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines
2. Check [TASKS.md](TASKS.md) for available tasks
3. Review [docs/core-sdk-prd.md](docs/core-sdk-prd.md) for product requirements
4. Review [docs/internal-module.md](docs/internal-module.md) for architecture

---

**Author:** Israel Goytom  
**Last Updated:** 2025-01-XX

