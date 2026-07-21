import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/types/json_rpc.dart' as json_rpc;

final _logger = Logger("mcp_dart.shared.stdio");

/// A newline-delimited stdio frame that could not be decoded as an MCP
/// JSON-RPC message.
///
/// [errorCode] and [requestId] retain enough envelope information for a server
/// transport to send the JSON-RPC error required by the protocol. Notifications
/// and malformed responses set [shouldRespond] to false because JSON-RPC does
/// not permit a response to either message kind.
class StdioMessageDecodeException extends FormatException {
  /// JSON-RPC error classification for this malformed frame.
  final ErrorCode errorCode;

  /// A valid request identifier recovered from the envelope, if any.
  final RequestId? requestId;

  /// Whether a server should send an error response for this frame.
  final bool shouldRespond;

  StdioMessageDecodeException(
    String detail, {
    required this.errorCode,
    required this.shouldRespond,
    this.requestId,
    Object? source,
  }) : super(detail, source);

  /// The canonical JSON-RPC error message for [errorCode].
  String get wireMessage => switch (errorCode) {
        ErrorCode.parseError => 'Parse error',
        ErrorCode.invalidRequest => 'Invalid Request',
        ErrorCode.invalidParams => 'Invalid params',
        _ => 'Invalid Request',
      };
}

class _JsonRpcEnvelope {
  final RequestId? requestId;
  final bool isRequest;
  final bool isNotification;

  const _JsonRpcEnvelope({
    this.requestId,
    this.isRequest = false,
    this.isNotification = false,
  });
}

/// Buffers a continuous stdio stream (like stdin) and parses discrete,
/// newline-terminated JSON-RPC messages.
class ReadBuffer {
  final BytesBuilder _builder = BytesBuilder();
  Uint8List? _bufferCache;

  /// Appends a chunk of binary data (received from the stream) to the buffer.
  void append(Uint8List chunk) {
    _builder.add(chunk);
    _bufferCache = null;
  }

  /// Attempts to read a complete, newline-terminated JSON-RPC message
  /// from the accumulated buffer.
  ///
  /// Returns the parsed [JsonRpcMessage] if a complete message is found,
  /// otherwise returns null.
  ///
  /// Throws [FormatException] if the extracted line is not valid JSON or
  /// if the JSON does not represent a known [JsonRpcMessage] structure.
  JsonRpcMessage? readMessage() {
    _bufferCache ??= _builder.toBytes();

    if (_bufferCache == null || _bufferCache!.isEmpty) {
      return null;
    }

    final newlineIndex = _bufferCache!.indexOf(10);
    if (newlineIndex == -1) {
      return null;
    }

    final lineBytes = Uint8List.sublistView(_bufferCache!, 0, newlineIndex);

    String line;
    try {
      line = utf8.decode(lineBytes);
    } catch (e) {
      _logger.warn("Error decoding UTF-8 line: $e");
      _updateBufferAfterRead(newlineIndex);
      throw StdioMessageDecodeException(
        'Invalid UTF-8 in stdio message: $e',
        errorCode: ErrorCode.parseError,
        shouldRespond: true,
      );
    }

    _updateBufferAfterRead(newlineIndex);

    return deserializeMessage(line);
  }

  /// Clears the internal buffer and resets the state.
  void clear() {
    _builder.clear();
    _bufferCache = null;
  }

  void _updateBufferAfterRead(int newlineIndex) {
    final remainingBytes = Uint8List.sublistView(
      _bufferCache!,
      newlineIndex + 1,
    );

    _builder.clear();
    _builder.add(remainingBytes);
    _bufferCache = null;
  }
}

