import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

typedef Parser = void Function(Map<String, dynamic> json);

JsonRpcResponse _response(Map<String, dynamic> json) {
  final message = JsonRpcMessage.fromJson(json);
  if (message is! JsonRpcResponse) {
    throw FormatException('Expected JsonRpcResponse, got $message');
  }
  return message;
}

void _parseErrorDataOrWrapper(Map<String, dynamic> json) {
  if (json.containsKey('error')) {
    JsonRpcError.fromJson(json);
    return;
  }
  JsonRpcErrorData.fromJson(json);
}

void _parseRequestLike(Map<String, dynamic> json) {
  if (json.containsKey('jsonrpc')) {
    JsonRpcMessage.fromJson(json);
    return;
  }

  final method = json['method'];
  if (method is! String) {
    throw const FormatException('Expected request-like method');
  }

  final params = json['params'];
  final paramsJson = params is Map ? Map<String, dynamic>.from(params) : null;

  switch (method) {
    case Method.elicitationCreate:
      if (paramsJson == null) {
        throw const FormatException('elicitation/create params are required');
      }
      ElicitRequest.fromJson(
        paramsJson,
        protocolVersion: latestDraftProtocolVersion,
      );
      return;
    case Method.samplingCreateMessage:
      if (paramsJson == null) {
        throw const FormatException(
          'sampling/createMessage params are required',
        );
      }
      CreateMessageRequest.fromJson(paramsJson);
      return;
    case Method.rootsList:
      if (paramsJson != null && paramsJson.isNotEmpty) {
        throw const FormatException('roots/list input request has no params');
      }
      return;
    default:
      throw FormatException('No request-like parser for method $method');
  }
}

void _parseJsonRpc(Map<String, dynamic> json) {
  JsonRpcMessage.fromJson(json);
}

void _parseSchema(Map<String, dynamic> json) {
  JsonSchema.fromJson(json);
}

void _parseInputResponses(Map<String, dynamic> json) {
  InputResponse.mapFromJson(json, 'InputResponses');
}

