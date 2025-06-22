# Web Platform Tests for MCP Dart

This directory contains tests that validate the MCP Dart client library works
correctly in web browser environments.

## Overview

The MCP Dart library has been refactored to remove `dart:io` dependencies and
use cross-platform packages (`package:http` and `package:eventflux`) to support
web compilation. These tests validate that the refactoring was successful and
the library works in browsers.

## Test Files

### `web_transport_test.dart`
Core web transport tests that verify:
- Transport instantiation in web environment
- Mock HTTP client integration
- Authentication flows
- Session management
- Error handling
- Web-specific features

### `web_integration_test.dart`
Integration tests that simulate real-world web usage:
- Cross-platform package compatibility
- Browser-specific feature integration
- Security considerations
- Error recovery scenarios
- Realistic usage patterns

### `manual_test.html`
Manual test page for browser validation:
- Visual verification of web compatibility
- Browser console testing
- Interactive test scenarios
- Platform feature validation

## Running the Tests

### Automated Tests

1. **Run all web tests:**
   ```bash
   dart test test/web/
   ```

2. **Run with specific browser:**
   ```bash
   dart test test/web/ -p chrome
   dart test test/web/ -p firefox
   ```

3. **Run with verbose output:**
   ```bash
   dart test test/web/ --reporter expanded
   ```

### Manual Testing

1. **Open the manual test page:**
   ```bash
   # Serve the test directory
   dart pub global activate dhttpd
   dhttpd --port 8080 test/web/
   
   # Then open http://localhost:8080/manual_test.html in your browser
   ```

2. **Test with a local server:** If you have a real MCP server running, you can
   test the connection by entering its URL in the manual test page.

## Test Configuration

The `dart_test.yaml` file configures the test runner for browser environments:
- Supports Chrome and Firefox
- Configures headless mode for CI/CD
- Sets appropriate timeouts for web tests

## Expected Results

### What Should Pass ✅
- Package imports and instantiation
- Transport creation with various options
- Mock HTTP client integration
- Authentication flow simulation
- Session management
- Error handling
- Browser feature integration

### What May Fail ❌ (Expected)
- Actual network connections to non-existent servers
- Real Server-Sent Events without a live server
- CORS issues when testing with real servers

## Validating the Refactoring

These tests validate that:

1. **No `dart:io` dependencies** - The library compiles and runs in web browsers
2. **Cross-platform packages work** - `package:http` and `package:eventflux`
   function correctly
3. **Transport interface preserved** - All existing Transport methods work as
   expected
4. **Web-specific features supported** - Browser storage, URLs, CORS headers,
   etc.
5. **Error handling robust** - Network errors are handled gracefully
6. **Authentication flows work** - OAuth redirects function in browser context

## Next Steps

After running these tests successfully:

1. **Create a real web application** that uses the MCP Dart client
2. **Test with a live MCP server** to validate end-to-end functionality
3. **Deploy to production** with confidence that web support is working

## Troubleshooting

### Common Issues

1. **Tests fail with "Platform not supported"**
   - Ensure you have Chrome or Firefox installed
   - Check that the test runner can find the browser executables

2. **Import errors**
   - Verify all dependencies are listed in `pubspec.yaml`
   - Run `dart pub get` to update dependencies

3. **Network-related test failures**
   - Expected for tests that try to connect to mock servers
   - Check that the test is properly expecting/handling these failures

4. **Browser crashes or hangs**
   - Reduce test timeout in `dart_test.yaml`
   - Run tests individually to isolate problematic tests

### Debugging Tips

1. **Use browser developer tools:**
   ```bash
   dart test test/web/ -p chrome --pause-after-load
   ```

2. **Check console output:**
   - Look for JavaScript errors in browser console
   - Verify network requests in browser Network tab

3. **Validate compilation:**
   ```bash
   dart compile js lib/mcp_dart.dart -o test/web/mcp_dart.js
   ```

## Contributing

When adding new web tests:

1. Use `@TestOn('browser')` annotation
2. Import `dart:html` for browser-specific features
3. Create mock implementations for external dependencies
4. Test both success and failure scenarios
5. Add appropriate timeout values for async operations

## Notes

- These tests validate **web compatibility**, not full functionality
- Full end-to-end testing requires a real MCP server
- The manual test page provides visual validation of web integration
- Tests are designed to run in CI/CD environments with headless browsers
