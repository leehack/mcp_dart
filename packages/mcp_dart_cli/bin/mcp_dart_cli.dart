/// Proxy entrypoint for `dart run`.
///
/// `dart run` expects an executable named after the package (`mcp_dart_cli`).
/// This file delegates to the actual entrypoint in `mcp_dart.dart`.
library;

import 'mcp_dart.dart' as original;

void main(List<String> arguments) {
  original.main(arguments);
}
