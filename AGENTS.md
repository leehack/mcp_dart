# mcp_dart Agent Guidelines

This document provides instructions and guidelines for AI agents and developers working on the `mcp_dart` repository.
Please review these guidelines before making changes to ensure consistency and quality.

## 1. Project Overview

`mcp_dart` is a Dart implementation of the Model Context Protocol (MCP) SDK.
It enables building MCP servers and clients to connect AI applications with external tools and resources.

- **SDK Version**: Dart ^3.0.0
- **Main Entry**: `lib/mcp_dart.dart`
- **Core Logic**: `lib/src/`
- **Tests**: `test/` (mirrors `lib/` structure)

## 2. Build, Lint, and Test Commands

All commands should be run from the root of the repository.

### Dependencies
```bash
dart pub get
```

### Formatting & Linting
Enforce code style and static analysis rules.
```bash
# Format code (applies changes)
dart format .

# Analyze code (reports lint errors)
dart analyze

# Fix auto-fixable lint errors
dart fix --apply
```

### Testing
Tests are crucial. Do not commit code that breaks existing tests.

```bash
# Run all tests
dart test

# Run a specific test file
dart test test/server/server_test.dart

# Run a specific test case by name (substring match)
dart test --name "Server initialization"

# Run tests with coverage (requires coverage package)
dart test --coverage=coverage
```

## 3. Code Style & Conventions

Adhere strictly to the following conventions.

### General
- **Dart Version**: Use features compatible with Dart 3.0+ (records, patterns, etc. if applicable).
- **Formatting**: Always run `dart format .` before submitting.
- **Comments**: Use `///` for public API documentation (classes, methods).
- **Trailing Commas**: Required. This helps `dart format` produce cleaner diffs.

### Naming
- **Classes/Types**: `PascalCase` (e.g., `McpServer`, `JsonRpcRequest`).
- **Variables/Methods**: `camelCase` (e.g., `capabilities`, `sendLoggingMessage`).
- **Private Members**: Prefix with `_` (e.g., `_capabilities`, `_oninitialize`).
- **Files**: `snake_case.dart` (e.g., `server_test.dart`).

### Imports
- **Ordering**:
    1. Dart SDK imports (`dart:async`, `dart:io`).
    2. Package imports (`package:mcp_dart/...`).
    3. Relative imports (only for strictly local usage, otherwise prefer `package:`).
- **Sort**: Alphabetical within each group.

### Types & Null Safety
- **Strict Typing**: Avoid `dynamic` unless absolutely necessary.
- **Null Safety**: Use `?` for nullable types. Use `required` for non-nullable named parameters.
- **Return Types**: Always declare return types (e.g., `Future<void>`, `String`, `bool`).
- **Const**: Use `const` constructors and literals where possible (`prefer_const_constructors`).

### Asynchronous Programming
- **Futures**: Return `Future<void>` instead of `void` for async functions to allow waiting.
- **Streams**: Use `StreamController` for event-based logic.
- **Async/Await**: Prefer `await` over `.then()`.

### Error Handling
- **Protocol Errors**: Use `McpError` with `ErrorCode` for MCP protocol-specific errors.
  ```dart
  throw McpError(ErrorCode.invalidParams.value, "Message text");
  ```
- **State Errors**: Use `StateError` for invalid object states.
- **Argument Errors**: Use `ArgumentError` for invalid inputs.
- **Try/Catch**: Handle specific exceptions. Avoid catching broad `Error` or `Exception` without rethrowing or logging.

## 4. Testing Guidelines

- **Framework**: Use `package:test`.
- **Structure**: Use `group()` to organize tests by class or feature.
- **Setup**: Use `setUp()` and `tearDown()` for resource management.
- **Mocks**: Use manual mocks or `MockTransport` (as seen in `server_test.dart`) to test protocol logic without network I/O.
- **Coverage**: Aim to test both success paths and error conditions (e.g., missing capabilities).

## 5. Development Workflow for Agents

1.  **Explore**: Read related files (`lib/src/...` and `test/...`) to understand the context.
2.  **Plan**: Create a brief plan of changes.
3.  **Edit**: Apply changes using `write` or `edit` tools.
    - Prefer editing existing files over creating new ones unless necessary.
4.  **Verify**:
    - Run `dart format .`
    - Run `dart analyze` (fix any issues).
    - Run related tests (e.g., `dart test test/path/to/relevant_test.dart`).
    - Run all tests (`dart test`) before finishing to ensure no regressions.

## 6. Example Patterns

**Class Definition:**
```dart
class MyServer extends Protocol {
  final String _name;

  MyServer(this._name, {super.options});

  Future<void> handleRequest() async {
    // ...
  }
}
```

**Test Definition:**
```dart
group('MyServer Tests', () {
  late MyServer server;

  setUp(() {
    server = MyServer('Test');
  });

  test('handles request correctly', () async {
    await server.handleRequest();
    // expectations...
  });
});
```
