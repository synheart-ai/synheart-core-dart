# Example App Setup Guide

This guide will help you configure the Synheart Core SDK example app with your own credentials and settings.

## Overview

The example app demonstrates how to integrate the Synheart Core SDK into a Flutter application. To use certain features (like consent service integration), you'll need to provide your own credentials.

## Prerequisites

- Flutter SDK installed (see [Flutter documentation](https://docs.flutter.dev/get-started/install))
- A Synheart account with access to:
  - Consent Service API credentials (for consent service features)
  - Cloud Platform credentials (for cloud sync features)

## Configuration

### 1. Consent Service Configuration

The consent service allows you to manage user consent for data collection and processing. To enable consent service features:

#### Step 1: Obtain Your Credentials

You'll need:
- **App ID**: Your application identifier from the Synheart platform
- **App API Key**: Your API key for authenticating with the consent service

Contact your Synheart representative or visit the [Synheart Developer Portal](https://platform.synheart.ai/) to obtain these credentials.

#### Step 2: Configure in the Example App

Open `lib/providers/synheart_provider.dart` and locate the `initialize` method. Uncomment and update the `ConsentConfig`:

```dart
consentConfig: ConsentConfig(
  appId: 'your-app-id-here',           // Replace with your App ID
  appApiKey: 'your-api-key-here',      // Replace with your API Key
  platform: 'flutter',                  // Platform identifier
  userId: userId,                       // User ID (passed to initialize)
  region: 'US',                         // Optional: Region code
),
```

#### Step 3: Device ID

The `deviceId` is optional. If not provided, the SDK will automatically generate and persist a unique device ID for each device. You can provide a custom device ID if needed:

```dart
consentConfig: ConsentConfig(
  appId: 'your-app-id-here',
  appApiKey: 'your-api-key-here',
  deviceId: 'custom-device-id',  // Optional: Custom device ID
  // ... other fields
),
```

### 2. Cloud Configuration (Optional)

The cloud configuration enables uploading HSV snapshots to the Synheart Platform. To enable cloud sync features:

#### Step 1: Obtain Your Credentials

You'll need:
- **Tenant ID**: Your tenant identifier from the Synheart platform
- **HMAC Secret**: Your HMAC secret for signing requests
- **Subject ID**: Pseudonymous user identifier (typically the same as `userId`)
- **Instance ID**: Unique identifier for this SDK instance (can be auto-generated)

Contact your Synheart representative or visit the [Synheart Developer Portal](https://platform.synheart.ai/) to obtain these credentials.

#### Step 2: Configure in the Example App

Open `lib/providers/synheart_provider.dart` and locate the `initialize` method. Uncomment and update the `CloudConfig`:

```dart
cloudConfig: CloudConfig(
  tenantId: 'your-tenant-id',            // Replace with your Tenant ID
  hmacSecret: 'your-hmac-secret',       // Replace with your HMAC Secret
  subjectId: userId,                     // Pseudonymous user identifier
  instanceId: 'unique-instance-id',      // Unique instance identifier (UUID recommended)
),
```

**Security Note**: Never commit API keys, secrets, or credentials to version control. Consider using environment variables or secure storage solutions.

### 3. Environment Variables (Recommended)

For better security, use environment variables instead of hardcoding credentials:

1. Create a `.env` file in the `example` directory (add it to `.gitignore`):

```env
SYNHEART_APP_ID=your-app-id-here
SYNHEART_API_KEY=your-api-key-here
SYNHEART_TENANT_ID=your-tenant-id
SYNHEART_HMAC_SECRET=your-hmac-secret
```

2. Add `flutter_dotenv` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_dotenv: ^5.1.0
```

3. Load environment variables in your app:

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

// In main() or before initialization
await dotenv.load(fileName: ".env");

// Use in configuration
consentConfig: ConsentConfig(
  appId: dotenv.env['SYNHEART_APP_ID']!,
  appApiKey: dotenv.env['SYNHEART_API_KEY']!,
  platform: 'flutter',
  userId: userId,
  region: 'US',
),
cloudConfig: CloudConfig(
  tenantId: dotenv.env['SYNHEART_TENANT_ID']!,
  hmacSecret: dotenv.env['SYNHEART_HMAC_SECRET']!,
  subjectId: userId,
  instanceId: 'unique-instance-id', // Or generate UUID
),
```

## Running the Example App

1. **Install dependencies**:
   ```bash
   cd example
   flutter pub get
   ```

2. **Configure credentials** (see Configuration section above)

3. **Run the app**:
   ```bash
   flutter run
   ```

## Features

The example app demonstrates:

- **SDK Initialization**: How to initialize the Synheart Core SDK
- **HSV Updates**: Subscribing to Human State Vector updates
- **Emotion Detection**: Enabling and displaying emotion inference
- **Focus Detection**: Enabling and displaying focus inference
- **Consent Management**: Managing user consent for data collection
- **Cloud Sync**: Uploading HSV snapshots to the cloud (requires credentials)
- **Behavior Tracking**: Monitoring user-device interactions

## Troubleshooting

### Consent Service Not Working

- **Check credentials**: Ensure your `appId` and `appApiKey` are correct
- **Check logs**: Look for error messages in the console output

### No Data Appearing

- **Check permissions**: Ensure health data permissions are granted (iOS HealthKit, Android Health Connect)
- **Wait for initialization**: The SDK needs time to collect initial data (typically 30-60 seconds)
- **Enable features**: Make sure emotion/focus modules are enabled in the UI

### Cloud Sync Not Working

- **Verify CloudConfig**: Ensure all required fields are provided
- **Check consent**: Cloud upload requires user consent (`cloudUpload: true`)
- **Network connectivity**: Ensure the device has internet connectivity

## Security Best Practices

1. **Never commit credentials**: Always use `.gitignore` for files containing secrets
2. **Use environment variables**: Store sensitive data in environment variables or secure storage
3. **Rotate keys regularly**: Regularly rotate your API keys for security
4. **Use different keys per environment**: Use separate credentials for development, staging, and production
5. **Monitor usage**: Monitor API usage to detect unauthorized access

## Getting Help

- **Documentation**: See the main [Synheart Core SDK README](../README.md)
- **Issues**: Report issues on [GitHub](https://github.com/synheart-ai/synheart-core-dart/issues)
- **Support**: Contact support@synheart.io for assistance

## Next Steps

After setting up the example app:

1. Explore the different screens and features
2. Review the code to understand SDK integration patterns
3. Adapt the example code for your own application
4. Refer to the [main SDK documentation](../README.md) for advanced features

---

**Important**: This example app is for demonstration purposes. In production applications, always:
- Store credentials securely
- Implement proper error handling
- Follow platform-specific privacy guidelines
- Obtain proper user consent before collecting data

