# RFC: Synheart Core SDK Consent Integration

**RFC Number:** CONSENT-SDK-001  
**Status:** Draft  
**Created:** 2026-01-10  
**Author:** Synheart Engineering Team

---

## 1. Summary

This RFC defines how mobile applications integrate with the Synheart Consent Service via the Synheart Core SDK. It covers consent profile retrieval, user consent collection, SDK token issuance, and data upload authorization.

**Recommendation:** Integrate consent functionality directly into the existing **Synheart Core SDK** rather than creating a separate Consent SDK. This simplifies integration and ensures consent is enforced at the data collection point.

---

## 2. Background

### Problem Statement
Mobile apps using Synheart Core SDK need to:
1. Retrieve available consent profiles for their app
2. Present consent options to end users
3. Obtain authorization tokens for data uploads
4. Attach tokens to all cloud-bound biosignal data

### Current Architecture
```
┌─────────────────┐     ┌──────────────────┐     ┌────────────────┐
│   Mobile App    │────▶│ Synheart Core SDK│────▶│ Consent Service│
│  (iOS/Android)  │     │  (On-Device)     │     │   (Cloud)      │
└─────────────────┘     └──────────────────┘     └────────────────┘
                                │
                                ▼
                        ┌──────────────────┐
                        │  Cloud Ingest    │
                        │  (with token)    │
                        └──────────────────┘
```

---

## 3. Decision: Single SDK vs Separate Consent SDK

### Recommendation: Extend Synheart Core SDK

| Approach | Pros | Cons |
|----------|------|------|
| **Extend Core SDK** ✅ | Single integration point, consent enforced at source, simpler for developers | Slightly larger SDK |
| Separate Consent SDK | Modular | Two SDKs to maintain, risk of bypassing consent |

**Decision:** Add consent module to Synheart Core SDK. Consent must be enforced where data is collected.

---

## 4. SDK Integration Architecture

### 4.1 Consent Module API

```swift
// iOS Example
class SynheartConsentManager {
    
    /// Fetch available consent profiles for this app
    func getAvailableProfiles(completion: @escaping (Result<[ConsentProfile], Error>) -> Void)
    
    /// Present consent UI and collect user agreement
    func presentConsentFlow(profile: ConsentProfile, completion: @escaping (Result<ConsentToken, Error>) -> Void)
    
    /// Get current consent status
    func getCurrentConsent() -> ConsentStatus?
    
    /// Revoke consent (clears local token, notifies cloud)
    func revokeConsent(completion: @escaping (Result<Void, Error>) -> Void)
}

// Kotlin Example  
class SynheartConsentManager {
    
    suspend fun getAvailableProfiles(): List<ConsentProfile>
    
    suspend fun requestConsent(profile: ConsentProfile): ConsentToken
    
    fun getCurrentConsent(): ConsentStatus?
    
    suspend fun revokeConsent()
}
```

### 4.2 Data Types

```swift
struct ConsentProfile {
    let id: String
    let name: String
    let description: String
    let channels: ConsentChannels
    let cloudEnabled: Bool
    let vendorSyncEnabled: Bool
    let isDefault: Bool
}

struct ConsentChannels {
    let biosignals: BiosignalsConsent
    let phoneContext: PhoneContextConsent
    let behavior: BehaviorConsent
    let interpretation: InterpretationConsent
}

struct ConsentToken {
    let token: String          // JWT
    let expiresAt: Date
    let profileId: String
    let scopes: [String]       // e.g., ["bio:vitals", "cloud:upload"]
}

enum ConsentStatus {
    case granted(token: ConsentToken)
    case pending
    case denied
    case expired
}
```

---

## 5. API Endpoints (Consent Service)

### 5.1 Get Available Profiles
```http
GET /api/v1/apps/{app_id}/consent-profiles?active_only=true
Authorization: Bearer {app_api_key}

Response:
{
  "profiles": [
    {
      "id": "cp_xxx",
      "name": "Full Health Tracking",
      "description": "Complete access to vitals and sleep data",
      "channels": {
        "biosignals": { "vitals": true, "sleep": true },
        "interpretation": { "focus_estimation": false }
      },
      "cloud": true,
      "is_default": true
    }
  ]
}
```

