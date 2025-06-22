# Testing Guide for MCP Dart

## 🎯 Quick Start

**Run all tests (VM + Web):**
```bash
dart run test_runner.dart
```

## 📋 Available Commands

### 1. **Dart Test Runner (Recommended)**
```bash
# Run all tests
dart run test_runner.dart

# Run with verbose output
dart run test_runner.dart --verbose

# Run only web tests
dart run test_runner.dart --web-only

# Run only VM tests  
dart run test_runner.dart --vm-only
```

### 3. **Shell Script**
```bash
./scripts/test-all.sh           # All tests
./scripts/test-all.sh --vm-only # VM only
./scripts/test-all.sh --web-only # Web only
```

### 4. **Direct Dart Commands**
```bash
# VM tests (what VS Code runs by default)
dart test --exclude-tags=web-only

# Web tests (what VS Code can't run automatically)
dart test test/web/ -p chrome
dart test test/web/ -p firefox

# All tests (doesn't work well - mix of platforms)
dart test  # ❌ This won't run web tests properly
```

## 🔧 VS Code Integration

### Tasks (Ctrl+Shift+P → "Tasks: Run Task")
- **Test: All (VM + Web)** - Runs comprehensive test suite
- **Test: VM Only** - Runs standard Dart tests
- **Test: Web Only** - Runs browser tests
- **Test: Web (Firefox)** - Runs web tests in Firefox

### Debug Configurations (F5)
- **Run All Tests** - Debug the test runner
- **Run VM Tests** - Debug VM tests only
- **Run Web Tests** - Debug web tests only

### Why VS Code Test Runner Doesn't Work for Web Tests

VS Code's built-in test runner (`Dart: Run All Tests`) only runs Dart VM tests. It doesn't:
- ✅ Run `dart test` (VM tests)
- ❌ Run `dart test test/web/ -p chrome` (web tests)

The web tests require a browser platform (`-p chrome`) which VS Code doesn't handle automatically.

## 🌐 Web Test Details

### Web Test Types
1. **Core Transport Tests** (`test/web/web_transport_test.dart`)
   - Transport instantiation in browser
   - HTTP client integration
   - Authentication flows
   - Session management

2. **Integration Tests** (`test/web/web_integration_test.dart`)
   - Browser environment validation
   - Cross-platform package compatibility
   - Security considerations
   - Error handling

### Web Test Requirements
- Chrome or Firefox browser installed
- Network access for compilation
- Headless browser support for CI/CD

### Manual Web Testing
- Open `test/web/manual_test.html` in browser
- Interactive validation of web features
- Visual confirmation of functionality

## 📊 Test Results

### Expected Output
```
🧪 MCP Dart Comprehensive Test Runner
=====================================

🌐 Running Web Tests (Chrome)...
✅ Web tests passed!

🖥️  Running VM Tests...
✅ VM tests passed!

🎉 All tests passed! Total time: 10s
```

### Test Counts
- **VM Tests:** ~105 tests
- **Web Tests:** 16 tests  
- **Total:** ~121 tests

## 🚨 Troubleshooting

### Common Issues

**"No tests ran" for web tests:**
```bash
# ❌ Wrong - missing platform
dart test test/web/

# ✅ Correct - with browser platform  
dart test test/web/ -p chrome
```

**VS Code not running web tests:**
- Use Tasks or Debug configurations instead
- Or run from terminal: `dart run test_runner.dart`

**Browser not found:**
- Install Chrome: `brew install chrome` (Mac)
- Install Firefox: `brew install firefox` (Mac)  
- Use headless mode in CI/CD

**Compilation errors:**
- Check `pubspec.yaml` dependencies
- Run `dart pub get`
- Verify web compatibility

### Debugging Tips

**Verbose output:**
```bash
dart run test_runner.dart --verbose
```

**Run specific test:**
```bash
dart test test/web/web_transport_test.dart -p chrome
```

**Check browser console:**
```bash
dart test test/web/ -p chrome --pause-after-load
```

## 🎯 Best Practices

### For Development
1. **Use `dart run test_runner.dart`** for comprehensive testing
4. **Use VS Code tasks** for integrated development workflow

### For CI/CD
```yaml
# GitHub Actions example
- name: Run all tests
  run: dart run test_runner.dart
```

## 📚 Additional Resources

- **Web Test Details:** [`test/web/README.md`](test/web/README.md)
- **Design Document:** [`web-design-doc.md`](web-design-doc.md)
- **Validation Summary:** [`WEB_VALIDATION_SUMMARY.md`](WEB_VALIDATION_SUMMARY.md)
