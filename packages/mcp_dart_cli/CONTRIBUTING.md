# Contributing to mcp_dart_cli

Thanks for considering contributing to `mcp_dart_cli`! We appreciate your help in making this project better.

## Getting Started

1.  **Fork the repository** on GitHub.
2.  **Clone your fork** locally:
    ```bash
    git clone https://github.com/your-username/mcp_dart.git
    cd mcp_dart/packages/mcp_dart_cli
    ```
3.  **Install dependencies**:
    ```bash
    dart pub get
    ```

## Running Tests

We use `test` for testing.

To run all tests:
```bash
dart test
```

## specific tests:
```bash
dart test test/src/some_test.dart
```

## Code Style

- Format your code:
  ```bash
  dart format .
  ```
- Analyze your code:
  ```bash
  dart analyze
  ```
- Ensure all checks pass before submitting a PR.

## Submitting a Pull Request

1.  Create a new branch for your feature or fix.
2.  Commit your changes with clear messages.
3.  Push your branch to your fork.
4.  Open a Pull Request against the `main` branch of the `mcp_dart` repository.
