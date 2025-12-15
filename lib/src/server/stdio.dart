import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/stdio.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.server.stdio");

/// Server transport for stdio: communicates with a MCP client by reading
/// from the current process's standard input ([io.stdin]) and writing to
/// standard output ([io.stdout]).
///
/// This transport is primarily intended for server processes that are directly
/// invoked by a client managing the process lifecycle.
///
/// Note: This transport assumes exclusive control over stdin/stdout for JSON-RPC
/// communication while active. Other uses of stdin/stdout might interfere.
class StdioServerTransport implements Transport {
  final io.Stdin _stdin;
  final io.IOSink _stdout;

  /// Buffer for incoming data from stdin.
  final ReadBuffer _readBuffer = ReadBuffer();

  /// Flag to prevent multiple starts.
  bool _started = false;

  /// Subscription to stdin data stream.
  StreamSubscription<List<int>>? _stdinSubscription;

  /// Callback for when the connection is closed.
  @override
  void Function()? onclose;

  /// Callback for reporting errors.
  @override
  void Function(Error error)? onerror;

  /// Callback for received messages.
  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Session ID is not typically applicable to stdio transport.
  @override
  String? get sessionId => null;

  /// Creates a new stdio server transport.
  ///
  /// By default, uses [io.stdin] and [io.stdout] from `dart:io`.
  /// Provide alternative streams for testing or embedding purposes.
  StdioServerTransport({io.Stdin? stdin, io.IOSink? stdout})
      : _stdin = stdin ?? io.stdin,
        _stdout = stdout ?? io.stdout;

  /// Starts listening for messages on stdin.
  ///
  /// Attaches listeners to the stdin stream to process incoming data.
  /// Throws [StateError] if already started.
  @override
  Future<void> start() async {
    if (_started) {
      throw StateError(
        "StdioServerTransport already started! If using Server class, note that connect() calls start() automatically.",
      );
    }
    _started = true;

    _stdinSubscription = _stdin.listen(
      _ondata,
      onError: _onErrorCallback,
      onDone: _onStdinDone,
      cancelOnError: false,
    );
  }

  /// Internal callback for handling data chunks from stdin.
  void _ondata(List<int> chunk) {
    if (chunk is! Uint8List) {
      chunk = Uint8List.fromList(chunk);
    }
    _readBuffer.append(chunk);
    _processReadBuffer();
  }

  /// Internal callback for handling errors on the stdin stream.
  void _onErrorCallback(dynamic error, StackTrace stackTrace) {
    final Error dartError = (error is Error)
        ? error
        : StateError("Stdin error: $error\n$stackTrace");
    try {
      onerror?.call(dartError);
    } catch (e) {
      _logger.warn("Error within onerror handler: $e");
    }
  }

  /// Internal callback for when the stdin stream is closed.
  void _onStdinDone() {
    _logger.debug("Stdin closed.");
    close();
  }

  /// Processes the internal read buffer, attempting to parse complete messages.
  void _processReadBuffer() {
    while (true) {
      try {
        final message = _readBuffer.readMessage();
        if (message == null) {
          break;
        }
        try {
          onmessage?.call(message);
        } catch (e) {
          _logger.warn("Error within onmessage handler: $e");
          onerror?.call(StateError("Error in onmessage handler: $e"));
        }
      } catch (error) {
        final Error dartError = (error is Error)
            ? error
            : StateError("Message parsing error: $error");
        try {
          onerror?.call(dartError);
        } catch (e) {
          _logger.warn("Error within onerror handler during parsing: $e");
        }
        _logger.warn(
          "StdioServerTransport: Error processing read buffer: $dartError. Attempting to continue.",
        );
      }
    }
  }

  /// Closes the transport by detaching from stdin and invoking [onclose].
  ///
  /// Note: This does not close the actual [io.stdin] or [io.stdout] streams,
  /// as they might be shared by other parts of the application. It only stops
  /// this transport from listening and interacting with them.
  @override
  Future<void> close() async {
    if (!_started) {
      return;
    }

    await _stdinSubscription?.cancel();
    _stdinSubscription = null;

    _readBuffer.clear();
    _started = false;

    try {
      onclose?.call();
    } catch (e) {
      _logger.warn("Error within onclose handler: $e");
    }
  }

  /// Sends a [JsonRpcMessage] to the client by writing its serialized form
  /// (JSON string followed by newline) to stdout.
  ///
  /// Returns a Future that completes when the message has been successfully
  /// written to the output stream buffer. Use `await _stdout.flush()` if
  /// immediate sending is required.
  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) {
    if (!_started) {
      _logger.warn(
        "Attempted to send message on stopped StdioServerTransport.",
      );
      return Future.value();
    }
    try {
      final jsonString = serializeMessage(message);
      _stdout.write(jsonString);
      return Future.value();
    } catch (error) {
      final Error dartError = (error is Error)
          ? error
          : StateError("Failed to send message: $error");
      try {
        onerror?.call(dartError);
      } catch (e) {
        _logger.warn("Error within onerror handler during send: $e");
      }
      return Future.error(dartError);
    }
  }
}
