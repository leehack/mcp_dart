import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:mcp_dart/src/shared/stdio.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.shared.iostream");

/// Transport implementation that uses standard I/O for communication.
class IOStreamTransport implements Transport {
  /// The input stream to read from.
  final Stream<List<int>> stream;

  /// The output sink to write to.
  final StreamSink<List<int>> sink;

  /// Buffer for incoming data from the stream.
  final ReadBuffer _readBuffer = ReadBuffer();

  /// Subscription to the input stream
  StreamSubscription<List<int>>? _streamSubscription;

  /// Whether the transport has been started
  bool _started = false;

  /// Whether the transport has been closed
  bool _closed = false;

  /// Callback invoked when the transport is closed
  @override
  void Function()? onclose;

  /// Callback invoked when an error occurs
  @override
  void Function(Error error)? onerror;

  /// Callback invoked when a message is received
  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Session ID is not applicable to direct transport
  @override
  String? get sessionId => null;

  /// Creates a transport with the provided streams.
  ///
  /// [stream] is the stream to read from.
  /// [sink] is the sink to write to.
  IOStreamTransport({
    required this.stream,
    required this.sink,
  });

  /// Starts the transport by setting up listeners on the input stream.
  ///
  /// This must be called before sending or receiving messages.
  /// Throws [StateError] if already started.
  @override
  Future<void> start() async {
    if (_started) {
      throw StateError(
        "IOStreamTransport already started! Note that server/client .connect() calls start() automatically.",
      );
    }
    _started = true;
    _closed = false;

    try {
      // Listen to input stream for messages
      _streamSubscription = stream.listen(
        _onStreamData,
        onError: _onStreamError,
        onDone: _onStreamDone,
        cancelOnError: false,
      );

      return Future.value();
    } catch (error, stackTrace) {
      _started = false; // Reset state
      final startError = StateError(
        "Failed to start IOStreamTransport: $error\n$stackTrace",
      );
      try {
        onerror?.call(startError);
      } catch (e) {
        _logger.warning("Error in onerror handler: $e");
      }
      throw startError; // Rethrow to signal failure
    }
  }

  /// Internal handler for data received from the input stream
  void _onStreamData(List<int> chunk) {
    if (chunk is! Uint8List) chunk = Uint8List.fromList(chunk);
    _readBuffer.append(chunk);
    _processReadBuffer();
  }

  /// Internal handler for when the input stream closes
  void _onStreamDone() {
    _logger.fine("IOStreamTransport: Input stream closed.");
    close(); // Close transport when input ends
  }

  /// Internal handler for errors on input stream
  void _onStreamError(dynamic error, StackTrace stackTrace) {
    final Error streamError = (error is Error)
        ? error
        : StateError("Stream error: $error\n$stackTrace");
    try {
      onerror?.call(streamError);
    } catch (e) {
      _logger.warning("Error in onerror handler: $e");
    }
    close();
  }

  /// Internal handler processing buffered input data for messages
  void _processReadBuffer() {
    while (true) {
      try {
        final message = _readBuffer.readMessage();
        if (message == null) break; // No complete message
        try {
          onmessage?.call(message);
        } catch (e) {
          _logger.warning("Error in onmessage handler: $e");
          onerror?.call(StateError("Error in onmessage handler: $e"));
        }
      } catch (error) {
        final Error parseError = (error is Error)
            ? error
            : StateError("Message parsing error: $error");
        try {
          onerror?.call(parseError);
        } catch (e) {
          _logger.warning("Error in onerror handler: $e");
        }
        _logger.warning(
          "IOStreamTransport: Error processing read buffer: $parseError. Skipping data.",
        );
        break; // Stop processing buffer on error
      }
    }
  }

  /// Closes the transport connection and cleans up resources.
  @override
  Future<void> close() async {
    if (_closed || !_started) return; // Already closed or never started

    _logger.fine("IOStreamTransport: Closing transport...");

    // Mark as closing immediately to prevent further sends/starts
    _started = false;
    _closed = true;

    // Cancel stream subscription
    await _streamSubscription?.cancel();
    _streamSubscription = null;

    _readBuffer.clear();

    // Invoke the onclose callback
    try {
      onclose?.call();
    } catch (e) {
      _logger.warning("Error in onclose handler: $e");
    }
    _logger.fine("IOStreamTransport: Transport closed.");
  }

  /// Sends a message to the output stream.
  ///
  /// Throws [StateError] if the transport is not started.
  @override
  Future<void> send(JsonRpcMessage message) async {
    if (!_started || _closed) {
      throw StateError(
        "Cannot send message: IOStreamTransport is not running or is closed.",
      );
    }

    try {
      final jsonString = "${jsonEncode(message.toJson())}\n";
      sink.add(utf8.encode(jsonString));
      // No need to flush as StreamSink should handle this
    } catch (error, stackTrace) {
      _logger
          .warning("IOStreamTransport: Error writing to output stream: $error");
      final Error sendError = (error is Error)
          ? error
          : StateError("Output stream write error: $error\n$stackTrace");
      try {
        onerror?.call(sendError);
      } catch (e) {
        _logger.warning("Error in onerror handler: $e");
      }
      close();
      throw sendError; // Rethrow after cleanup attempt
    }
  }
}
