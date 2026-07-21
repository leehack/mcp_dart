import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/stdio.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.client.stdio");

/// Configuration parameters for launching the stdio server process.
class StdioServerParameters {
  /// The executable command to run to start the server process.
  final String command;

  /// Command line arguments to pass to the executable.
  final List<String> args;

  /// Environment variables to use when spawning the process.
  ///
  /// When null, the child receives the parent environment only if
  /// [includeParentEnvironment] is `true`.
  final Map<String, String>? environment;

  /// Whether to merge the parent process environment into [environment].
  ///
  /// Defaults to `true`, matching [io.Process.start]. Set this to `false` when
  /// the child must receive only the variables explicitly provided through
  /// [environment], such as when isolating application credentials from an
  /// MCP server subprocess.
  final bool includeParentEnvironment;

  /// How to handle the stderr stream of the child process.
  /// Defaults to [io.ProcessStartMode.inheritStdio], printing to the parent's stderr.
  /// Can be set to [io.ProcessStartMode.normal] to capture stderr via the [stderr] stream getter.
  final io.ProcessStartMode stderrMode;

  /// The working directory to use when spawning the process.
  /// If null, inherits the current working directory.
  final String? workingDirectory;

  /// Whether to restart a stateless MCP server after an unexpected exit.
  ///
  /// Recovery is enabled only after the transport has identified a successful
  /// stateless MCP connection. Initialization-era sessions still close because
  /// they cannot be restored without repeating the lifecycle handshake.
  /// Active `subscriptions/listen` requests are replayed after a restart. An
  /// idle child that exits with code zero is treated as server-initiated clean
  /// shutdown; code zero while requests or subscriptions are active is not.
  /// Automatic recovery uses a short exponential backoff and stops after five
  /// restarts within 30 seconds to prevent an unbounded child-process loop.
  ///
  /// Unexpected exit is reported through [StdioClientTransport.onerror].
  /// Ordinary in-flight requests are not replayed automatically.
  final bool restartOnUnexpectedExit;

  /// Creates parameters for launching the stdio server.
  const StdioServerParameters({
    required this.command,
    this.args = const [],
    this.environment,
    this.includeParentEnvironment = true,
    this.stderrMode = io.ProcessStartMode.inheritStdio,
    this.workingDirectory,
    this.restartOnUnexpectedExit = true,
  });
}

enum _StdioProtocolMode { unknown, stateless, initializationEra }

const _processOutputDrainTimeout = Duration(seconds: 2);
const _stderrPrelistenBufferLimitBytes = 64 * 1024;
const _unexpectedRestartWindow = Duration(seconds: 30);
const _maxUnexpectedRestartsPerWindow = 5;
const _restartBackoffBase = Duration(milliseconds: 25);
const _restartBackoffMaximum = Duration(milliseconds: 200);

bool _isRecognizedModernDiscoveryError(int code) =>
    code == ErrorCode.headerMismatch.value ||
    code == ErrorCode.missingRequiredClientCapability.value ||
    code == ErrorCode.unsupportedProtocolVersion.value;

class _TrackedSubscription {
  final String wireMessage;
  final SubscriptionFilter requestedNotifications;
  SubscriptionFilter? acknowledgedNotifications;
  bool suppressReplayAcknowledgment = false;

  _TrackedSubscription(this.wireMessage, this.requestedNotifications);
}