final Map<String, Parser> _parsers = {
  'AudioContent': (json) => AudioContent.fromJson(json),
  'BlobResourceContents': (json) => ResourceContents.fromJson(json),
  'BooleanSchema': _parseSchema,
  'CallToolRequest': _parseJsonRpc,
  'CallToolRequestParams': (json) => CallToolRequest.fromJson(json),
  'CallToolResult': (json) => CallToolResult.fromJson(json),
  'CallToolResultResponse': (json) {
    CallToolResult.fromJson(_response(json).result);
  },
  'CancelledNotification': _parseJsonRpc,
  'CancelledNotificationParams': (json) {
    CancelledNotification.fromJson(json);
  },
  'ClientCapabilities': (json) => ClientCapabilities.fromJson(json),
  'CompleteRequest': _parseJsonRpc,
  'CompleteRequestParams': (json) => CompleteRequest.fromJson(json),
  'CompleteResult': (json) => CompleteResult.fromJson(json),
  'CompleteResultResponse': (json) {
    CompleteResult.fromJson(_response(json).result);
  },
  'CreateMessageRequest': _parseRequestLike,
  'CreateMessageRequestParams': (json) {
    CreateMessageRequest.fromJson(json);
  },
  'CreateMessageResult': (json) => CreateMessageResult.fromJson(json),
  'DiscoverRequest': _parseJsonRpc,
  'DiscoverResult': (json) => DiscoverResult.fromJson(json),
  'DiscoverResultResponse': (json) {
    DiscoverResult.fromJson(_response(json).result);
  },
  'ElicitRequest': _parseRequestLike,
  'ElicitRequestFormParams': (json) {
    ElicitRequest.fromJson(
      json,
      protocolVersion: latestDraftProtocolVersion,
    );
  },
  'ElicitRequestURLParams': (json) {
    ElicitRequest.fromJson(
      json,
      protocolVersion: latestDraftProtocolVersion,
    );
  },
  'ElicitResult': (json) => ElicitResult.fromJson(json),
  'ElicitationCompleteNotification': _parseJsonRpc,
  'EmbeddedResource': (json) => EmbeddedResource.fromJson(json),
  'GetPromptRequest': _parseJsonRpc,
  'GetPromptRequestParams': (json) => GetPromptRequest.fromJson(json),
  'GetPromptResult': (json) => GetPromptResult.fromJson(json),
  'GetPromptResultResponse': (json) {
    GetPromptResult.fromJson(_response(json).result);
  },
  'ImageContent': (json) => ImageContent.fromJson(json),
  'InputRequiredResult': (json) => InputRequiredResult.fromJson(json),
  'InputRequests': (json) {
    InputRequest.mapFromJson(json, 'InputRequests');
  },
  'InputResponses': _parseInputResponses,
  'InternalError': _parseErrorDataOrWrapper,
  'InvalidParamsError': _parseErrorDataOrWrapper,
  'InvalidRequestError': _parseErrorDataOrWrapper,
  'ListPromptsRequest': _parseJsonRpc,
  'ListPromptsResult': (json) => ListPromptsResult.fromJson(json),
  'ListPromptsResultResponse': (json) {
    ListPromptsResult.fromJson(_response(json).result);
  },
  'ListResourceTemplatesRequest': _parseJsonRpc,
  'ListResourceTemplatesResult': (json) {
    ListResourceTemplatesResult.fromJson(json);
  },
  'ListResourceTemplatesResultResponse': (json) {
    ListResourceTemplatesResult.fromJson(_response(json).result);
  },
  'ListResourcesRequest': _parseJsonRpc,
  'ListResourcesResult': (json) => ListResourcesResult.fromJson(json),
  'ListResourcesResultResponse': (json) {
    ListResourcesResult.fromJson(_response(json).result);
  },
  'ListRootsRequest': _parseRequestLike,
  'ListRootsResult': (json) => ListRootsResult.fromJson(json),
  'ListToolsRequest': _parseJsonRpc,
  'ListToolsResult': (json) => ListToolsResult.fromJson(json),
  'ListToolsResultResponse': (json) {
    ListToolsResult.fromJson(_response(json).result);
  },
  'LoggingMessageNotification': _parseJsonRpc,
  'LoggingMessageNotificationParams': (json) {
    LoggingMessageNotification.fromJson(json);
  },
  'MethodNotFoundError': _parseErrorDataOrWrapper,
  'MissingRequiredClientCapabilityError': _parseErrorDataOrWrapper,
  'ModelPreferences': (json) => ModelPreferences.fromJson(json),
  'NumberSchema': _parseSchema,
  'PaginatedRequestParams': (json) => ListToolsRequest.fromJson(json),
  'ParseError': _parseErrorDataOrWrapper,
  'ProgressNotification': _parseJsonRpc,
  'ProgressNotificationParams': (json) {
    ProgressNotification.fromJson(json);
  },
  'PromptListChangedNotification': _parseJsonRpc,
  'ReadResourceRequest': _parseJsonRpc,
  'ReadResourceResult': (json) => ReadResourceResult.fromJson(json),
  'ReadResourceResultResponse': (json) {
    ReadResourceResult.fromJson(_response(json).result);
  },
  'Resource': (json) => Resource.fromJson(json),
  'ResourceLink': (json) => ResourceLink.fromJson(json),
  'ResourceListChangedNotification': _parseJsonRpc,
  'ResourceUpdatedNotification': _parseJsonRpc,
  'ResourceUpdatedNotificationParams': (json) {
    ResourceUpdatedNotification.fromJson(json);
  },
  'Root': (json) => Root.fromJson(json),
  'SamplingMessage': (json) => SamplingMessage.fromJson(json),
  'ServerCapabilities': (json) => ServerCapabilities.fromJson(json),
  'StringSchema': _parseSchema,
  'SubscriptionsAcknowledgedNotification': _parseJsonRpc,
  'SubscriptionsListenRequest': _parseJsonRpc,
  'TextContent': (json) => TextContent.fromJson(json),
  'TextResourceContents': (json) => ResourceContents.fromJson(json),
  'TitledMultiSelectEnumSchema': _parseSchema,
  'TitledSingleSelectEnumSchema': _parseSchema,
  'Tool': (json) => Tool.fromJson(json),
  'ToolListChangedNotification': _parseJsonRpc,
  'ToolResultContent': (json) => SamplingContent.fromJson(json),
  'ToolUseContent': (json) => SamplingContent.fromJson(json),
  'UnsupportedProtocolVersionError': _parseErrorDataOrWrapper,
  'UntitledMultiSelectEnumSchema': _parseSchema,
  'UntitledSingleSelectEnumSchema': _parseSchema,
};

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run tool/spec_example_audit.dart <schema examples dir>',
    );
    exitCode = 64;
    return;
  }

  final root = Directory(args.single);
  if (!root.existsSync()) {
    stderr.writeln('examples directory does not exist: ${root.path}');
    exitCode = 66;
    return;
  }

  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final failures = <String>[];
  final missing = <String, int>{};
  var parsed = 0;

  for (final file in files) {
    final relative = file.path.substring(root.path.length + 1);
    final group = relative.split(Platform.pathSeparator).first;
    final parser = _parsers[group];
    if (parser == null) {
      missing[group] = (missing[group] ?? 0) + 1;
      continue;
    }

    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        throw FormatException(
          'Expected object root, got ${decoded.runtimeType}',
        );
      }
      parser(Map<String, dynamic>.from(decoded));
      parsed++;
    } catch (error, stackTrace) {
      failures.add(
        '$relative\n'
        '  $error\n'
        '  ${stackTrace.toString().split('\n').first}',
      );
    }
  }

  stdout.writeln(
    'examples=${files.length} parsed=$parsed '
    'missing=${missing.values.fold<int>(0, (sum, count) => sum + count)}',
  );

  if (missing.isNotEmpty) {
    stdout.writeln('missing parser groups:');
    for (final entry in missing.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      stdout.writeln('  ${entry.key}: ${entry.value}');
    }
  }

  if (failures.isNotEmpty) {
    stdout.writeln('failures:');
    for (final failure in failures) {
      stdout.writeln(failure);
    }
  }

  if (missing.isNotEmpty || failures.isNotEmpty) {
    exitCode = 1;
  }
}