### 5.2 Issue SDK Token (After User Consent)
```http
POST /api/v1/sdk/consent-token
Content-Type: application/json

{
  "app_id": "app_123",
  "device_id": "dev_456",
  "platform": "ios",
  "consent_profile_id": "cp_xxx",
  "user_id": "usr_789",        // Optional
  "region": "US"
}

Response:
{
  "token": "eyJhbGciOiJSUzI1NiIs...",
  "expires_at": "2026-01-10T19:00:00Z",
  "token_type": "Bearer",
  "scopes": ["bio:vitals", "bio:sleep", "cloud:upload"]
}
```

### 5.3 Token Claims (JWT)
```json
{
  "iss": "synheart-consent",
  "sub": "dev_456",
  "aud": ["synheart-ingest", "synheart-cloud"],
  "exp": 1736535600,
  "iat": 1736532000,
  "app_id": "app_123",
  "device_id": "dev_456",
  "profile_id": "cp_xxx",
  "region": "US",
  "scopes": ["bio:vitals", "bio:sleep", "cloud:upload"],
  "channels": {
    "biosignals.vitals": true,
    "biosignals.sleep": true
  }
}
```

---

## 6. SDK Integration Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                     Mobile App Startup                            │
└───────────────────────────┬──────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│ 1. SDK checks: Is there a valid ConsentToken in secure storage?  │
└───────────────────────────┬──────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
         [Yes, Valid]              [No or Expired]
              │                           │
              ▼                           ▼
┌─────────────────────┐     ┌─────────────────────────────────────┐
│ Resume data         │     │ 2. Fetch available consent profiles │
│ collection with     │     │    GET /apps/{app_id}/consent-profiles │
│ existing token      │     └───────────────────┬─────────────────┘
└─────────────────────┘                         │
                                                ▼
                            ┌─────────────────────────────────────┐
                            │ 3. Present consent UI to user       │
                            │    (Native or WebView)              │
                            └───────────────────┬─────────────────┘
                                                │
                                    ┌───────────┴───────────┐
                                    │                       │
                              [User Accepts]         [User Declines]
                                    │                       │
                                    ▼                       ▼
                            ┌──────────────────┐    ┌─────────────────┐
                            │ 4. Issue token   │    │ On-device only  │
                            │ POST /sdk/token  │    │ mode (no cloud) │
                            └────────┬─────────┘    └─────────────────┘
                                     │
                                     ▼
                            ┌──────────────────┐
                            │ 5. Store token   │
                            │ in Keychain/     │
                            │ KeyStore         │
                            └────────┬─────────┘
                                     │
                                     ▼
                            ┌──────────────────┐
                            │ 6. Begin data    │
                            │ collection with  │
                            │ token attached   │
                            └──────────────────┘
