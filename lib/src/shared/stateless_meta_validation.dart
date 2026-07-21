import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/types/json_rpc.dart' as json_rpc;
import 'package:mcp_dart/src/types/validation.dart';

const _inputResponseRequestMethods = {
  Method.toolsCall,
  Method.promptsGet,
  Method.resourcesRead,
  Method.tasksUpdate,
};

void _validateMeta(Map<String, dynamic> json, String field) {
  if (!json.containsKey('_meta')) {
    return;
  }
  final meta = readJsonObject(json['_meta'], '$field._meta');
  json_rpc.validateMetaObject(meta, fieldName: '$field._meta');
}

Map<String, dynamic>? _jsonObject(Object? value) =>
    value is Map<String, dynamic> ? value : null;

void _validateObjectList(
  Object? value,
  String field,
  void Function(Map<String, dynamic> json, String field) validate,
) {
  if (value is! List) {
    return;
  }
  for (var index = 0; index < value.length; index++) {
    final json = _jsonObject(value[index]);
    if (json != null) {
      validate(json, '$field[$index]');
    }
  }
}

void _validateContentBlock(Map<String, dynamic> json, String field) {
  _validateMeta(json, field);
  switch (json['type']) {
    case 'resource':
      final resource = _jsonObject(json['resource']);
      if (resource != null) {
        _validateMeta(resource, '$field.resource');
      }
      break;
    case 'tool_result':
      _validateObjectList(
        json['content'],
        '$field.content',
        _validateContentBlock,
      );
      break;
  }
}

void _validateContentBlocks(Object? value, String field) {
  final single = _jsonObject(value);
  if (single != null) {
    _validateContentBlock(single, field);
    return;
  }
  _validateObjectList(value, field, _validateContentBlock);
}

void _validateTool(Map<String, dynamic> json, String field) {
  _validateMeta(json, field);
}

void _validateSamplingMessage(Map<String, dynamic> json, String field) {
  _validateMeta(json, field);
  _validateContentBlocks(json['content'], '$field.content');
}

void _validateCreateMessageParams(Map<String, dynamic> json, String field) {
  _validateObjectList(
    json['messages'],
    '$field.messages',
    _validateSamplingMessage,
  );
  _validateObjectList(json['tools'], '$field.tools', _validateTool);
}

void _validateInputRequests(Object? value, String field) {
  final requests = _jsonObject(value);
  if (requests == null) {
    return;
  }
  for (final entry in requests.entries) {
    final request = _jsonObject(entry.value);
    final requestField = '$field.${entry.key}';
    final params = request == null ? null : _jsonObject(request['params']);
    if (params == null) {
      continue;
    }
    switch (request!['method']) {
      case Method.samplingCreateMessage:
        _validateCreateMessageParams(params, '$requestField.params');
        break;
      case Method.rootsList:
        _validateMeta(params, '$requestField.params');
        break;
    }
  }
}

void _validateInputResponses(Object? value, String field) {
  final responses = _jsonObject(value);
  if (responses == null) {
    return;
  }
  for (final entry in responses.entries) {
    final response = _jsonObject(entry.value);
    if (response == null) {
      continue;
    }
    final responseField = '$field.${entry.key}';
    _validateMeta(response, responseField);
    if (response.containsKey('model') &&
        response.containsKey('role') &&
        response.containsKey('content')) {
      _validateSamplingMessage(response, responseField);
    }
    _validateObjectList(
      response['roots'],
      '$responseField.roots',
      _validateMeta,
    );
  }
}

void _validateCallToolResult(Map<String, dynamic> json, String field) {
  _validateMeta(json, field);
  _validateObjectList(
    json['content'],
    '$field.content',
    _validateContentBlock,
  );
}

void _validateDetailedTask(Map<String, dynamic> json, String field) {
  switch (json['status']) {
    case 'input_required':
      _validateInputRequests(json['inputRequests'], '$field.inputRequests');
      break;
    case 'completed':
      final result = _jsonObject(json['result']);
      if (result != null) {
        // The pinned Tasks extension supports task execution only for
        // tools/call, so the final result has CallToolResult's shape.
        _validateCallToolResult(result, '$field.result');
      }
      break;
  }
}

/// Validates schema-defined nested metadata in a modern outgoing request.
///
/// Arbitrary request arguments and extension payloads are intentionally not
/// traversed, even if they happen to contain a property named `_meta`.
void validateStatelessRequestMetaObjects(JsonRpcRequest request) {
  if (!_inputResponseRequestMethods.contains(request.method)) {
    return;
  }
  _validateInputResponses(
    request.params?['inputResponses'],
    '${request.method}.params.inputResponses',
  );
}

/// Validates schema-defined metadata in a modern result.
///
/// Arbitrary structured tool output and extension result fields are left
/// opaque so application data is never mistaken for protocol metadata.
void validateStatelessResultMetaObjects(
  JsonRpcRequest request,
  Map<String, dynamic> result,
) {
  _validateMeta(result, 'MCP stateless Result');

  if (result['resultType'] == resultTypeInputRequired) {
    _validateInputRequests(
      result['inputRequests'],
      'MCP stateless Result.inputRequests',
    );
    return;
  }

  switch (request.method) {
    case Method.resourcesList:
      _validateObjectList(
        result['resources'],
        'MCP stateless Result.resources',
        _validateMeta,
      );
      break;
    case Method.resourcesTemplatesList:
      _validateObjectList(
        result['resourceTemplates'],
        'MCP stateless Result.resourceTemplates',
        _validateMeta,
      );
      break;
    case Method.resourcesRead:
      _validateObjectList(
        result['contents'],
        'MCP stateless Result.contents',
        _validateMeta,
      );
      break;
    case Method.promptsList:
      _validateObjectList(
        result['prompts'],
        'MCP stateless Result.prompts',
        _validateMeta,
      );
      break;
    case Method.promptsGet:
      final messages = result['messages'];
      if (messages is List) {
        for (var index = 0; index < messages.length; index++) {
          final message = _jsonObject(messages[index]);
          final content =
              message == null ? null : _jsonObject(message['content']);
          if (content != null) {
            _validateContentBlock(
              content,
              'MCP stateless Result.messages[$index].content',
            );
          }
        }
      }
      break;
    case Method.toolsList:
      _validateObjectList(
        result['tools'],
        'MCP stateless Result.tools',
        _validateTool,
      );
      break;
    case Method.toolsCall:
      if (result['resultType'] == resultTypeComplete) {
        _validateCallToolResult(result, 'MCP stateless Result');
      }
      break;
    case Method.tasksGet:
      _validateDetailedTask(result, 'MCP stateless Result');
      break;
  }
}

/// Validates schema-defined metadata in a modern notification.
void validateStatelessNotificationMetaObjects(
  JsonRpcNotification notification,
) {
  final wire = notification.toJson();
  final params = _jsonObject(wire['params']);
  if (params != null) {
    _validateMeta(params, 'MCP stateless Notification.params');
  }
  if (notification.method == Method.notificationsTasks) {
    final task = params ?? notification.params;
    if (task != null) {
      _validateDetailedTask(task, 'MCP stateless Notification.params');
    }
  }
}
