import 'dart:async';
import 'dart:convert'; // For utf8 encoding if needed
import 'dart:io' as io; // Use 'io' prefix
import 'dart:typed_data'; // For Uint8List

// Assume shared stdio helpers are defined in shared/stdio.dart
import 'package:mcp_dart/src/shared/stdio.dart'; // Adjust import path as needed
// Assume Transport interface is defined in shared/transport.dart
import 'package:mcp_dart/src/shared/transport.dart'; // Adjust import path as needed
// Assume types are defined in types.dart
import 'package:mcp_dart/src/types.dart'; // Adjust import path as needed
import 'package:mcp_dart/src/shared/logging.dart';

final _logger = Logger("mcp_dart.client.stdio");

/// Configuration parameters for launching the stdio server process.
class StdioServerParameters {
  /// The executable command to run to start the server process.
  final String command;

  /// Command line arguments to pass to the executable.
  final List<String> args;

  /// Environment variables to use when spawning the process.
  /// If null, the parent process environment will be inherited.
  final Map<String, String>? environment;

  /// How to handle the stderr stream of the child process.
  /// Defaults to [io.ProcessStartMode.inheritStdio], printing to the parent's stderr.
  /// Can be set to [io.ProcessStartMode.normal] to capture stderr via the [stderr] stream getter.
  final io.ProcessStartMode stderrMode;

  /// The working directory to use when spawning the process.
  /// If null, inherits the current working directory.
  final String? workingDirectory;

  /// Creates parameters for launching the stdio server.
  const StdioServerParameters({
    required this.command,
    this.args = const [],
    this.environment, // Consider defaulting using getDefaultEnvironment() if null
    this.stderrMode = io.ProcessStartMode.inheritStdio,
    this.workingDirectory,
  });
}

// Note: DEFAULT_INHERITED_ENV_VARS and getDefaultEnvironment from the TS code
// provide a mechanism to create a restricted default environment.
// This can be complex to replicate perfectly across platforms in Dart.
// For simplicity, this conversion allows passing a custom environment or
// defaulting to inheriting the parent's environment (which is dart:io's default).
// If strict environment control is needed, implement a Dart equivalent of
// getDefaultEnvironment() based on io.Platform.environment.

/// Client transport for stdio: connects to a server by spawning a process
/// and communicating with it over stdin/stdout pipes.
///
/// This transport requires `dart:io` and is suitable for command-line clients
/// or desktop applications that manage a server subprocess.
class StdioClientTransport implements Transport {
  /// Configuration for launching the server process.
  final StdioServerParameters _serverParams;

  /// The running server process, null until [start] is called and completes.
  io.Process? _process;

  /// Used to signal process termination during [close].
  final Completer<void> _exitCompleter = Completer<void>();

  /// Buffer for incoming data from the process's stdout.
  final ReadBuffer _readBuffer = ReadBuffer();

  /// Flag to prevent multiple starts.
  bool _started = false;

  /// Subscriptions to the process's stdout and stderr streams.
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>?
      _stderrSubscription; // Only used if stderrMode is pipe

  /// Callback for when the connection (process) is closed.
  @override
  void Function()? onclose;

  /// Callback for reporting errors (e.g., process spawn failure, stream errors).
  @override
  void Function(Error error)? onerror;

  /// Callback for received messages parsed from the process's stdout.
  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Session ID is not applicable to stdio transport.
  @override
  String? get sessionId => null;

  /// Creates a stdio client transport.
  ///
  /// Requires [_serverParams] detailing how to launch the server process.
  StdioClientTransport(this._serverParams);

