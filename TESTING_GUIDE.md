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

### 2. **Shell Script**
```bash
./scripts/test-all.sh           # All tests
./scripts/test-all.sh --vm-only # VM only
./scripts/test-all.sh --web-only # Web only
```

### 3. **Direct Dart Commands**
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

### Test Types by Category

#### VM Tests (Native Dart)
- **Client Tests:** MCP client functionality, protocol compliance, capability validation
- **Server Tests:** MCP server implementation, transport handling, session management  
- **Integration Tests:** End-to-end stdio communication between client and server
- **Protocol Tests:** JSON-RPC message handling, timeout management, error handling
- **Type Tests:** Serialization/deserialization of MCP protocol types

#### Web Tests (Browser Environment)
- **Transport Tests:** Browser-compatible HTTP transport, authentication, session APIs
- **Client Tests:** MCP client functionality in web browsers, capability registration
- **Integration Tests:** Cross-platform compatibility, security considerations, CORS handling
- **Real-World Tests:** End-to-end connectivity to live MCP servers (HuggingFace, DeepWiki)

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

### Test Categories
- **VM Tests:** Native Dart tests (client, server, integration, types, protocol)
- **Web Tests:** Browser-based tests (transport, client, integration, real-world)
- **Total:** Full cross-platform test coverage

## 🚨 Troubleshooting

### Common Issues

**"No tests ran" for web tests:**
```bash
# ❌ Wrong - missing platform
dart test test/web/

# ✅ Correct - with browser platform  
dart test test/web/ -p chrome
```

**Web test troubleshooting:**
- Web tests require browser platform specification (`-p chrome`)
- Transport connection lifecycle issues may occasionally occur
- Both VM and web tests provide comprehensive coverage

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

## 🎯 How to Run Different Test Categories

### VM Tests Only (Native Dart)
```bash
dart run test_runner.dart --vm-only
# OR
dart test --exclude-tags=web-only
```

### Web Tests Only (Browser)
```bash
dart run test_runner.dart --web-only
# OR  
dart test test/web/ -p chrome
```

### All Tests (VM + Web)
```bash
dart run test_runner.dart
# OR
./scripts/test-all.sh
```

### Specific Test Files
```bash
# Run specific VM test
dart test test/client/client_test.dart

# Run specific web test  
dart test test/web/web_transport_test.dart -p chrome
```

## 🎯 Best Practices

### For Development
1. **Use `dart run test_runner.dart`** for comprehensive cross-platform testing
2. **Use VS Code tasks** for integrated development workflow
3. **Run VM tests** for core library functionality validation
4. **Run web tests** for browser compatibility validation
5. **Use real-world integration tests** to validate live server connectivity

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
