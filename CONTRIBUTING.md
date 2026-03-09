# Contributing to Synheart Core SDK

Thank you for your interest in contributing to the Synheart Core SDK! This document provides guidelines and instructions for contributing.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)
- [Module-Specific Guidelines](#module-specific-guidelines)

## 📜 Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Follow the project's coding standards
- Respect privacy and security requirements

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.10.0 or higher
- Dart SDK 3.0.0 or higher
- iOS: Xcode 15+ (for iOS development)
- Android: Android Studio with Android SDK 26+
- Git

### Initial Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/synheart/synheart-core-dart.git
   cd synheart-core-dart
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run tests to verify setup**
   ```bash
   flutter test
   ```

4. **Read the documentation**
   - [README.md](README.md) - Project overview
   - [CHANGELOG.md](CHANGELOG.md) - Release history

## 🔄 Development Workflow

### 1. Pick a Task

- Check GitHub Issues for available tasks
- Comment on an issue to claim it

### 2. Create a Branch

```bash
# Create a feature branch
git checkout -b feature/your-feature-name

# Or a bugfix branch
git checkout -b fix/bug-description
```

**Branch naming conventions:**
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `test/` - Test additions/updates

### 3. Make Changes

- Write code following our [coding standards](#coding-standards)
- Add tests for your changes
- Update documentation as needed
- Update the issue to mark your task as in progress

### 4. Test Your Changes

```bash
# Run all tests
flutter test

# Run tests for a specific file
flutter test test/path/to/test_file.dart

# Run with coverage
flutter test --coverage
```

### 5. Commit Your Changes

```bash
git add .
git commit -m "feat: add feature description"
```

**Commit message conventions:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Test additions/updates
- `chore:` - Build process or auxiliary tool changes

### 6. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub with:
- Clear description of changes
- Reference to related issue/task
- Screenshots (if UI changes)
- Test results

## 📝 Coding Standards

### Dart Style Guide

- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines
- Use `dart format` to format code
- Follow the project's `analysis_options.yaml`

### Code Organization

```
lib/
├── src/
│   ├── modules/          # Module implementations
│   │   ├── base/         # Base classes and interfaces
│   │   ├── capabilities/ # Capabilities module
│   │   ├── consent/      # Consent module
│   │   ├── wear/         # Wear module
│   │   ├── phone/        # Phone module
│   │   ├── behavior/     # Behavior module
│   │   ├── hsi_runtime/  # HSI Runtime module
│   │   └── cloud/        # Cloud Connector module
│   ├── core/             # Core functionality
│   ├── models/           # Data models
│   └── services/         # Services (auth, etc.)
```

### Naming Conventions

- **Files**: `snake_case.dart`
- **Classes**: `PascalCase`
- **Variables/Functions**: `camelCase`
- **Constants**: `lowerCamelCase` or `UPPER_SNAKE_CASE`
- **Private members**: `_leadingUnderscore`

### Documentation

- Document all public APIs with dartdoc
- Include code examples in documentation
- Document complex algorithms and business logic
- Keep comments up-to-date with code changes

### Example

```dart
/// Provides biosignal features for a given time window.
///
/// This method collects biosignal data from configured sources,
/// normalizes it, and returns aggregated features for the specified window.
///
/// Example:
/// ```dart
/// final features = wearModule.features(WindowType.window30s);
/// if (features != null) {
///   print('HR: ${features.hrAverage}');
/// }
/// ```
///
/// Returns `null` if:
/// - Consent for biosignals is not granted
/// - No data is available for the window
/// - Module is not enabled
WearWindowFeatures? features(WindowType window);
```

## 🧪 Testing Guidelines

### Test Structure

- Unit tests: `test/unit/`
- Integration tests: `test/integration/`
- Widget tests: `test/widget/`

### Test Naming

```dart
test('should return null when consent is denied', () {
  // Test implementation
});

group('WearModule', () {
  test('should initialize successfully', () {
    // Test implementation
  });
  
  test('should handle missing data gracefully', () {
    // Test implementation
  });
});
```

### Test Coverage

- Aim for 80%+ code coverage
- Test happy paths and error cases
- Test edge cases and boundary conditions
- Mock external dependencies

### Running Tests

```bash
# All tests
flutter test

# Specific test file
flutter test test/modules/wear/wear_module_test.dart

# With coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

## 📚 Documentation

### Code Documentation

- Use dartdoc for all public APIs
- Include examples in documentation
- Document parameters and return values
- Document exceptions that may be thrown

### README Updates

- Update README.md if you add new features
- Update setup instructions if needed
- Add examples for new functionality

### Architecture Documentation

- Document design decisions in code comments

## 🔀 Submitting Changes

### Pull Request Checklist

- [ ] Code follows project style guidelines
- [ ] Tests added/updated and passing
- [ ] Documentation updated
- [ ] Related issue updated
- [ ] No breaking changes (or documented if intentional)
- [ ] Performance impact considered
- [ ] Privacy/security implications reviewed

### Pull Request Template

```markdown
## Description
Brief description of changes

## Related Task/Issue
Closes #issue-number

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing performed

## Checklist
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] Tests passing
- [ ] No new warnings
```

## 🏗️ Module-Specific Guidelines

### Module Development

All modules should:
- Extend `SynheartModule` base class
- Handle consent checks
- Respect capability levels
- Provide proper error handling
- Include comprehensive tests

### Module Structure

```dart
class MyModule extends BaseSynheartModule {
  @override
  String get moduleId => 'my_module';

  @override
  Future<void> onInitialize() async {
    // Initialize module
  }

  @override
  Future<void> onStart() async {
    // Start module operation
  }

  @override
  Future<void> onStop() async {
    // Stop module operation
  }

  @override
  Future<void> onDispose() async {
    // Cleanup resources
  }
}
```

### Consent Handling

Always check consent before collecting data:

```dart
@override
MyFeatures? features(WindowType window) {
  // Check consent first
  final consent = _consentProvider.current();
  if (!consent.allows(ConsentType.myDataType)) {
    return null; // Return null if consent denied
  }
  
  // Continue with feature collection
}
```

### Capability Handling

Respect capability levels:

```dart
final capability = _capabilityProvider.capability(Module.myModule);
if (capability == CapabilityLevel.core) {
  // Only provide core features
} else if (capability == CapabilityLevel.extended) {
  // Provide extended features
}
```

## 🐛 Reporting Bugs

### Bug Report Template

```markdown
## Description
Clear description of the bug

## Steps to Reproduce
1. Step one
2. Step two
3. ...

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Environment
- Flutter version:
- Dart version:
- Platform: iOS/Android/Web
- OS version:

## Additional Context
Any other relevant information
```

## 💡 Feature Requests

### Feature Request Template

```markdown
## Feature Description
Clear description of the feature

## Use Case
Why is this feature needed?

## Proposed Solution
How should it work?

## Alternatives Considered
Other solutions you've considered

## Additional Context
Any other relevant information
```

## 📞 Getting Help

- Check [README.md](README.md) for setup and architecture
- Open an issue for bugs or feature requests
- Ask questions in discussions

## 🙏 Thank You!

Your contributions make Synheart Core SDK better for everyone. Thank you for taking the time to contribute!

---

**Author:** Israel Goytom  
**Last Updated:** 2026-03-07