  /// Starts the server process and establishes communication pipes.
  ///
  /// Spawns the process defined in [_serverParams] and sets up listeners
  /// on its stdout and stderr streams. Completes when the process has
  /// successfully started. Throws exceptions if the process fails to start.
  /// Throws [StateError] if already started.
  @override
  Future<void> start() async {
    if (_started) {
      throw StateError(
        "StdioClientTransport already started! If using Client class, note that connect() calls start() automatically.",
      );
    }
    _started = true;

    final mode = (_serverParams.stderrMode == io.ProcessStartMode.normal)
        ? io.ProcessStartMode.normal // Use normal for pipe access
        : io.ProcessStartMode.inheritStdio; // More direct inheritance

    try {
      // Start the process.
      _process = await io.Process.start(
        _serverParams.command,
        _serverParams.args,
        workingDirectory: _serverParams.workingDirectory,
        environment:
            _serverParams.environment, // Use provided or inherit Dart default
        runInShell: false, // Generally safer
        mode: mode, // Handles stdin/stdout/stderr piping/inheritance
      );

      _logger.debug(
        "StdioClientTransport: Process started (PID: ${_process?.pid})",
      );

      // --- Setup stream listeners ---

      // Listen to stdout for messages
      _stdoutSubscription = _process!.stdout.listen(
        _onStdoutData,
        onError: _onStreamError,
        onDone: _onStdoutDone,
        cancelOnError: false,
      );

      // Listen to stderr if piped
      if (_serverParams.stderrMode == io.ProcessStartMode.normal) {
        // Expose stderr via getter, let user handle it.
        // Optionally add logging here:
        _stderrSubscription = _process!.stderr.listen(
          (data) => _logger.debug(
            "Server stderr: ${utf8.decode(data, allowMalformed: true)}",
          ),
          onError: _onStreamError, // Report stderr stream errors too
        );
      }

      // Handle process exit
      _process!.exitCode.then(_onProcessExit).catchError(_onProcessExitError);

      // Start successful
      return Future.value();
    } catch (error, stackTrace) {
      // Handle errors during Process.start()
      _logger.error("StdioClientTransport: Failed to start process: $error");
      _started = false; // Reset state
      final startError = StateError(
        "Failed to start server process: $error\n$stackTrace",
      );
      try {
        onerror?.call(startError);
      } catch (e) {
        _logger.warn("Error in onerror handler: $e");
      }
      throw startError; // Rethrow to signal failure
    }
  }

  /// Provides access to the stderr stream of the child process,
  /// but only if [StdioServerParameters.stderrMode] was set to
  /// [io.ProcessStartMode.normal] during construction.
  /// Returns null if stderr is not piped or if the process is not running.
  Stream<List<int>>? get stderr {
    if (_serverParams.stderrMode == io.ProcessStartMode.normal &&
        _process != null) {
      return _process!.stderr;
    }
    return null;
  }

  /// Internal handler for data received from the process's stdout.
  void _onStdoutData(List<int> chunk) {
    if (chunk is! Uint8List) chunk = Uint8List.fromList(chunk);
    _readBuffer.append(chunk);
    _processReadBuffer();
  }

  /// Internal handler for when the process's stdout stream closes.
  void _onStdoutDone() {
    _logger.debug("StdioClientTransport: Process stdout closed.");
    // Consider if this should trigger close() - depends if server exiting is expected.
    // Maybe only close if the process has also exited?
    // close(); // Optionally close transport when stdout ends
  }

  /// Internal handler for errors on process stdout/stderr streams.
  void _onStreamError(dynamic error, StackTrace stackTrace) {
    final Error streamError = (error is Error)
        ? error
        : StateError("Process stream error: $error\n$stackTrace");
    try {
      onerror?.call(streamError);
    } catch (e) {
      _logger.warn("Error in onerror handler: $e");
    }
    // Consider if stream errors should trigger close()
    // close();
  }

  /// Internal handler processing buffered stdout data for messages.
  void _processReadBuffer() {
    while (true) {
      try {
        final message = _readBuffer.readMessage();
        if (message == null) break; // No complete message
        try {
          onmessage?.call(message);
        } catch (e) {
          _logger.warn("Error in onmessage handler: $e");
          onerror?.call(StateError("Error in onmessage handler: $e"));
        }
      } catch (error) {
        final Error parseError = (error is Error)
            ? error
            : StateError("Message parsing error: $error");
        try {
          onerror?.call(parseError);
        } catch (e) {
          _logger.warn("Error in onerror handler: $e");
        }
        _logger.error(
          "StdioClientTransport: Error processing read buffer: $parseError. Skipping data.",
        );
        // Consider clearing buffer or attempting recovery depending on error type.
        // Clearing might be safest for unknown parsing errors.
        // _readBuffer.clear();
        break; // Stop processing buffer on error for now
      }
    }
  }

