import 'package:mcp_dart/mcp_dart.dart';

void _verifyLegacySseExports(
  SseClientTransport? transport,
  SseClientTransportOptions? options,
) {
  if (transport != null || options != null) {
    throw StateError('Legacy SSE probe values must remain null.');
  }
}

void main() {
  const parameters = StdioServerParameters(
    command: 'mcp-server',
    restartOnUnexpectedExit: false,
  );

  if (parameters.restartOnUnexpectedExit) {
    throw StateError('The stdio restart setting was not preserved.');
  }
  _verifyLegacySseExports(null, null);
}