```

---

## 7. Implementation Details

### 7.1 Token Storage
| Platform | Storage | Encryption |
|----------|---------|------------|
| iOS | Keychain Services | Hardware-backed |
| Android | EncryptedSharedPreferences / KeyStore | AES-GCM |

### 7.2 Token Refresh
- Tokens have configurable TTL (default: 1 hour)
- SDK should refresh token 5 minutes before expiry
- Silent refresh if user hasn't revoked consent

### 7.3 Data Upload Authorization
```swift
// Every cloud upload MUST include the consent token
func uploadBiosignalData(data: HSIWindow) {
    guard let token = consentManager.getCurrentConsent()?.token else {
        // Queue locally, cannot upload without consent
        return
    }
    
    var request = URLRequest(url: ingestURL)
    request.setValue("Bearer \(token.token)", forHTTPHeaderField: "Authorization")
    request.setValue(token.profileId, forHTTPHeaderField: "X-Consent-Profile-ID")
    // ... upload
}
```

### 7.4 Offline Handling
1. SDK caches last valid token locally
2. Profile definitions cached with TTL
3. Data queued locally when offline
4. Token validated on reconnection before upload

---

## 8. Security Considerations

| Risk | Mitigation |
|------|------------|
| Token theft | Short TTL, device binding, secure storage |
| Token reuse | Device ID in claims, rate limiting |
| Consent bypass | Server-side validation on every upload |
| Man-in-middle | Certificate pinning, TLS 1.3 |

---

## 9. SDK Module Structure

```
SynheartCoreSDK/
├── Core/
│   ├── SynheartClient.swift
│   └── Configuration.swift
├── Biosignals/
│   ├── ECGProcessor.swift
│   └── HSICalculator.swift
├── Consent/                        # NEW MODULE
│   ├── ConsentManager.swift
│   ├── ConsentProfile.swift
│   ├── ConsentToken.swift
│   ├── ConsentStorage.swift        # Keychain wrapper
│   ├── ConsentAPI.swift            # REST client
│   └── ConsentUI/
│       ├── ConsentViewController.swift
│       └── ProfileSelectionView.swift
└── Upload/
    ├── UploadManager.swift
    └── TokenAttacher.swift         # Attaches token to uploads
```

---

## 10. Developer Integration Example

### iOS (Swift)
```swift
import SynheartCore

class AppDelegate {
    func applicationDidFinishLaunching() {
        // Initialize Synheart SDK
        let config = SynheartConfig(appId: "app_123", apiKey: "sk_...")
        SynheartSDK.initialize(config: config)
        
        // Check consent status
        SynheartSDK.consent.checkStatus { status in
            switch status {
            case .granted(let token):
                self.startDataCollection()
            case .pending, .expired:
                self.showConsentFlow()
            case .denied:
                self.runOfflineOnly()
            }
        }
    }
    
    func showConsentFlow() {
        SynheartSDK.consent.getAvailableProfiles { result in
            guard case .success(let profiles) = result else { return }
            
            // Present built-in consent UI or custom UI
            SynheartSDK.consent.presentConsentUI(
                profiles: profiles,
                from: self.window?.rootViewController
            ) { result in
                if case .success = result {
                    self.startDataCollection()
                }
            }
        }
    }
}
```

### Android (Kotlin)
```kotlin
import ai.synheart.sdk.SynheartSDK
import ai.synheart.sdk.consent.ConsentStatus

class MainActivity : AppCompatActivity() {
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Initialize
        SynheartSDK.initialize(this, "app_123", "sk_...")
        
        // Check consent
        lifecycleScope.launch {
            when (val status = SynheartSDK.consent.checkStatus()) {
                is ConsentStatus.Granted -> startDataCollection()
                is ConsentStatus.Pending,
                is ConsentStatus.Expired -> showConsentFlow()
                is ConsentStatus.Denied -> runOfflineOnly()
            }
        }
    }
    
    private fun showConsentFlow() {
        SynheartSDK.consent.launchConsentActivity(this) { result ->
            if (result.isSuccess) {
                startDataCollection()
            }
        }
    }
}
```

---

## 11. Summary

| Question | Answer |
|----------|--------|
| **Separate Consent SDK?** | No. Integrate into Synheart Core SDK |
| **Where to add?** | New `Consent` module in Core SDK |
| **Key APIs** | `getAvailableProfiles()`, `requestConsent()`, `getCurrentConsent()` |
| **Token Storage** | Keychain (iOS), KeyStore (Android) |
| **Token Attachment** | Automatic on all cloud uploads |
| **Offline Mode** | Cache profiles, queue data, validate on reconnect |

---

## 12. Next Steps

1. [ ] Add Consent module to Synheart Core SDK (iOS)
2. [ ] Add Consent module to Synheart Core SDK (Android)  
3. [ ] Implement consent UI components
4. [ ] Add token attachment to upload pipeline
5. [ ] Write integration tests
6. [ ] Update developer documentation

---

**Document History**
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-01-10 | Engineering | Initial draft |
