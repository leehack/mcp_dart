import 'package:mcp_dart/mcp_dart.dart';

void main() {
  const parameters = StdioServerParameters(
    command: 'mcp-server',
    restartOnUnexpectedExit: false,
  );

  if (parameters.restartOnUnexpectedExit) {
    throw StateError('The stdio restart setting was not preserved.');
  }
}
