# Consent System Compliance Analysis

## Documentation Reference
[Synheart Core Consent System Documentation](https://docs.synheart.ai/synheart-core/consent-system)

## Summary
Our implementation has **significant compliance issues** that need to be addressed. The main issue is that we grant default consents for local processing, which violates the documentation's requirement that all consents default to `false` and data collection should not occur until explicit consent is granted.

---

## ✅ **COMPLIANT Areas**

### 1. Core Principles
- ✅ **Explicit Consent**: We require explicit consent via `grantConsent()` or consent profiles
- ✅ **Granular Control**: Each module (biosignals, behavior, motion, cloudUpload) can be controlled independently
- ✅ **Revocable**: `revokeConsent()` and `revokeConsentType()` methods exist
- ✅ **Enforced**: Modules check consent before collecting data
- ✅ **Transparent**: Consent status is queryable via `hasConsent()` and `getConsentStatus()`

### 2. Consent Types
- ✅ **biosignals**: Implemented (maps to WearModule)
- ✅ **behavior**: Implemented (maps to BehaviorModule)
- ✅ **motion/phoneContext**: Implemented as `motion` (maps to PhoneModule)
- ✅ **cloudUpload**: Implemented (maps to CloudConnectorModule)
- ⚠️ **focusEstimation**: Not explicitly tracked (handled via module enablement)
- ⚠️ **emotionEstimation**: Not explicitly tracked (handled via module enablement)
- ⚠️ **syni**: We have this but it's not in the documentation

### 3. Storage
- ✅ **Local encrypted storage**: Uses `FlutterSecureStorage` (Keychain/KeyStore)
- ✅ **Device-specific**: Consent stored per device
- ✅ **Versioned**: `ConsentSnapshot` includes `version` field

### 4. Module-Level Enforcement
- ✅ **WearModule**: Checks `_consent.current().biosignals` before returning features
- ✅ **PhoneModule**: Checks `_consent.current().motion` before returning features
- ✅ **BehaviorModule**: Checks `_consent.current().behavior` before processing events
- ✅ **CloudConnectorModule**: Checks `_consent.current().cloudUpload` before uploading

### 5. HSI Runtime Enforcement
- ✅ Returns `null` when consent denied (modules return `null` features)
- ✅ Does not generate synthetic data when consent is missing

### 6. Cloud Upload Enforcement
- ✅ Requires `cloudUpload` consent before enabling cloud sync
- ✅ Checks consent before each upload

### 7. API Methods (Partial)
- ✅ `hasConsent(String consentType)`: Implemented
- ✅ `grantConsent(String consentType)`: Implemented
- ✅ `revokeConsent()`: Implemented (revokes all via consent service)
- ✅ `revokeConsentType(String consentType)`: Implemented (granular revocation)
- ✅ `getConsentStatus()`: Implemented (returns `ConsentStatus` enum)
- ✅ `observe()`: Stream for consent changes (equivalent to `onConsentChanged`)

---

## ❌ **NON-COMPLIANT Areas**

### 1. **CRITICAL: Default Consent Values**

**Documentation Requirement:**
> All consents default to `false`. SDK should return empty/null state until consent is granted.

**Our Implementation:**
```dart
// In ConsentModule.loadConsent()
_currentConsent = ConsentSnapshot(
  biosignals: true, // ❌ VIOLATION: Should be false
  behavior: true,   // ❌ VIOLATION: Should be false
  motion: true,     // ❌ VIOLATION: Should be false
  cloudUpload: false, // ✅ Correct
  syni: false,
  timestamp: DateTime.now(),
);
```

**Impact:** 
- Data collection starts immediately without explicit user consent
- Violates "Explicit Consent" principle
- Violates "Enforced: Missing consent = no data collection" principle

**Fix Required:**
```dart
// Should default to all false
_currentConsent = ConsentSnapshot.none();
```

### 2. **Missing API Methods**

**Documentation Requires:**
- `getConsentStatus()` should return `Map<String, bool>` not `ConsentStatus` enum
- `deleteLocalData()`: **NOT IMPLEMENTED**
- `deleteCloudData()`: **NOT IMPLEMENTED**

**Current Implementation:**
```dart
// ❌ Returns enum, not Map
static ConsentStatus getConsentStatus() { ... }

// ❌ NOT IMPLEMENTED
// static Future<void> deleteLocalData() { ... }
// static Future<void> deleteCloudData() { ... }
```

### 3. **Consent Type Naming**

**Documentation Uses:**
- `phoneContext` (primary name)
- `motion` (alternative)

**Our Implementation:**
- Uses `motion` as primary name
- Accepts both `phoneContext` and `motion` in `hasConsent()` and `grantConsent()` ✅

**Status:** Mostly compliant, but should prefer `phoneContext` in documentation.

### 4. **Interpretation Module Consents**

**Documentation Requires:**
- `focusEstimation` consent type
- `emotionEstimation` consent type

**Our Implementation:**
- These are handled via module enablement (`enableFocus()`, `enableEmotion()`)
- Not tracked as explicit consent types

**Status:** Partially compliant - functionality exists but not as explicit consent types.

### 5. **Initial State Behavior**

**Documentation Requirement:**
> When SDK initializes, if no consent exists, SDK should:
> 1. Return empty/null state until consent is granted
> 2. Provide consent request callbacks to the app
> 3. Does NOT collect any data

**Our Implementation:**
- ✅ Returns null when consent denied (modules return null)
- ✅ Provides consent UI hooks via `ConsentUIManager`
- ❌ **BUT**: We grant default consents, so data collection starts immediately

---

## ⚠️ **PARTIALLY COMPLIANT Areas**

### 1. Consent Flow
- ✅ Checks for existing consent on initialization
- ✅ Provides UI hooks for consent requests
- ⚠️ But grants defaults instead of requiring explicit consent

### 2. Consent Revocation
- ✅ `revokeConsent()` clears token and notifies cloud
- ✅ `revokeConsentType()` allows granular revocation
- ✅ Modules immediately stop collecting when consent revoked
- ⚠️ Local data is NOT deleted (documentation says this is by design, but API should exist)

### 3. Consent Versioning
- ✅ `ConsentSnapshot` includes `version` field
- ❌ No `isConsentValid()` method to check version compatibility

---

## 🔧 **Required Fixes**

### Priority 1: Critical Compliance Issues

1. **Fix Default Consent Values**
   - Change `loadConsent()` to default all consents to `false`
   - Remove automatic granting of biosignals, behavior, motion
   - This is the most critical violation

2. **Add Missing API Methods**
   - Implement `deleteLocalData()`
   - Implement `deleteCloudData()`
   - Update `getConsentStatus()` to return `Map<String, bool>` (or add new method)

### Priority 2: Important Enhancements

3. **Add Consent Versioning Check**
   - Implement `isConsentValid(String consentType)` method
   - Check SDK version compatibility

4. **Documentation Alignment**
   - Prefer `phoneContext` over `motion` in public APIs
   - Add explicit `focusEstimation` and `emotionEstimation` consent types (optional)

---

## 📊 **Compliance Score**

| Category | Status | Score |
|----------|--------|-------|
| Core Principles | ⚠️ Partial | 60% |
| Consent Types | ✅ Good | 85% |
| Storage | ✅ Good | 100% |
| Enforcement | ✅ Good | 95% |
| API Methods | ⚠️ Partial | 70% |
| Initial State | ❌ Non-compliant | 30% |
| **Overall** | **⚠️ Needs Fixes** | **73%** |

---

## 🎯 **Recommendation**

**Immediate Action Required:**
1. Fix default consent values to be `false` (not `true`)
2. Implement `deleteLocalData()` and `deleteCloudData()` methods
3. Update `getConsentStatus()` to return `Map<String, bool>` or add separate method

**Future Enhancements:**
- Add explicit interpretation module consent types
- Add consent versioning validation
- Align naming with documentation (`phoneContext` as primary)

---

**Last Updated:** 2025-01-XX
**Documentation Version:** 1.0.0
**Implementation Version:** Current