  /// Internal handler for when the process exits.
  void _onProcessExit(int exitCode) {
    _logger.debug("StdioClientTransport: Process exited with code $exitCode.");
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(); // Signal exit if not already closing
    }
    close(); // Ensure transport is cleaned up on process exit
  }

  /// Internal handler for errors retrieving the process exit code.
  void _onProcessExitError(dynamic error, StackTrace stackTrace) {
    _logger.debug(
      "StdioClientTransport: Error waiting for process exit: $error",
    );
    final Error exitError = (error is Error)
        ? error
        : StateError("Process exit error: $error\n$stackTrace");
    try {
      onerror?.call(exitError);
    } catch (e) {
      _logger.warn("Error in onerror handler: $e");
    }
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.completeError(exitError);
    }
    close(); // Ensure cleanup even on exit code error
  }

  /// Closes the transport connection by terminating the server process
  /// and cleaning up resources.
  ///
  /// Sends a SIGTERM signal (or SIGKILL on timeout/Windows) to the process.
  @override
  Future<void> close() async {
    if (!_started) return; // Already closed or never started

    _logger.debug("StdioClientTransport: Closing transport...");

    // Mark as closing immediately to prevent further sends/starts
    _started = false;

    // Cancel stream subscriptions
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    _readBuffer.clear();

    // Terminate the process
    final processToKill = _process;
    _process = null; // Clear reference

    if (processToKill != null) {
      _logger.debug(
        "StdioClientTransport: Terminating process (PID: ${processToKill.pid})...",
      );
      // Attempt graceful termination first
      final bool killed = processToKill.kill(io.ProcessSignal.sigterm);
      if (!killed) {
        _logger.debug(
          "StdioClientTransport: Failed to send SIGTERM or process already exited.",
        );
        // If SIGTERM fails or wasn't sent (e.g., process already dead),
        // rely on the exitCode future completing.
      } else {
        // Give a short grace period for SIGTERM before SIGKILL
        try {
          await _exitCompleter.future.timeout(const Duration(seconds: 2));
          _logger.debug("StdioClientTransport: Process terminated gracefully.");
        } on TimeoutException {
          _logger.warn(
            "StdioClientTransport: Process did not exit after SIGTERM, sending SIGKILL.",
          );
          processToKill.kill(io.ProcessSignal.sigkill); // Force kill
        } catch (e) {
          // Error waiting for exit after SIGTERM (might have exited quickly)
          _logger.error(
            "StdioClientTransport: Error waiting for process exit after SIGTERM: $e",
          );
        }
      }
    }

    // Ensure exit completer is finished if not already
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete();
    }

    // Invoke the onclose callback
    try {
      onclose?.call();
    } catch (e) {
      _logger.warn("Error in onclose handler: $e");
    }
    _logger.debug("StdioClientTransport: Transport closed.");
  }

  /// Sends a [JsonRpcMessage] to the server process via its stdin.
  ///
  /// Serializes the message to JSON with a newline and writes it to the
  /// process's stdin stream. Throws [StateError] if the transport is not started
  /// or the process is not running.
  @override
  Future<void> send(JsonRpcMessage message) async {
    final currentProcess = _process; // Capture locally
    if (!_started || currentProcess == null) {
      throw StateError(
        "Cannot send message: StdioClientTransport is not running.",
      );
    }

    try {
      final jsonString = serializeMessage(message);
      currentProcess.stdin.write(jsonString);
      // Flushing stdin might be necessary depending on the server's reading behavior.
      await currentProcess.stdin.flush();
    } catch (error, stackTrace) {
      _logger.warn(
        "StdioClientTransport: Error writing to process stdin: $error",
      );
      final Error sendError = (error is Error)
          ? error
          : StateError("Process stdin write error: $error\n$stackTrace");
      try {
        onerror?.call(sendError);
      } catch (e) {
        _logger.warn("Error in onerror handler: $e");
      }
      // Consider closing the transport on stdin write failure
      close();
      throw sendError; // Rethrow after cleanup attempt
    }
  }
}