/// Deserializes a single line of text (assumed to be a JSON object)
/// into a [JsonRpcMessage] using its factory constructor.
///
/// Throws [FormatException] if the line is not valid JSON.
JsonRpcMessage deserializeMessage(String line) {
  late final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException catch (e) {
    _logger.warn("Failed to decode JSON line: $line");
    throw StdioMessageDecodeException(
      'Invalid JSON received: ${e.message}',
      errorCode: ErrorCode.parseError,
      shouldRespond: true,
      source: line,
    );
  }

  if (decoded is! Map<String, dynamic>) {
    _logger.warn("JSON-RPC stdio frame is not an object: $line");
    throw StdioMessageDecodeException(
      'Invalid JSON-RPC message: expected an object',
      errorCode: ErrorCode.invalidRequest,
      shouldRespond: true,
      source: line,
    );
  }

  late final _JsonRpcEnvelope envelope;
  try {
    envelope = _validateEnvelope(decoded);
  } on StdioMessageDecodeException {
    rethrow;
  } catch (error) {
    _logger.warn("Failed to validate JSON-RPC envelope: $line");
    throw StdioMessageDecodeException(
      'Invalid JSON-RPC envelope: $error',
      errorCode: ErrorCode.invalidRequest,
      shouldRespond: true,
      source: line,
    );
  }

  try {
    return JsonRpcMessage.fromJson(decoded);
  } on FormatException catch (error) {
    _logger.warn("Failed to parse JsonRpcMessage from line: $line");
    throw StdioMessageDecodeException(
      error.message,
      errorCode: envelope.isRequest || envelope.isNotification
          ? ErrorCode.invalidParams
          : ErrorCode.invalidRequest,
      requestId: envelope.requestId,
      shouldRespond: envelope.isRequest,
      source: line,
    );
  } on TypeError catch (error) {
    _logger.warn("Failed to parse JsonRpcMessage from line: $line");
    throw StdioMessageDecodeException(
      'Invalid MCP message parameters: $error',
      errorCode: envelope.isRequest || envelope.isNotification
          ? ErrorCode.invalidParams
          : ErrorCode.invalidRequest,
      requestId: envelope.requestId,
      shouldRespond: envelope.isRequest,
      source: line,
    );
  }
}

_JsonRpcEnvelope _validateEnvelope(Map<String, dynamic> json) {
  final hasMethod = json.containsKey('method');
  final hasResult = json.containsKey('result');
  final hasError = json.containsKey('error');
  final isResponseEnvelope = !hasMethod && (hasResult || hasError);

  RequestId? requestId;
  if (json.containsKey('id')) {
    try {
      requestId = json_rpc.parseRequestId(json['id']);
    } on FormatException catch (error) {
      throw StdioMessageDecodeException(
        error.message,
        errorCode: ErrorCode.invalidRequest,
        shouldRespond: !isResponseEnvelope,
        source: json,
      );
    }
  }

  if (json['jsonrpc'] != jsonRpcVersion) {
    throw StdioMessageDecodeException(
      'Invalid JSON-RPC version: ${json['jsonrpc']}',
      errorCode: ErrorCode.invalidRequest,
      requestId: requestId,
      shouldRespond: !isResponseEnvelope,
      source: json,
    );
  }

  if ((hasResult && hasError) || (hasMethod && (hasResult || hasError))) {
    throw StdioMessageDecodeException(
      'Invalid JSON-RPC envelope: method, result, and error are mutually exclusive',
      errorCode: ErrorCode.invalidRequest,
      requestId: requestId,
      shouldRespond: !isResponseEnvelope,
      source: json,
    );
  }

  if (hasMethod) {
    if (json['method'] is! String) {
      throw StdioMessageDecodeException(
        'Invalid method: expected string, got ${json['method'].runtimeType}',
        errorCode: ErrorCode.invalidRequest,
        requestId: requestId,
        shouldRespond: true,
        source: json,
      );
    }
    final isRequest = json.containsKey('id');
    if (json.containsKey('params') && json['params'] is! Map<String, dynamic>) {
      throw StdioMessageDecodeException(
        'Invalid params: expected an object',
        errorCode: ErrorCode.invalidParams,
        requestId: requestId,
        shouldRespond: isRequest,
        source: json,
      );
    }
    return _JsonRpcEnvelope(
      requestId: requestId,
      isRequest: isRequest,
      isNotification: !isRequest,
    );
  }

  if (hasResult || hasError) {
    // Responses must never receive responses of their own, including when the
    // response envelope or body is malformed.
    return _JsonRpcEnvelope(requestId: requestId);
  }

  throw StdioMessageDecodeException(
    'Invalid JSON-RPC message: expected method, result, or error',
    errorCode: ErrorCode.invalidRequest,
    requestId: requestId,
    shouldRespond: true,
    source: json,
  );
}

/// Serializes a [JsonRpcMessage] into a JSON string followed by a newline character.
///
/// Assumes the [message] object has a valid `toJson()` method.
String serializeMessage(JsonRpcMessage message) {
  try {
    return '${jsonEncode(message.toJson())}\n';
  } catch (e) {
    _logger.warn("Failed to serialize JsonRpcMessage: $message");
    rethrow;
  }
}
