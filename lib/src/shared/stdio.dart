import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.shared.stdio");

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
      return null;
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
  try {
    final jsonMap = jsonDecode(line) as Map<String, dynamic>;
    return JsonRpcMessage.fromJson(jsonMap);
  } on FormatException catch (e) {
    _logger.warn("Failed to decode JSON line: $line");
    throw FormatException("Invalid JSON received: ${e.message}", line);
  } catch (e) {
    _logger.warn("Failed to parse JsonRpcMessage from line: $line");
    rethrow;
  }
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