/// Client transport for stdio: connects to a server by spawning a process
/// and communicating with it over stdin/stdout pipes.
///
/// This transport requires `dart:io` and is suitable for command-line clients
/// or desktop applications that manage a server subprocess.
class StdioClientTransport
    implements Transport, SubscriptionReplayAcknowledgmentTransport {
  /// Configuration for launching the server process.
  final StdioServerParameters _serverParams;

  /// The running server process, null until [start] is called and completes.
  io.Process? _process;

  /// Buffer for incoming data from the process's stdout.
  final ReadBuffer _readBuffer = ReadBuffer();

  /// Flag to prevent multiple starts.
  bool _started = false;

  /// Whether [close] has initiated the current process shutdown.
  bool _closing = false;

  /// Ensures the close callback is emitted once per [start] lifecycle.
  bool _closeNotified = false;

  /// Recovery work that outbound sends must wait for before writing.
  Future<void>? _restartFuture;

  /// Monotonic owner for recovery attempts.
  ///
  /// A replacement child can fail after it has acknowledged one replayed
  /// subscription, allowing a newer recovery to start while the older replay
  /// is still unwinding a failed stdin write. The generation prevents that
  /// stale attempt from closing the newer child.
  int _restartGeneration = 0;

  /// Shared completion for concurrent [close] calls.
  Future<void>? _closeFuture;

  /// Shared completion for transport cleanup initiated by process failure.
  Future<void>? _finishClosedFuture;

  /// Prevents a child that immediately crashes after restart from looping.
  /// A valid message or a new stateless request arms recovery again.
  bool _restartArmed = false;

  /// Monotonic timestamps of recent automatic restarts.
  ///
  /// A rolling budget prevents a replacement that acknowledges replayed work
  /// and immediately crashes from creating an unbounded process loop. The
  /// window naturally resets after a stable period.
  final Stopwatch _restartClock = Stopwatch();
  final List<Duration> _recentUnexpectedRestarts = [];

  _StdioProtocolMode _protocolMode = _StdioProtocolMode.unknown;

  /// Discovery requests whose successful replies identify a stateless peer.
  final Set<RequestId> _pendingDiscoveryRequests = {};

  /// Stateless requests awaiting a terminal response from the current child.
  ///
  /// This includes ordinary requests and subscriptions whose server-side
  /// cancellation has ended notifications but may still be followed by a
  /// terminal response or error. These IDs classify an unsolicited exit as
  /// unexpected and settle as lost; only entries in [_activeSubscriptions]
  /// are replayed.
  final Set<RequestId> _pendingStatelessRequests = {};

  /// Long-lived stateless requests that must be replayed after child restart.
  final Map<RequestId, _TrackedSubscription> _activeSubscriptions = {};

  /// Identifies a changed acknowledgment being forwarded from a replayed
  /// subscription stream during the synchronous [onmessage] callback.
  RequestId? _replayAcknowledgmentInDelivery;

  /// Subscriptions to the process's stdout and stderr streams.
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;

  /// Stable captured stderr for the current explicit [start]/[close]
  /// lifecycle. A broadcast stream lets the transport drain child stderr even
  /// when nobody is listening, without retaining an unbounded backlog.
  StreamController<List<int>>? _stderrController;
  Stream<List<int>>? _stderrStream;
  final List<Uint8List> _stderrPrelistenBuffer = [];
  int _stderrPrelistenBufferBytes = 0;
  bool _stderrWasListened = false;

  /// Write queue to serialize concurrent send() calls.
  /// Dart's IOSink does not allow concurrent write+flush operations.
  Future<void> _writeQueue = Future.value();

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
    if (_closeFuture != null || _finishClosedFuture != null) {
      throw StateError("StdioClientTransport is closing.");
    }
    _started = true;
    _closing = false;
    _closeNotified = false;
    _restartGeneration++;
    _restartArmed = false;
    _restartClock
      ..reset()
      ..start();
    _recentUnexpectedRestarts.clear();
    _protocolMode = _StdioProtocolMode.unknown;
    _pendingDiscoveryRequests.clear();
    _pendingStatelessRequests.clear();
    _activeSubscriptions.clear();
    _openStderrStream();
    try {
      await _spawnProcess();
    } catch (error, stackTrace) {
      _logger.error("StdioClientTransport: Failed to start process: $error");
      _started = false;
      _closeStderrStream();
      final startError = StateError(
        "Failed to start server process: $error\n$stackTrace",
      );
      try {
        onerror?.call(startError);
      } catch (e) {
        _logger.warn("Error in onerror handler: $e");
      }
      throw startError;
    }
  }

  Future<void> _spawnProcess() async {
    final process = await io.Process.start(
      _serverParams.command,
      _serverParams.args,
      workingDirectory: _serverParams.workingDirectory,
      environment: _serverParams.environment,
      includeParentEnvironment: _serverParams.includeParentEnvironment,
      runInShell: false,
      // Pipes are required even when stderr is forwarded to the parent.
      mode: io.ProcessStartMode.normal,
    );

    // A concurrent close may finish while Process.start is still pending. Do
    // not attach (or leak) a child that appeared after that lifecycle ended.
    if (_closing || !_started) {
      final stdoutDrained = process.stdout.drain<void>();
      final stderrDrained = process.stderr.drain<void>();
      await _stopProcess(process);
      await Future.wait([stdoutDrained, stderrDrained]);
      return;
    }

    _process = process;
    _readBuffer.clear();

    _logger.debug(
      "StdioClientTransport: Process started (PID: ${process.pid})",
    );

    final stdoutDone = Completer<void>();
    _stdoutSubscription = process.stdout.listen(
      (data) {
        if (identical(_process, process)) {
          _onStdoutData(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_process, process)) {
          _onStreamError(error, stackTrace);
        }
      },
      onDone: () {
        _onStdoutDone(process);
        if (!stdoutDone.isCompleted) {
          stdoutDone.complete();
        }
      },
      cancelOnError: false,
    );

    final stderrController = _stderrController;
    _stderrSubscription = process.stderr.listen(
      (data) {
        if (_serverParams.stderrMode == io.ProcessStartMode.normal) {
          if (stderrController != null && !stderrController.isClosed) {
            _emitStderr(stderrController, data);
          }
          return;
        }
        io.stderr.add(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_serverParams.stderrMode == io.ProcessStartMode.normal) {
          if (stderrController != null && !stderrController.isClosed) {
            stderrController.addError(error, stackTrace);
          }
          return;
        }
        if (identical(_process, process)) {
          _onStreamError(error, stackTrace);
        }
      },
      cancelOnError: false,
    );

    unawaited(
      process.exitCode.then<void>(
        (exitCode) => _onProcessExit(process, exitCode, stdoutDone.future),
        onError: (Object error, StackTrace stackTrace) => _onProcessExitError(
          process,
          error,
          stackTrace,
          stdoutDone.future,
        ),
      ),
    );
  }

  /// Provides captured stderr when [StdioServerParameters.stderrMode] is
  /// [io.ProcessStartMode.normal] and this transport is running.
  ///
  /// The returned broadcast stream remains stable across automatic child
  /// restarts. Child stderr is always drained; chunks emitted while the stream
  /// has not yet had its first listener are retained in a bounded 64 KiB
  /// buffer. Later gaps between listeners use normal broadcast semantics and
  /// discard chunks. Explicit [close] closes the stream, and a later [start]
  /// creates a new stream lifecycle.
  Stream<List<int>>? get stderr => _stderrStream;

  void _openStderrStream() {
    _closeStderrStream();
    if (_serverParams.stderrMode != io.ProcessStartMode.normal) {
      return;
    }
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>.broadcast(
      onListen: () {
        if (_stderrWasListened) {
          return;
        }
        _stderrWasListened = true;
        final buffered = List<Uint8List>.of(_stderrPrelistenBuffer);
        _stderrPrelistenBuffer.clear();
        _stderrPrelistenBufferBytes = 0;
        for (final chunk in buffered) {
          controller.add(chunk);
        }
      },
    );
    _stderrController = controller;
    _stderrStream = controller.stream;
  }

  void _emitStderr(
    StreamController<List<int>> controller,
    List<int> data,
  ) {
    final chunk = Uint8List.fromList(data);
    if (_stderrWasListened) {
      controller.add(chunk);
      return;
    }

    if (chunk.length >= _stderrPrelistenBufferLimitBytes) {
      _stderrPrelistenBuffer
        ..clear()
        ..add(
          Uint8List.fromList(
            chunk.sublist(chunk.length - _stderrPrelistenBufferLimitBytes),
          ),
        );
      _stderrPrelistenBufferBytes = _stderrPrelistenBufferLimitBytes;
      return;
    }

    _stderrPrelistenBuffer.add(chunk);
    _stderrPrelistenBufferBytes += chunk.length;
    while (_stderrPrelistenBufferBytes > _stderrPrelistenBufferLimitBytes) {
      final overflow =
          _stderrPrelistenBufferBytes - _stderrPrelistenBufferLimitBytes;
      final first = _stderrPrelistenBuffer.first;
      if (first.length <= overflow) {
        _stderrPrelistenBuffer.removeAt(0);
        _stderrPrelistenBufferBytes -= first.length;
        continue;
      }
      _stderrPrelistenBuffer[0] = Uint8List.fromList(first.sublist(overflow));
      _stderrPrelistenBufferBytes -= overflow;
    }
  }

  void _closeStderrStream() {
    final controller = _stderrController;
    _stderrController = null;
    _stderrStream = null;
    _stderrPrelistenBuffer.clear();
    _stderrPrelistenBufferBytes = 0;
    _stderrWasListened = false;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }

  /// Internal handler for data received from the process's stdout.
  void _onStdoutData(List<int> chunk) {
    if (chunk is! Uint8List) chunk = Uint8List.fromList(chunk);
    _readBuffer.append(chunk);
    _processReadBuffer();
  }

  /// Internal handler for when the process's stdout stream closes.
  void _onStdoutDone(io.Process process) {
    _logger.debug(
      "StdioClientTransport: Process stdout closed (PID: ${process.pid}).",
    );
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
  }

  /// Internal handler processing buffered stdout data for messages.
  void _processReadBuffer() {
    while (true) {
      try {
        final message = _readBuffer.readMessage();
        if (message == null) break; // No complete message
        if (!_observeIncomingMessage(message)) {
          if (_closing) {
            return;
          }
          continue;
        }
        if (_protocolMode == _StdioProtocolMode.stateless) {
          _restartArmed = true;
        }
        try {
          onmessage?.call(message);
        } catch (e) {
          _logger.warn("Error in onmessage handler: $e");
          onerror?.call(StateError("Error in onmessage handler: $e"));
        } finally {
          _replayAcknowledgmentInDelivery = null;
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
        // readMessage consumes the malformed newline-delimited frame before
        // parsing it. Continue so a valid frame already buffered behind it is
        // not stranded until another stdout chunk happens to arrive.
        continue;
      }
    }
  }

  bool _observeIncomingMessage(JsonRpcMessage message) {
    if (_protocolMode == _StdioProtocolMode.stateless &&
        message is JsonRpcRequest) {
      _reportError(
        StateError(
          'Stateless stdio servers must not send JSON-RPC requests; dropped '
          '${message.method} (${message.id}).',
        ),
      );
      return false;
    }

    if (message case JsonRpcResponse(:final id, :final result)) {
      if (_pendingDiscoveryRequests.remove(id)) {
        final supportedVersions = result['supportedVersions'];
        if (supportedVersions is List &&
            supportedVersions
                .whereType<String>()
                .any(isStatelessProtocolVersion)) {
          _protocolMode = _StdioProtocolMode.stateless;
          _restartArmed = true;
        }
      }
      _pendingStatelessRequests.remove(id);
      _activeSubscriptions.remove(id);
      return true;
    }

    if (message case JsonRpcError(:final id?, :final error)) {
      final wasDiscovery = _pendingDiscoveryRequests.remove(id);
      if (wasDiscovery && _isRecognizedModernDiscoveryError(error.code)) {
        // These errors are defined by stateless MCP discovery. Even though the
        // probe failed, they prove that the child is a modern peer, so a child
        // exit before the caller's retry remains recoverable.
        _protocolMode = _StdioProtocolMode.stateless;
        _restartArmed = true;
      }
      _pendingStatelessRequests.remove(id);
      _activeSubscriptions.remove(id);
      return true;
    }

    if (message is! JsonRpcNotification) {
      return true;
    }

    if (message is JsonRpcCancelledNotification) {
      final requestId = message.cancelParams.requestId;
      final subscriptionId = message.meta?[McpMetaKey.subscriptionId];
      if ((subscriptionId is int || subscriptionId is String) &&
          subscriptionId == requestId) {
        final cancelledSubscription = _activeSubscriptions.remove(requestId);
        if (cancelledSubscription != null) {
          // Server cancellation ends the notification stream, but the stream
          // can still end with a terminal response or error. Track that gap
          // like an ordinary in-flight request so a child exit settles the
          // high-level subscription instead of leaving it pending forever.
          _pendingStatelessRequests.add(requestId);
        }
      }
      return true;
    }

    final subscriptionId = message.meta?[McpMetaKey.subscriptionId];
    final subscription = _activeSubscriptions[subscriptionId];
    if (subscription == null) {
      return true;
    }

    if (message.method == Method.notificationsSubscriptionsAcknowledged) {
      final acknowledgment =
          message is JsonRpcSubscriptionsAcknowledgedNotification
              ? message
              : JsonRpcSubscriptionsAcknowledgedNotification.fromJson(
                  message.toJson(),
                );
      final acknowledgedNotifications =
          acknowledgment.acknowledgedParams.notifications;
      if (!subscription.suppressReplayAcknowledgment) {
        subscription.acknowledgedNotifications = acknowledgedNotifications;
        return true;
      }

      if (!acknowledgedNotifications.isSubsetOf(
        subscription.requestedNotifications,
      )) {
        _failSubscriptionRecovery(
          subscriptionId as RequestId,
          StateError(
            'Restarted stdio server acknowledged notifications that were '
            'not requested for subscription $subscriptionId.',
          ),
        );
        return false;
      }

      if (_subscriptionFiltersEquivalent(
        subscription.acknowledgedNotifications,
        acknowledgedNotifications,
      )) {
        subscription.suppressReplayAcknowledgment = false;
        _restartArmed = true;
        // McpSubscription.acknowledged is already completed. The replacement
        // child must acknowledge the same filter, but callers should not see a
        // duplicate first-message notification.
        return false;
      }

      // A replacement may legally acknowledge a different subset of the
      // original listen filter. Forward only changed acknowledgments so the
      // high-level subscription can update its active filter without exposing
      // duplicate acknowledgments for the common unchanged case.
      subscription
        ..acknowledgedNotifications = acknowledgedNotifications
        ..suppressReplayAcknowledgment = false;
      _restartArmed = true;
      _replayAcknowledgmentInDelivery = subscriptionId as RequestId;
      return true;
    }

    if (subscription.suppressReplayAcknowledgment) {
      _failRecovery(
        StateError(
          'Restarted stdio server sent ${message.method} before '
          '${Method.notificationsSubscriptionsAcknowledged} for '
          'subscription $subscriptionId.',
        ),
      );
      return false;
    }

    return true;
  }

  @override
  bool consumeSubscriptionReplayAcknowledgment(RequestId subscriptionId) {
    if (_replayAcknowledgmentInDelivery != subscriptionId) {
      return false;
    }
    _replayAcknowledgmentInDelivery = null;
    return true;
  }

  void _failSubscriptionRecovery(RequestId subscriptionId, Error error) {
    _activeSubscriptions.remove(subscriptionId);
    _restartArmed = true;
    _reportError(error);
    try {
      onmessage?.call(
        JsonRpcError(
          id: subscriptionId,
          error: JsonRpcErrorData(
            code: ErrorCode.invalidRequest.value,
            message: error.toString(),
          ),
        ),
      );
    } catch (callbackError) {
      _reportError(
        StateError(
          'Failed to settle invalid replay for subscription '
          '$subscriptionId: $callbackError',
        ),
      );
    }
  }

  Future<void> _onProcessExit(
    io.Process process,
    int exitCode,
    Future<void> stdoutDone,
  ) async {
    _logger.debug(
      "StdioClientTransport: Process exited with code $exitCode "
      "(PID: ${process.pid}).",
    );
    await _awaitProcessStdout(process, stdoutDone);
    _handleProcessTermination(process, exitCode: exitCode);
  }

  Future<void> _onProcessExitError(
    io.Process process,
    Object error,
    StackTrace stackTrace,
    Future<void> stdoutDone,
  ) async {
    _logger
        .debug("StdioClientTransport: Error waiting for process exit: $error");
    final Error exitError = (error is Error)
        ? error
        : StateError("Process exit error: $error\n$stackTrace");
    await _awaitProcessStdout(process, stdoutDone);
    _handleProcessTermination(process, exitError: exitError);
  }

  Future<void> _awaitProcessStdout(
    io.Process process,
    Future<void> stdoutDone,
  ) async {
    try {
      await stdoutDone.timeout(_processOutputDrainTimeout);
    } on TimeoutException {
      if (identical(_process, process) && !_closing) {
        _reportError(
          StateError(
            'Timed out draining stdout after stdio server process '
            '${process.pid} exited.',
          ),
        );
      }
    }
  }

  void _handleProcessTermination(
    io.Process process, {
    int? exitCode,
    Error? exitError,
  }) {
    if (!identical(_process, process)) {
      return;
    }

    _process = null;

    if (_closing || !_started) {
      return;
    }

    final hasActiveProtocolWork =
        _pendingStatelessRequests.isNotEmpty || _activeSubscriptions.isNotEmpty;
    final exitedUnexpectedly =
        exitError != null || exitCode != 0 || hasActiveProtocolWork;
    final canRestart = exitedUnexpectedly &&
        _serverParams.restartOnUnexpectedExit &&
        _protocolMode == _StdioProtocolMode.stateless &&
        _restartArmed;
    if (!canRestart) {
      if (exitError != null) {
        _reportError(exitError);
      }
      unawaited(_finishClosed());
      return;
    }

    final restartDelay = _reserveUnexpectedRestart();
    if (restartDelay == null) {
      _reportError(
        StateError(
          'Stdio server exceeded the automatic restart limit of '
          '$_maxUnexpectedRestartsPerWindow exits within '
          '${_unexpectedRestartWindow.inSeconds} seconds.',
        ),
      );
      unawaited(_finishClosed(killProcess: true));
      return;
    }

    _restartArmed = false;
    final lostRequests = List<RequestId>.of(_pendingStatelessRequests);
    _pendingStatelessRequests.clear();
    final restartGeneration = ++_restartGeneration;
    final restart = _restartAfterUnexpectedExit(
      restartGeneration,
      restartDelay,
    );
    _restartFuture = restart;
    _failLostStatelessRequests(lostRequests, exitCode, exitError);
    _reportError(
      exitError ??
          StateError(
            'Stdio server process exited unexpectedly with code $exitCode. '
            'The process is restarting; ordinary in-flight requests were not '
            'replayed.',
          ),
    );
    unawaited(
      restart.whenComplete(() {
        if (identical(_restartFuture, restart)) {
          _restartFuture = null;
        }
      }),
    );
  }

  Duration? _reserveUnexpectedRestart() {
    final now = _restartClock.elapsed;
    _recentUnexpectedRestarts.removeWhere(
      (restart) => now - restart >= _unexpectedRestartWindow,
    );
    if (_recentUnexpectedRestarts.length >= _maxUnexpectedRestartsPerWindow) {
      return null;
    }

    final priorRestarts = _recentUnexpectedRestarts.length;
    _recentUnexpectedRestarts.add(now);
    if (priorRestarts == 0) {
      return Duration.zero;
    }
    var delayMs = _restartBackoffBase.inMilliseconds << (priorRestarts - 1);
    if (delayMs > _restartBackoffMaximum.inMilliseconds) {
      delayMs = _restartBackoffMaximum.inMilliseconds;
    }
    return Duration(milliseconds: delayMs);
  }

  void _failLostStatelessRequests(
    List<RequestId> requestIds,
    int? exitCode,
    Error? exitError,
  ) {
    for (final requestId in requestIds) {
      try {
        onmessage?.call(
          JsonRpcError(
            id: requestId,
            error: JsonRpcErrorData(
              code: ErrorCode.connectionClosed.value,
              message:
                  'Stdio server exited before responding; request was not replayed.',
              data: {
                if (exitCode != null) 'exitCode': exitCode,
                if (exitError != null) 'cause': exitError.toString(),
                'retriable': true,
              },
            ),
          ),
        );
      } catch (error) {
        _reportError(
          StateError(
            'Failed to settle lost stdio request $requestId: $error',
          ),
        );
      }
    }
  }

  Future<void> _restartAfterUnexpectedExit(
    int restartGeneration,
    Duration delay,
  ) async {
    _logger.warn('StdioClientTransport: Restarting unexpected server exit.');
    io.Process? replacement;
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (_closing || !_started || restartGeneration != _restartGeneration) {
        return;
      }
      await _cancelProcessSubscriptions();
      _readBuffer.clear();
      await _spawnProcess();
      if (_closing || !_started || restartGeneration != _restartGeneration) {
        return;
      }

      replacement = _process;
      if (replacement == null) {
        throw StateError('Replacement stdio server did not start.');
      }
      // A replacement server may immediately complete or cancel a replayed
      // subscription while the write is awaiting its flush. Iterate over a
      // snapshot so response processing cannot invalidate the iterator, and
      // skip subscriptions that stopped being active before their turn.
      final subscriptions = List.of(_activeSubscriptions.entries);
      for (final entry in subscriptions) {
        if (_closing ||
            !_started ||
            restartGeneration != _restartGeneration ||
            !identical(_process, replacement)) {
          return;
        }
        final subscription = entry.value;
        if (!identical(_activeSubscriptions[entry.key], subscription)) {
          continue;
        }
        subscription.suppressReplayAcknowledgment =
            subscription.acknowledgedNotifications != null;
        await _writeSerialized(replacement, subscription.wireMessage);
      }
    } catch (error, stackTrace) {
      if (_closing ||
          !_started ||
          restartGeneration != _restartGeneration ||
          (replacement != null && !identical(_process, replacement))) {
        _logger.debug(
          'StdioClientTransport: Ignoring failure from a superseded restart.',
        );
        return;
      }
      final restartError = error is Error
          ? error
          : StateError('Failed to restart stdio server: $error\n$stackTrace');
      if (replacement != null && identical(_process, replacement)) {
        // A replay write can observe a broken pipe before the replacement's
        // exit callback runs (the ordering differs across Dart runtimes). Let
        // the single process-termination path classify and recover that exit;
        // closing here would race it and permanently disarm recovery.
        _logger.debug(
          'StdioClientTransport: Replay write failed; deferring recovery to '
          'the replacement process exit: $restartError',
        );
        replacement.kill(io.ProcessSignal.sigterm);
        return;
      }
      _reportError(restartError);
      await _finishClosed(killProcess: true);
    }
  }

  void _failRecovery(Error error) {
    _reportError(error);
    _closing = true;
    _started = false;
    unawaited(_finishClosed(killProcess: true));
  }

  /// Closes the transport connection and cleans up the server process.
  ///
  /// Closes the child's stdin first, then escalates to SIGTERM and SIGKILL if
  /// the process does not exit within a reasonable time.
  @override
  Future<void> close() {
    final activeClose = _closeFuture;
    if (activeClose != null) {
      return activeClose;
    }

    late final Future<void> closeFuture;
    closeFuture = _close().whenComplete(() {
      if (identical(_closeFuture, closeFuture)) {
        _closeFuture = null;
      }
    });
    _closeFuture = closeFuture;
    return closeFuture;
  }

  Future<void> _close() async {
    if (!_started && _process == null && _restartFuture == null) {
      await _finishClosedFuture;
      return;
    }

    _logger.debug("StdioClientTransport: Closing transport...");
    _closing = true;
    _started = false;
    _restartGeneration++;

    final restart = _restartFuture;
    if (restart != null) {
      try {
        await restart.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        _logger.debug(
          'StdioClientTransport: Timed out waiting for restart during '
          'shutdown.',
        );
      } catch (_) {
        // Restart failures are reported by the recovery path.
      }
    }

    // Let an already-started write finish before closing the IOSink. New sends
    // are rejected because [_started] was cleared above.
    try {
      await _writeQueue.timeout(const Duration(milliseconds: 250));
    } on TimeoutException {
      _logger.debug(
        'StdioClientTransport: Timed out waiting for an active write during '
        'shutdown.',
      );
    }

    final processToKill = _process;
    _process = null;

    if (processToKill != null) {
      await _stopProcess(processToKill);
    }

    await _finishClosed();
  }

  /// Sends a [JsonRpcMessage] to the server process via its stdin.
  ///
  /// Serializes the message to JSON with a newline and writes it to the
  /// process's stdin stream. Throws [StateError] if the transport is not started
  /// or the process is not running.
  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    await _waitForCurrentRestart();

    final currentProcess = _process;
    if (!_started || currentProcess == null) {
      throw StateError(
        "Cannot send message: StdioClientTransport is not running.",
      );
    }
    if (_protocolMode == _StdioProtocolMode.stateless &&
        (message is JsonRpcResponse || message is JsonRpcError)) {
      throw McpError(
        ErrorCode.invalidRequest.value,
        'Stateless MCP clients must not send JSON-RPC responses to servers.',
      );
    }

    final wireMessage = serializeMessage(message);

    // Serialize writes: Dart's IOSink throws if write() is called while a
    // flush() is pending. Queue each send behind the previous one so that
    // concurrent callers (e.g. UI + AI agent sharing one client) don't crash.
    final completer = Completer<void>();
    final previousWrite = _writeQueue;
    _writeQueue = completer.future;
    var observedOutgoingMessage = false;

    try {
      await previousWrite;
      if (!_started || _process != currentProcess) {
        throw StateError(
          "Cannot send message: StdioClientTransport is not running.",
        );
      }
      // Only register protocol work once it reaches the head of the write
      // queue. A request rejected because an earlier write lost the child was
      // never in flight and must not be replayed during recovery.
      _observeOutgoingMessage(message, wireMessage);
      observedOutgoingMessage = true;
      await _writeSerialized(currentProcess, wireMessage);
    } catch (error, stackTrace) {
      if (observedOutgoingMessage) {
        _rollbackOutgoingMessage(message);
      }
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
      if (identical(_process, currentProcess) && _restartFuture == null) {
        final canRecover = _serverParams.restartOnUnexpectedExit &&
            _protocolMode == _StdioProtocolMode.stateless &&
            _restartArmed;
        if (canRecover) {
          // A broken stdin makes the current child unusable. Its exit callback
          // owns recovery so this failed send cannot race an explicit close
          // that would suppress the restart.
          currentProcess.kill(io.ProcessSignal.sigterm);
        } else {
          unawaited(close());
        }
      }
      Error.throwWithStackTrace(sendError, stackTrace);
    } finally {
      completer.complete();
    }
  }

  Future<void> _waitForCurrentRestart() async {
    while (true) {
      final restart = _restartFuture;
      if (restart == null) {
        return;
      }
      await restart;
      if (identical(_restartFuture, restart)) {
        return;
      }
    }
  }

  void _observeOutgoingMessage(JsonRpcMessage message, String wireMessage) {
    if (message case JsonRpcRequest(:final id, :final method, :final meta)) {
      if (method == Method.initialize) {
        _protocolMode = _StdioProtocolMode.initializationEra;
        _pendingDiscoveryRequests.clear();
        _pendingStatelessRequests.clear();
        _activeSubscriptions.clear();
        _restartArmed = false;
        return;
      }

      if (method == Method.serverDiscover) {
        _pendingDiscoveryRequests.add(id);
        if (_protocolMode == _StdioProtocolMode.stateless) {
          // Once a discovery error identifies a modern peer, a retry is an
          // ordinary stateless request. If the child exits after accepting it,
          // settle the request as lost instead of leaving the caller hung.
          _pendingStatelessRequests.add(id);
        }
        return;
      }

      final protocolVersion = meta?[McpMetaKey.protocolVersion];
      if (protocolVersion is String &&
          isStatelessProtocolVersion(protocolVersion)) {
        _protocolMode = _StdioProtocolMode.stateless;
        _restartArmed = true;
      }

      if (method == Method.subscriptionsListen &&
          _protocolMode == _StdioProtocolMode.stateless) {
        final requestedNotifications =
            message is JsonRpcSubscriptionsListenRequest
                ? message.listenParams.notifications
                : SubscriptionsListenRequest.fromJson(
                    message.params ?? const <String, dynamic>{},
                  ).notifications;
        _activeSubscriptions[id] = _TrackedSubscription(
          wireMessage,
          requestedNotifications,
        );
      } else if (_protocolMode == _StdioProtocolMode.stateless) {
        _pendingStatelessRequests.add(id);
      }
      return;
    }

    if (message is JsonRpcNotification &&
        message.method == Method.notificationsCancelled) {
      final requestId = message.params?['requestId'];
      if (requestId is int || requestId is String) {
        _pendingStatelessRequests.remove(requestId);
        _activeSubscriptions.remove(requestId);
      }
    }
  }

  void _rollbackOutgoingMessage(JsonRpcMessage message) {
    if (message case JsonRpcRequest(:final id)) {
      _pendingDiscoveryRequests.remove(id);
      _pendingStatelessRequests.remove(id);
      _activeSubscriptions.remove(id);
    }
  }

  Future<void> _writeSerialized(io.Process process, String message) async {
    process.stdin.write(message);
    await process.stdin.flush();
  }

  Future<void> _cancelProcessSubscriptions() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
  }

  Future<bool> _waitForExit(io.Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (error) {
      _logger.debug(
        'StdioClientTransport: Error waiting for process exit: $error',
      );
      return true;
    }
  }

  Future<void> _stopProcess(io.Process process) async {
    _logger.debug(
      "StdioClientTransport: Closing process stdin (PID: ${process.pid})...",
    );
    try {
      await process.stdin.close();
    } catch (error) {
      _logger.debug(
        "StdioClientTransport: Error closing process stdin: $error",
      );
    }

    var exited = await _waitForExit(
      process,
      const Duration(milliseconds: 250),
    );
    if (!exited) {
      _logger.debug(
        "StdioClientTransport: Process did not exit after stdin closed; "
        "sending SIGTERM.",
      );
      process.kill(io.ProcessSignal.sigterm);
      exited = await _waitForExit(
        process,
        const Duration(seconds: 2),
      );
    }
    if (!exited) {
      _logger.warn(
        "StdioClientTransport: Process did not exit after SIGTERM; "
        "sending SIGKILL.",
      );
      process.kill(io.ProcessSignal.sigkill);
      await _waitForExit(process, const Duration(seconds: 2));
    }
  }

  Future<void> _finishClosed({bool killProcess = false}) {
    final activeFinish = _finishClosedFuture;
    if (activeFinish != null) {
      return activeFinish;
    }

    late final Future<void> finishFuture;
    finishFuture = _finishClosedImpl(killProcess: killProcess).whenComplete(() {
      if (identical(_finishClosedFuture, finishFuture)) {
        _finishClosedFuture = null;
      }
    });
    _finishClosedFuture = finishFuture;
    return finishFuture;
  }

  Future<void> _finishClosedImpl({bool killProcess = false}) async {
    _closing = true;
    _started = false;
    final process = _process;
    _process = null;
    if (killProcess && process != null) {
      await _stopProcess(process);
    }
    await _cancelProcessSubscriptions();
    _closeStderrStream();
    _readBuffer.clear();
    _pendingDiscoveryRequests.clear();
    _pendingStatelessRequests.clear();
    _activeSubscriptions.clear();
    _restartClock.stop();
    _recentUnexpectedRestarts.clear();

    if (!_closeNotified) {
      _closeNotified = true;
      try {
        onclose?.call();
      } catch (error) {
        _logger.warn("Error in onclose handler: $error");
      }
    }
    _logger.debug("StdioClientTransport: Transport closed.");
  }

  void _reportError(Error error) {
    try {
      onerror?.call(error);
    } catch (callbackError) {
      _logger.warn("Error in onerror handler: $callbackError");
    }
  }
}

bool _subscriptionFiltersEquivalent(
  SubscriptionFilter? first,
  SubscriptionFilter? second,
) {
  if (first == null || second == null) {
    return first == null && second == null;
  }
  return first.isSubsetOf(second) && second.isSubsetOf(first);
}
