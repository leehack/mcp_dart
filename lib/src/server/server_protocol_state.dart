import 'package:mcp_dart/src/types.dart';

final Expando<String> _negotiatedProtocolVersions =
    Expando<String>('mcp_dart.server.negotiatedProtocolVersion');

typedef ServerTaskOutputValidator = void Function(
  Map<String, dynamic> result,
);

/// Internal marker that preserves a tool-output contract error through the
/// task-creation resolvability check without exposing unrelated handler errors.
final class ServerTaskOutputValidationError extends McpError {
  ServerTaskOutputValidationError(super.code, super.message, [super.data]);
}

final Expando<Map<(String?, String), ServerTaskOutputValidator>>
    _taskOutputValidators = Expando('mcp_dart.server.taskOutputValidators');

/// Reads the legacy protocol version negotiated by [server].
///
/// This package-internal state keeps the deprecated low-level server's public
/// interface unchanged while allowing the high-level server facade to preserve
/// version-specific wire behavior.
String? readServerProtocolVersion(Object server) =>
    _negotiatedProtocolVersions[server];

/// Records the legacy protocol [version] negotiated by [server].
void writeServerProtocolVersion(Object server, String? version) {
  _negotiatedProtocolVersions[server] = version;
}

/// Associates an accepted task with its immutable tool-output contract.
void writeServerTaskOutputValidator(
  Object server,
  String? sessionId,
  String taskId,
  ServerTaskOutputValidator validator,
) {
  final validators = _taskOutputValidators[server] ??
      <(String?, String), ServerTaskOutputValidator>{};
  validators[(sessionId, taskId)] = validator;
  _taskOutputValidators[server] = validators;
}

/// Reads the output contract captured when a task was accepted.
ServerTaskOutputValidator? readServerTaskOutputValidator(
  Object server,
  String? sessionId,
  String taskId,
) =>
    _taskOutputValidators[server]?[(sessionId, taskId)];

/// Removes output-contract state for a task that can no longer return a result.
void removeServerTaskOutputValidator(
  Object server,
  String? sessionId,
  String taskId,
) {
  _taskOutputValidators[server]?.remove((sessionId, taskId));
}

/// Clears task output-contract state when a server session is closed.
void clearServerTaskOutputValidators(Object server) {
  _taskOutputValidators[server] = null;
}
