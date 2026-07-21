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
final Expando<Object> _serverTaskOutputValidationScopes =
    Expando<Object>('mcp_dart.server.taskOutputValidationScope');
final Expando<Object> _transportTaskOutputValidationScopes =
    Expando<Object>('mcp_dart.transport.taskOutputValidationScope');

Object _taskOutputValidationScope(Object server) =>
    _serverTaskOutputValidationScopes[server] ?? server;

/// Assigns application-owned task validation state to a transport.
///
/// Stateless HTTP creates a fresh protocol instance for every POST. Sharing a
/// scope across those transports preserves the immutable output contract from
/// task creation until a later task retrieval validates its terminal result.
void writeTransportTaskOutputValidationScope(
  Object transport,
  Object scope,
) {
  _transportTaskOutputValidationScopes[transport] = scope;
}

/// Links [server] to task validation state supplied by [transport], if any.
void linkServerTaskOutputValidationScope(Object server, Object transport) {
  _serverTaskOutputValidationScopes[server] =
      _transportTaskOutputValidationScopes[transport];
}

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
  final scope = _taskOutputValidationScope(server);
  final validators = _taskOutputValidators[scope] ??
      <(String?, String), ServerTaskOutputValidator>{};
  validators[(sessionId, taskId)] = validator;
  _taskOutputValidators[scope] = validators;
}

/// Reads the output contract captured when a task was accepted.
ServerTaskOutputValidator? readServerTaskOutputValidator(
  Object server,
  String? sessionId,
  String taskId,
) =>
    _taskOutputValidators[_taskOutputValidationScope(server)]?[(
      sessionId,
      taskId,
    )];

/// Removes output-contract state for a task that can no longer return a result.
void removeServerTaskOutputValidator(
  Object server,
  String? sessionId,
  String taskId,
) {
  _taskOutputValidators[_taskOutputValidationScope(server)]
      ?.remove((sessionId, taskId));
}

/// Clears task output-contract state when a server session is closed.
void clearServerTaskOutputValidators(Object server) {
  final scope = _serverTaskOutputValidationScopes[server];
  _serverTaskOutputValidationScopes[server] = null;
  if (scope == null) {
    _taskOutputValidators[server] = null;
  }
}

/// Clears application-scoped task output contracts during owner shutdown.
void clearTaskOutputValidatorsForScope(Object scope) {
  _taskOutputValidators[scope] = null;
}
