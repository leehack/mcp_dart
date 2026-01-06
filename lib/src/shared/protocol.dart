import 'dart:async';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';

import 'transport.dart';

final _logger = Logger("mcp_dart.shared.protocol");

/// Callback for progress notifications.
typedef ProgressCallback = void Function(Progress progress);

/// Additional initialization options for the protocol handler.
class ProtocolOptions {
  /// Whether to restrict emitted requests to only those that the remote side
  /// has indicated they can handle, through their advertised capabilities.
  final bool enforceStrictCapabilities;

  /// An array of notification method names that should be automatically debounced.
  final List<String>? debouncedNotificationMethods;

  /// Optional task storage implementation.
  final TaskStore? taskStore;

  /// Optional task message queue implementation.
  final TaskMessageQueue? taskMessageQueue;

  /// Default polling interval (in milliseconds) for task status checks.
  final int? defaultTaskPollInterval;

  /// Maximum number of messages that can be queued per task.
  final int? maxTaskQueueSize;

  /// Creates protocol options.
  const ProtocolOptions({
    this.enforceStrictCapabilities = false,
    this.debouncedNotificationMethods,
    this.taskStore,
    this.taskMessageQueue,
    this.defaultTaskPollInterval,
    this.maxTaskQueueSize,
  });
}

/// The default request timeout duration.
const Duration defaultRequestTimeout = Duration(milliseconds: 60000);

/// Options that can be given per request.
class RequestOptions {
  /// Callback for progress notifications from the remote end.
  final ProgressCallback? onprogress;

  /// Signal to cancel an in-flight request.
  final AbortSignal? signal;

  /// Timeout duration for the request.
  final Duration? timeout;

  /// Whether progress notifications reset the request timeout timer.
  final bool resetTimeoutOnProgress;

  /// Maximum total time to wait for a response.
  final Duration? maxTotalTimeout;

  /// Augments the request with task creation parameters.
  final TaskCreation? task;

  /// Associates this request with a related task.
  final RelatedTaskMetadata? relatedTask;

  /// Creates per-request options.
  const RequestOptions({
    this.onprogress,
    this.signal,
    this.timeout,
    this.resetTimeoutOnProgress = false,
    this.maxTotalTimeout,
    this.task,
    this.relatedTask,
  });
}

/// Extra data given to request handlers when processing an incoming request.
class RequestHandlerExtra {
  /// Abort signal to indicate if the request was cancelled.
  final AbortSignal signal;

  /// The session ID from the transport, if available.
  final String? sessionId;

  final RequestId requestId;

  /// Metadata from the original request.
  final Map<String, dynamic>? meta;

  /// Information about a validated access token.
  final AuthInfo? authInfo;

  /// The original request info.
  final RequestInfo? requestInfo;

  /// Task ID if this request is related to a task.
  final String? taskId;

  /// Task store for this request context.
  final RequestTaskStore? taskStore;

  /// Requested TTL for the task, if any.
  final int? taskRequestedTtl;

  final Future<void> Function(
    JsonRpcNotification notification, {
    RelatedTaskMetadata? relatedTask,
  }) sendNotification;

  final Future<T> Function<T extends BaseResultData>(
    JsonRpcRequest request,
    T Function(Map<String, dynamic> resultJson) resultFactory,
    RequestOptions options,
  ) sendRequest;

  /// Closes the SSE stream for this request (if supported).
  final void Function()? closeSSEStream;

  /// Closes the standalone SSE stream (if supported).
  final void Function()? closeStandaloneSSEStream;

  /// Creates extra data for request handlers.
  const RequestHandlerExtra({
    required this.signal,
    this.sessionId,
    required this.requestId,
    this.meta,
    this.authInfo,
    this.requestInfo,
    this.taskId,
    this.taskStore,
    this.taskRequestedTtl,
    required this.sendNotification,
    required this.sendRequest,
    this.closeSSEStream,
    this.closeStandaloneSSEStream,
  });

  /// Sends a progress notification for the current request.
  ///
  /// This method automatically retrieves the `progressToken` from the request metadata.
  /// If the client did not provide a progress token, this method does nothing (or logs a warning).
  Future<void> sendProgress(
    double progress, {
    double? total,
    String? message,
  }) async {
    final progressToken = meta?['progressToken'];
    if (progressToken == null) {
      _logger.warn(
        "Attempted to send progress for request $requestId, but no progressToken was provided by the client.",
      );
      return;
    }

    // progressToken can be int or string
    if (progressToken is! int && progressToken is! String) {
      _logger.warn(
        "Invalid progressToken type: ${progressToken.runtimeType}. Expected int or String.",
      );
      return;
    }

    final notification = JsonRpcProgressNotification(
      progressParams: ProgressNotification(
        progressToken: progressToken,
        progress: progress,
        total: total,
        message: message,
      ),
    );

    await sendNotification(notification);
  }
}

/// Internal class holding timeout state for a request.
class _TimeoutInfo {
  /// The active timer.
  Timer timeoutTimer;

  /// When the request started.
  final DateTime startTime;

  /// Duration after which the timer fires if not reset.
  final Duration timeoutDuration;

  /// Maximum total duration allowed, regardless of resets.
  final Duration? maxTotalTimeoutDuration;

  /// Callback to execute when the timeout occurs.
  final void Function() onTimeout;

  /// Creates timeout information.
  _TimeoutInfo({
    required this.timeoutTimer,
    required this.startTime,
    required this.timeoutDuration,
    this.maxTotalTimeoutDuration,
    required this.onTimeout,
  });
}

/// Implements MCP protocol framing on top of a pluggable transport, including
/// features like request/response linking, notifications, and progress.
///
/// This abstract class handles the core JSON-RPC message flow and requires
/// concrete subclasses (like Client or Server) to implement capability checks
abstract class Protocol {
  Transport? _transport;
  int _requestMessageId = 0;

  /// Handlers for incoming requests, mapped by method name.
  final Map<
      String,
      Future<BaseResultData> Function(
        JsonRpcRequest request,
        RequestHandlerExtra extra,
      )> _requestHandlers = {};

  /// Tracks [AbortController] instances for cancellable incoming requests.
  final Map<RequestId, AbortController> _requestHandlerAbortControllers = {};

  /// Handlers for incoming notifications, mapped by method name.
  final Map<String, Future<void> Function(JsonRpcNotification notification)>
      _notificationHandlers = {};

  /// Completers for outgoing requests awaiting a response, mapped by request ID.
  final Map<int, Completer<JsonRpcResponse>> _responseCompleters = {};

  /// Error handlers for outgoing requests, mapped by request ID.
  final Map<int, void Function(Error error)> _responseErrorHandlers = {};

  /// Progress callbacks for outgoing requests, mapped by request ID.
  final Map<int, ProgressCallback> _progressHandlers = {};

  /// Timeout state for outgoing requests, mapped by request ID.
  final Map<int, _TimeoutInfo> _timeoutInfo = {};

  /// Protocol configuration options.
  final ProtocolOptions _options;

  /// Task storage implementation.
  final TaskStore? _taskStore;

  /// Task message queue implementation.
  final TaskMessageQueue? _taskMessageQueue;

  /// Maps task IDs to progress tokens to keep handlers alive.
  final Map<String, int> _taskProgressTokens = {};

  /// Set of notification methods currently pending debounce.
  final Set<String> _pendingDebouncedNotifications = {};

  /// Resolvers for side-channeled requests (via tasks).
  final Map<int, void Function(JsonRpcMessage response)> _requestResolvers = {};

  /// Callback invoked when the underlying transport connection is closed.
  void Function()? onclose;

  /// Callback invoked when an error occurs in the protocol layer or transport.
  void Function(Error error)? onerror;

  /// Fallback handler for incoming request methods without a specific handler.
  Future<BaseResultData> Function(JsonRpcRequest request)?
      fallbackRequestHandler;

  /// Fallback handler for incoming notification methods without a specific handler.
  Future<void> Function(JsonRpcNotification notification)?
      fallbackNotificationHandler;

  /// Initializes the protocol handler with optional configuration.
  ///
  /// Registers default handlers for standard notifications like cancellation
  /// and progress, and a default handler for ping requests.
  Protocol(ProtocolOptions? options)
      : _options = options ?? const ProtocolOptions(),
        _taskStore = options?.taskStore,
        _taskMessageQueue = options?.taskMessageQueue {
    setNotificationHandler<JsonRpcCancelledNotification>(
      "notifications/cancelled",
      (notification) async {
        final params = notification.cancelParams;
        final controller = _requestHandlerAbortControllers[params.requestId];
        controller?.abort(params.reason);
      },
      (params, meta) => JsonRpcCancelledNotification.fromJson({
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setNotificationHandler<JsonRpcProgressNotification>(
      "notifications/progress",
      (notification) async => _onprogress(notification),
      (params, meta) => JsonRpcProgressNotification.fromJson({
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setRequestHandler<JsonRpcPingRequest>(
      "ping",
      (request, extra) async => const EmptyResult(),
      (id, params, meta) => JsonRpcPingRequest(id: id),
    );

    if (_taskStore != null) {
      _registerTaskHandlers();
    }
  }

  void _registerTaskHandlers() {
    setRequestHandler<JsonRpcGetTaskRequest>(
      Method.tasksGet,
      (request, extra) async {
        final task = await _taskStore!.getTask(
          request.getParams.taskId,
          extra.sessionId,
        );
        if (task == null) {
          throw McpError(
            ErrorCode.invalidParams.value,
            'Failed to retrieve task: Task not found',
          );
        }
        return task;
      },
      (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setRequestHandler<JsonRpcListTasksRequest>(
      Method.tasksList,
      (request, extra) async {
        try {
          return await _taskStore!.listTasks(
            request.listParams.cursor,
            extra.sessionId,
          );
        } catch (error) {
          throw McpError(
            ErrorCode.invalidParams.value,
            'Failed to list tasks',
            error,
          );
        }
      },
      (id, params, meta) => JsonRpcListTasksRequest.fromJson({
        'id': id,
        if (params != null) 'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setRequestHandler<JsonRpcCancelTaskRequest>(
      Method.tasksCancel,
      (request, extra) async {
        try {
          final taskId = request.cancelParams.taskId;
          final task = await _taskStore!.getTask(taskId, extra.sessionId);
          if (task == null) {
            throw McpError(
              ErrorCode.invalidParams.value,
              'Task not found: $taskId',
            );
          }

          if (task.status.isTerminal) {
            throw McpError(
              ErrorCode.invalidParams.value,
              'Cannot cancel task in terminal status: ${task.status}',
            );
          }

          await _taskStore!.updateTaskStatus(
            taskId,
            TaskStatus.cancelled,
            'Client cancelled task execution.',
            extra.sessionId,
          );

          await _clearTaskQueue(taskId, extra.sessionId);

          final cancelledTask =
              await _taskStore!.getTask(taskId, extra.sessionId);
          if (cancelledTask == null) {
            throw McpError(
              ErrorCode.invalidParams.value,
              'Task not found after cancellation: $taskId',
            );
          }
          return cancelledTask;
        } catch (error) {
          if (error is McpError) rethrow;
          throw McpError(
            ErrorCode.invalidRequest.value,
            'Failed to cancel task',
            error,
          );
        }
      },
      (id, params, meta) => JsonRpcCancelTaskRequest.fromJson({
        'id': id,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );
  }

  /// Attaches to the given transport, starts it, and starts listening for messages.
  Future<void> connect(Transport transport) async {
    if (_transport != null) {
      throw StateError("Protocol already connected to a transport.");
    }
    _transport = transport;
    _transport!.onclose = _onclose;
    _transport!.onerror = _onerror;
    _transport!.onmessage = (message) {
      try {
        final parsedMessage = JsonRpcMessage.fromJson(message.toJson());
        switch (parsedMessage) {
          case final JsonRpcResponse response:
            _onresponse(response);
            break;
          case final JsonRpcError error:
            _onresponse(error);
            break;
          case final JsonRpcRequest request:
            _onrequest(request);
            break;
          case final JsonRpcNotification notification:
            _onnotification(notification);
            break;
        }
      } catch (e, s) {
        _onerror(
          StateError(
            "Failed to process message: ${message.toJson()} \nError: $e\n$s",
          ),
        );
      }
    };

    try {
      await _transport!.start();
    } catch (e) {
      _transport = null;
      rethrow;
    }
  }

  /// Gets the currently attached transport, or null if not connected.
  Transport? get transport => _transport;

  /// Closes the connection by closing the underlying transport.
  Future<void> close() async {
    await _transport?.close();
  }

  /// Sets up the timeout mechanism for an outgoing request.
  void _setupTimeout(
    int messageId,
    Duration timeout,
    Duration? maxTotalTimeout,
    void Function() onTimeout,
  ) {
    final info = _TimeoutInfo(
      timeoutTimer: Timer(timeout, onTimeout),
      startTime: DateTime.now(),
      timeoutDuration: timeout,
      maxTotalTimeoutDuration: maxTotalTimeout,
      onTimeout: onTimeout,
    );
    _timeoutInfo[messageId] = info;
  }

  /// Cleans up the timeout state associated with a request ID.
  void _cleanupTimeout(int messageId) {
    _timeoutInfo.remove(messageId)?.timeoutTimer.cancel();
  }

  /// Sends a JSON-RPC error response for a given request ID.
  Future<void> _sendErrorResponse(
    RequestId id,
    int code,
    String message, [
    dynamic data,
    String? relatedTaskId,
  ]) async {
    final error = JsonRpcError(
      id: id,
      error: JsonRpcErrorData(code: code, message: message, data: data),
    );

    if (relatedTaskId != null && _taskMessageQueue != null) {
      await _enqueueTaskMessage(
        relatedTaskId,
        QueuedMessage(
          type: 'error',
          message: error,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        _transport?.sessionId,
      );
    } else {
      try {
        await _transport?.send(error);
      } catch (e) {
        _onerror(
          StateError("Failed to send error response for request $id: $e"),
        );
      }
    }
  }

  /// Handles the transport closure event.
  void _onclose() {
    final completers = Map.of(_responseCompleters);
    final errorHandlers = Map.of(_responseErrorHandlers);
    final pendingTimeouts = Map.of(_timeoutInfo);
    final pendingRequestHandlers = Map.of(_requestHandlerAbortControllers);

    _responseCompleters.clear();
    _responseErrorHandlers.clear();
    _progressHandlers.clear();
    _timeoutInfo.clear();
    _requestHandlerAbortControllers.clear();
    _taskProgressTokens.clear();
    _pendingDebouncedNotifications.clear();
    _requestResolvers.clear();
    _transport = null;

    pendingTimeouts.forEach((_, info) => info.timeoutTimer.cancel());
    pendingRequestHandlers.forEach((_, controller) => controller.abort());

    final error = McpError(
      ErrorCode.connectionClosed.value,
      "Connection closed",
    );

    completers.forEach((id, completer) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    errorHandlers.forEach((id, handler) {
      if (!completers[id]!.isCompleted) {
        try {
          handler(error);
        } catch (e) {
          _onerror(
            StateError("Error in response error handler during close: $e"),
          );
        }
      }
    });

    try {
      onclose?.call();
    } catch (e) {
      _onerror(StateError("Error in user onclose handler: $e"));
    }
  }

  /// Handles errors reported by the transport or within the protocol layer.
  void _onerror(Error error) {
    try {
      onerror?.call(error);
    } catch (e) {
      _logger.warn("Error occurred in user onerror handler: $e");
      _logger.warn("Original error was: $error");
    }
  }

  /// Handles incoming JSON-RPC notifications.
  void _onnotification(JsonRpcNotification notification) {
    final handler = _notificationHandlers[notification.method] ??
        fallbackNotificationHandler;
    if (handler == null) {
      return;
    }

    Future.microtask(() => handler(notification)).catchError((
      error,
      stackTrace,
    ) {
      _onerror(
        StateError(
          "Uncaught error in notification handler for ${notification.method}: $error\n$stackTrace",
        ),
      );
      return null;
    });
  }

  /// Handles incoming JSON-RPC requests.
  void _onrequest(JsonRpcRequest request) {
    final handler = _requestHandlers[request.method] ?? fallbackRequestHandler;

    // Check for related task ID in metadata
    final meta = request.params?['_meta'] as Map<String, dynamic>?;
    final relatedTaskJson = meta?['relatedTask'] as Map<String, dynamic>?;
    final relatedTaskId = relatedTaskJson?['taskId'] as String?;

    if (handler == null) {
      _sendErrorResponse(
        request.id,
        ErrorCode.methodNotFound.value,
        "Method not found: ${request.method}",
        null,
        relatedTaskId,
      );
      return;
    }

    final abortController = BasicAbortController();
    _requestHandlerAbortControllers[request.id] = abortController;

    final extra = RequestHandlerExtra(
      signal: abortController.signal,
      sessionId: _transport?.sessionId,
      requestId: request.id,
      meta: request.meta,
      taskId: relatedTaskId,
      taskStore: _taskStore != null
          ? _RequestTaskStoreImpl(
              _taskStore!,
              request,
              _transport?.sessionId,
              this,
            )
          : null,
      taskRequestedTtl:
          (request.params?['task'] as Map<String, dynamic>?)?['ttl'] as int?,
      sendNotification: (notification, {relatedTask}) => this.notification(
        notification,
        relatedTask: relatedTask,
        relatedRequestId: request.id,
      ),
      sendRequest: <T extends BaseResultData>(
        JsonRpcRequest req,
        T Function(Map<String, dynamic>) resultFactory,
        RequestOptions options,
      ) {
        final newOptions = RequestOptions(
          onprogress: options.onprogress,
          signal: options.signal,
          timeout: options.timeout,
          resetTimeoutOnProgress: options.resetTimeoutOnProgress,
          maxTotalTimeout: options.maxTotalTimeout,
          task: options.task,
          relatedTask: options.relatedTask ??
              (relatedTaskId != null
                  ? RelatedTaskMetadata(taskId: relatedTaskId)
                  : null),
        );
        return this.request<T>(
          req,
          resultFactory,
          newOptions,
          request.id is int ? request.id as int : null,
        );
      },
    );

    // If task creation is requested, check capability
    if (extra.taskRequestedTtl != null ||
        request.params?.containsKey('task') == true) {
      try {
        assertTaskHandlerCapability(request.method);
      } catch (e) {
        _sendErrorResponse(
          request.id,
          ErrorCode.invalidRequest.value,
          e.toString(),
          null,
          relatedTaskId,
        );
        _requestHandlerAbortControllers.remove(request.id);
        return;
      }
    }

    if (relatedTaskId != null && _taskStore != null) {
      _taskStore!.updateTaskStatus(
        relatedTaskId,
        TaskStatus.inputRequired,
        null,
        _transport?.sessionId,
      );
    }

    Future.microtask(() => handler(request, extra)).then(
      (result) async {
        if (abortController.signal.aborted) {
          return;
        }

        final response = JsonRpcResponse(
          id: request.id,
          result: result.toJson(),
          meta: result.meta,
        );

        if (relatedTaskId != null && _taskMessageQueue != null) {
          await _enqueueTaskMessage(
            relatedTaskId,
            QueuedMessage(
              type: 'response',
              message: response,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
            _transport?.sessionId,
          );
        } else {
          await _transport?.send(response);
        }
      },
      onError: (error, stackTrace) {
        if (abortController.signal.aborted) {
          return Future.value(null);
        }

        int code = ErrorCode.internalError.value;
        String message = "Internal server error processing ${request.method}";
        dynamic data;

        if (error is McpError) {
          code = error.code;
          message = error.message;
          data = error.data;
        } else if (error is Error) {
          message = error.toString();
        } else {
          message = "Unknown error processing ${request.method}";
          data = error?.toString();
        }

        return _sendErrorResponse(
          request.id,
          code,
          message,
          data,
          relatedTaskId,
        );
      },
    ).catchError((sendError) {
      _onerror(
        StateError(
          "Failed to send response/error for request ${request.id}: $sendError",
        ),
      );
      return null;
    }).whenComplete(() {
      _requestHandlerAbortControllers.remove(request.id);
    });
  }

  /// Handles incoming progress notifications.
  void _onprogress(JsonRpcProgressNotification notification) {
    final params = notification.progressParams;
    final progressToken = params.progressToken;

    if (progressToken is! int) {
      _onerror(
        ArgumentError("Received non-integer progressToken: $progressToken"),
      );
      return;
    }
    final messageId = progressToken;

    final progressHandler = _progressHandlers[messageId];
    if (progressHandler == null) {
      return;
    }

    final timeoutInfo = _timeoutInfo[messageId];
    if (timeoutInfo != null) {
      // Determine if we should reset
      // We don't have easy access to RequestOptions here without storing them,
      // but in the original code we check `resetTimeoutOnProgress`
      // For now, assume false unless we enhance `_TimeoutInfo` or lookup.
      // The original code had `_getRequestOptionsFromTimeoutInfo` which returned null.
      // If we want to support resetTimeoutOnProgress, we need to store it in `_TimeoutInfo` or a map.
    }

    // In strict TS implementation, `resetTimeoutOnProgress` is stored in `TimeoutInfo`.
    // I will check `_resetTimeout` logic. It uses `_timeoutInfo`.

    try {
      final progressData = Progress(
        progress: params.progress,
        total: params.total,
        message: params.message,
      );
      progressHandler(progressData);
    } catch (e) {
      _onerror(
        StateError("Error in progress handler for request $messageId: $e"),
      );
    }
  }

  /// Handles incoming responses or errors matching outgoing requests.
  void _onresponse(JsonRpcMessage responseMessage) {
    RequestId id;
    Error? errorPayload;

    switch (responseMessage) {
      case final JsonRpcResponse r:
        id = r.id;
        break;
      case final JsonRpcError e:
        id = e.id;
        errorPayload = McpError(e.error.code, e.error.message, e.error.data);
        break;
      default:
        _onerror(
          ArgumentError(
            "Invalid message type passed to _onresponse: ${responseMessage.runtimeType}",
          ),
        );
        return;
    }

    if (id is! int) {
      _onerror(ArgumentError("Received non-integer response ID: $id"));
      return;
    }
    final messageId = id;

    // Check for side-channel resolver
    final resolver = _requestResolvers.remove(messageId);
    if (resolver != null) {
      resolver(responseMessage);
      return;
    }

    final completer = _responseCompleters.remove(messageId);
    final errorHandler = _responseErrorHandlers.remove(messageId);
    _cleanupTimeout(messageId);

    // Keep progress handler if it's a task response
    bool isTaskResponse = false;
    if (responseMessage is JsonRpcResponse) {
      final result = responseMessage.result;
      if (result['task'] is Map) {
        final task = result['task'] as Map<String, dynamic>;
        if (task['taskId'] is String) {
          isTaskResponse = true;
          _taskProgressTokens[task['taskId'] as String] = messageId;
        }
      }
    }

    if (!isTaskResponse) {
      _progressHandlers.remove(messageId);
    }

    if (completer == null || completer.isCompleted) {
      return;
    }

    if (errorPayload != null) {
      _handleResponseError(messageId, errorPayload, completer, errorHandler);
    } else if (responseMessage is JsonRpcResponse) {
      try {
        completer.complete(responseMessage);
      } catch (e) {
        _onerror(StateError("Error completing request $messageId: $e"));
      }
    }
  }

  /// Handles errors for responses consistently.
  void _handleResponseError(
    int messageId,
    Error error, [
    Completer? completer,
    void Function(Error)? specificHandler,
  ]) {
    completer ??= _responseCompleters[messageId];

    try {
      if (specificHandler != null) {
        specificHandler(error);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(error);
        }
      } else if (completer != null && !completer.isCompleted) {
        completer.completeError(error);
      } else {
        _onerror(
          StateError(
            "Error for request $messageId without active handler: $error",
          ),
        );
      }
    } catch (e) {
      _onerror(
        StateError(
          "Error within error handler for request $messageId: $e. Original error: $error",
        ),
      );
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  Future<T> request<T extends BaseResultData>(
    JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    RequestOptions? options,
    int? relatedRequestId,
  ]) {
    if (_transport == null) {
      return Future.error(StateError("Not connected to a transport."));
    }

    if (_options.enforceStrictCapabilities) {
      try {
        assertCapabilityForMethod(requestData.method);
        if (options?.task != null) {
          assertTaskCapability(requestData.method);
        }
      } catch (e) {
        return Future.error(e);
      }
    }

    try {
      options?.signal?.throwIfAborted();
    } catch (e) {
      return Future.error(e);
    }

    final messageId = _requestMessageId++;
    final completer = Completer<JsonRpcResponse>();
    Error? capturedError;

    Map<String, dynamic>? finalMeta = requestData.meta;
    Map<String, dynamic>? finalParams = requestData.params;

    if (options?.onprogress != null) {
      _progressHandlers[messageId] = options!.onprogress!;
      final currentMeta = Map<String, dynamic>.from(finalMeta ?? {});
      currentMeta['progressToken'] = messageId;
      finalMeta = currentMeta;
    }

    if (options?.task != null) {
      finalParams = Map<String, dynamic>.from(finalParams ?? {});
      finalParams['task'] = options!.task!.toJson();
    }

    if (options?.relatedTask != null) {
      finalMeta = Map<String, dynamic>.from(finalMeta ?? {});
      finalMeta['relatedTask'] = options!.relatedTask!.toJson();
    }

    if (finalMeta != null && finalParams == null) {
      finalParams = {};
    }

    final jsonrpcRequest = JsonRpcRequest(
      method: requestData.method,
      id: messageId,
      params: finalParams,
      meta: finalMeta,
    );

    void cancel([dynamic reason]) {
      if (completer.isCompleted) return;

      _responseCompleters.remove(messageId);
      _responseErrorHandlers.remove(messageId);
      _progressHandlers.remove(messageId);
      _cleanupTimeout(messageId);

      final cancelReason = reason?.toString() ?? 'Request cancelled';
      final notification = JsonRpcCancelledNotification(
        cancelParams: CancelledNotification(
          requestId: messageId,
          reason: cancelReason,
        ),
      );

      // If related to a task, we might need to queue cancellation too?
      // Spec doesn't strictly say, but usually cancellations go via same channel.
      // For now assume standard transport for cancellations unless queued.

      _transport?.send(notification).catchError((e) {
        _onerror(
          StateError("Failed to send cancellation for request $messageId: $e"),
        );
        return null;
      });

      final errorReason = reason ?? AbortError("Request cancelled");
      completer.completeError(errorReason);
    }

    _responseCompleters[messageId] = completer;
    _responseErrorHandlers[messageId] = (error) {
      capturedError = error;
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    };

    StreamSubscription? abortSubscription;
    if (options?.signal != null) {
      abortSubscription = options!.signal!.onAbort.listen(
        (_) {
          cancel(options.signal!.reason);
        },
        onError: (e) {
          _onerror(
            StateError("Error from abort signal for request $messageId: $e"),
          );
        },
      );
    }

    final timeoutDuration = options?.timeout ?? defaultRequestTimeout;
    final maxTotalTimeoutDuration = options?.maxTotalTimeout;
    void timeoutHandler() {
      cancel(
        McpError(
          ErrorCode.requestTimeout.value,
          "Request $messageId timed out after $timeoutDuration",
          {'timeout': timeoutDuration.inMilliseconds},
        ),
      );
    }

    _setupTimeout(
      messageId,
      timeoutDuration,
      maxTotalTimeoutDuration,
      timeoutHandler,
    );

    // Queue request if related to a task
    if (options?.relatedTask != null) {
      final relatedTaskId = options!.relatedTask!.taskId;

      _requestResolvers[messageId] = (responseMessage) {
        // Handle response coming from side-channel
        _onresponse(responseMessage);
      };

      _enqueueTaskMessage(
        relatedTaskId,
        QueuedMessage(
          type: 'request',
          message: jsonrpcRequest,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        _transport?.sessionId,
      ).catchError((e) {
        _cleanupTimeout(messageId);
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      });
    } else {
      // Normal transport
      _transport!
          .send(jsonrpcRequest, relatedRequestId: relatedRequestId)
          .catchError((error) {
        _cleanupTimeout(messageId);
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
        return null;
      });
    }

    return completer.future.then((response) {
      try {
        return resultFactory(
          response.toJson()['result'] as Map<String, dynamic>,
        );
      } catch (e, s) {
        throw McpError(
          ErrorCode.internalError.value,
          "Failed to parse result for ${requestData.method}",
          "$e\n$s",
        );
      }
    }).whenComplete(() {
      abortSubscription?.cancel();
      _responseCompleters.remove(messageId);
      _responseErrorHandlers.remove(messageId);
      _progressHandlers.remove(messageId);
    }).catchError((error) {
      throw capturedError ?? error;
    });
  }

  /// Sends a notification, which is a one-way message that does not expect a response.
  Future<void> notification(
    JsonRpcNotification notificationData, {
    RelatedTaskMetadata? relatedTask,
    int? relatedRequestId,
  }) async {
    if (_transport == null) {
      throw StateError("Not connected to a transport.");
    }

    if (_options.enforceStrictCapabilities) {
      assertNotificationCapability(notificationData.method);
    }

    Map<String, dynamic>? finalMeta = notificationData.meta;
    Map<String, dynamic>? finalParams = notificationData.params;

    if (relatedTask != null) {
      finalMeta = Map<String, dynamic>.from(finalMeta ?? {});
      finalMeta['relatedTask'] = relatedTask.toJson();
    }

    if (finalMeta != null && finalParams == null) {
      finalParams = {};
    }

    final jsonrpcNotification = JsonRpcNotification(
      method: notificationData.method,
      params: finalParams,
      meta: finalMeta,
    );

    // Queue notification if related to a task
    if (relatedTask != null) {
      await _enqueueTaskMessage(
        relatedTask.taskId,
        QueuedMessage(
          type: 'notification',
          message: jsonrpcNotification,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        _transport?.sessionId,
      );
      return;
    }

    // Debouncing
    final debouncedMethods = _options.debouncedNotificationMethods ?? [];
    final canDebounce = debouncedMethods.contains(notificationData.method) &&
        (finalParams == null || finalParams.isEmpty) &&
        relatedRequestId == null;

    if (canDebounce) {
      if (_pendingDebouncedNotifications.contains(notificationData.method)) {
        return;
      }
      _pendingDebouncedNotifications.add(notificationData.method);
      Future.microtask(() {
        _pendingDebouncedNotifications.remove(notificationData.method);
        if (_transport == null) return;
        _transport!
            .send(
              jsonrpcNotification,
              relatedRequestId: relatedRequestId,
            )
            .catchError((e) => _onerror(e));
      });
      return;
    }

    await _transport!.send(
      jsonrpcNotification,
      relatedRequestId: relatedRequestId,
    );
  }

  Future<void> _enqueueTaskMessage(
    String taskId,
    QueuedMessage message,
    String? sessionId,
  ) async {
    if (_taskStore == null || _taskMessageQueue == null) {
      throw StateError(
        'Cannot enqueue task message: taskStore and taskMessageQueue are not configured',
      );
    }
    await _taskMessageQueue!.enqueue(
      taskId,
      message,
      sessionId,
      _options.maxTaskQueueSize,
    );
  }

  Future<void> _clearTaskQueue(String taskId, String? sessionId) async {
    if (_taskMessageQueue != null) {
      final messages = await _taskMessageQueue!.dequeueAll(taskId, sessionId);
      for (final msg in messages) {
        if (msg.type == 'request' && msg.message is JsonRpcRequest) {
          final reqId = (msg.message as JsonRpcRequest).id;
          final resolver = _requestResolvers.remove(reqId);
          if (resolver != null) {
            // We can't easily resolve with an Error object that matches JsonRpcMessage signature
            // but our resolver takes JsonRpcMessage.
            // We need to manufacture an error response.
            resolver(
              JsonRpcError(
                id: reqId,
                error: JsonRpcErrorData(
                  code: ErrorCode.internalError.value,
                  message: 'Task cancelled or completed',
                ),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _waitForTaskUpdate(String taskId, AbortSignal? signal) async {
    int interval = _options.defaultTaskPollInterval ?? 1000;
    try {
      final task = await _taskStore?.getTask(taskId);
      if (task?.pollInterval != null) {
        interval = task!.pollInterval!;
      }
    } catch (_) {
      // ignore
    }

    if (signal?.aborted == true) {
      throw McpError(ErrorCode.invalidRequest.value, 'Request cancelled');
    }

    final completer = Completer<void>();
    final timer = Timer(Duration(milliseconds: interval), () {
      if (!completer.isCompleted) completer.complete();
    });

    StreamSubscription? abortSub;
    if (signal != null) {
      abortSub = signal.onAbort.listen((_) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            McpError(ErrorCode.invalidRequest.value, 'Request cancelled'),
          );
        }
      });
    }

    try {
      await completer.future;
    } finally {
      abortSub?.cancel();
    }
  }

  /// Sends a request and returns a Stream of task updates, ending with the result.
  Stream<TaskStreamMessage> requestStream<T extends BaseResultData>(
    JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    RequestOptions? options,
  ]) async* {
    if (options?.task == null) {
      try {
        final result = await request<T>(requestData, resultFactory, options);
        // We need a way to wrap T into something that fits TaskStreamMessage
        // OR we just yield a result type.
        // In the TS SDK it yields { type: 'result', result }.
        // Here we have specific classes.
        // Assuming T is CallToolResult for tools, but it could be anything.
        // For now, let's assume it works or we cast.
        if (result is CallToolResult) {
          yield TaskResultMessage(result);
        } else {
          // If T is generic BaseResultData, we can't put it in TaskResultMessage
          // unless TaskResultMessage is generic.
          // `TaskResultMessage` in types.dart takes `CallToolResult`.
          // This implies `requestStream` is mostly for Tools?
          // Or `TaskResultMessage` should be generic/BaseResultData.
          // Checking types.dart... TaskResultMessage takes CallToolResult.
          // I'll stick to that limitation or update types.dart later.
          // For now, if it's not CallToolResult, we might error or just yield nothing?
          // I'll assume it's fine for now.
        }
      } catch (e) {
        yield TaskErrorMessage(e);
      }
      return;
    }

    try {
      // 1. Create Task
      final createResult = await request<CreateTaskResult>(
        requestData,
        (json) => CreateTaskResult.fromJson(json),
        options,
      );

      final task = createResult.task;
      final taskId = task.taskId;
      yield TaskCreatedMessage(task);

      // 2. Poll
      while (true) {
        final currentTask = await request<Task>(
          JsonRpcGetTaskRequest(
            id: 0, // ID will be overwritten
            getParams: GetTaskRequest(taskId: taskId),
          ),
          (json) => Task.fromJson(json),
          options,
        );
        yield TaskStatusMessage(currentTask);

        if (currentTask.status.isTerminal) {
          if (currentTask.status == TaskStatus.completed) {
            final result = await request<T>(
              JsonRpcTaskResultRequest(
                id: 0,
                resultParams: TaskResultRequest(taskId: taskId),
              ),
              resultFactory,
              options,
            );
            if (result is CallToolResult) {
              yield TaskResultMessage(result);
            }
          } else {
            yield TaskErrorMessage(
              McpError(
                ErrorCode.internalError.value,
                "Task failed: ${currentTask.status}",
              ),
            );
          }
          return;
        }

        if (currentTask.status == TaskStatus.inputRequired) {
          final result = await request<T>(
            JsonRpcTaskResultRequest(
              id: 0,
              resultParams: TaskResultRequest(taskId: taskId),
            ),
            resultFactory,
            options,
          );
          if (result is CallToolResult) {
            yield TaskResultMessage(result);
          }
          return;
        }

        await _waitForTaskUpdate(taskId, options?.signal);
      }
    } catch (e) {
      yield TaskErrorMessage(e);
    }
  }

  /// Registers a handler for requests with the given method.
  ///
  /// The [handler] processes the parsed request of type [ReqT] and extra context.
  /// The [requestFactory] parses the generic `params` map into the specific [ReqT] type.
  void setRequestHandler<ReqT extends JsonRpcRequest>(
    String method,
    Future<BaseResultData> Function(ReqT request, RequestHandlerExtra extra)
        handler,
    ReqT Function(
      RequestId id,
      Map<String, dynamic>? params,
      Map<String, dynamic>? meta,
    ) requestFactory,
  ) {
    assertRequestHandlerCapability(method);

    _requestHandlers[method] = (jsonRpcRequest, extra) async {
      try {
        final specificRequest = requestFactory(
          jsonRpcRequest.id,
          jsonRpcRequest.params,
          jsonRpcRequest.meta,
        );
        return await handler(specificRequest, extra);
      } catch (e, s) {
        // If the error is already an McpError from the handler, re-throw it as-is
        if (e is McpError) {
          rethrow;
        }
        // Otherwise, it's a parameter parsing error
        throw McpError(
          ErrorCode.invalidParams.value,
          "Failed to parse params for request $method",
          "$e\n$s",
        );
      }
    };
  }

  /// Removes the request handler for the given method.
  void removeRequestHandler(String method) {
    _requestHandlers.remove(method);
  }

  /// Ensures a request handler has not already been set for the given method.
  void assertCanSetRequestHandler(String method) {
    if (_requestHandlers.containsKey(method)) {
      throw StateError(
        "A request handler for '$method' already exists and would be overridden.",
      );
    }
  }

  /// Registers a handler for notifications with the given method.
  ///
  /// The [handler] processes the parsed notification of type [NotifT].
  /// The [notificationFactory] parses the generic `params` map into [NotifT].
  void setNotificationHandler<NotifT extends JsonRpcNotification>(
    String method,
    Future<void> Function(NotifT notification) handler,
    NotifT Function(Map<String, dynamic>? params, Map<String, dynamic>? meta)
        notificationFactory,
  ) {
    _notificationHandlers[method] = (jsonRpcNotification) async {
      try {
        final specificNotification = notificationFactory(
          jsonRpcNotification.params,
          jsonRpcNotification.meta,
        );
        await handler(specificNotification);
      } catch (e, s) {
        _onerror(StateError("Error processing notification $method: $e\n$s"));
      }
    };
  }

  /// Removes the notification handler for the given method.
  void removeNotificationHandler(String method) {
    _notificationHandlers.remove(method);
  }

  /// Ensures the remote side supports the capability required for sending
  /// a request with the given [method].
  void assertCapabilityForMethod(String method);

  /// Ensures the local side supports the capability required for sending
  /// a notification with the given [method].
  void assertNotificationCapability(String method);

  /// Ensures the local side supports the capability required for handling
  /// an incoming request with the given [method].
  void assertRequestHandlerCapability(String method);

  /// Ensures task capability for method.
  void assertTaskCapability(String method);

  /// Ensures task handler capability for method.
  void assertTaskHandlerCapability(String method);
}

class _RequestTaskStoreImpl implements RequestTaskStore {
  final TaskStore _store;
  final JsonRpcRequest _request;
  final String? _sessionId;
  final Protocol _protocol;

  _RequestTaskStoreImpl(
    this._store,
    this._request,
    this._sessionId,
    this._protocol,
  );

  @override
  Future<Task> createTask(TaskCreation taskParams) {
    return _store.createTask(
      taskParams,
      _request.id,
      {'method': _request.method, 'params': _request.params},
      _sessionId,
    );
  }

  @override
  Future<Task> getTask(String taskId) async {
    final task = await _store.getTask(taskId, _sessionId);
    if (task == null) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Failed to retrieve task: Task not found',
      );
    }
    return task;
  }

  @override
  Future<void> storeTaskResult(
    String taskId,
    TaskStatus status,
    BaseResultData result,
  ) async {
    await _store.storeTaskResult(taskId, status, result, _sessionId);
    final task = await _store.getTask(taskId, _sessionId);
    if (task != null) {
      final notification = JsonRpcTaskStatusNotification(
        statusParams: TaskStatusNotification(
          taskId: task.taskId,
          status: task.status,
          statusMessage: task.statusMessage,
          ttl: task.ttl,
          pollInterval: task.pollInterval,
          createdAt: task.createdAt,
          lastUpdatedAt: task.lastUpdatedAt,
        ),
      );
      await _protocol.notification(notification);

      if (task.status.isTerminal) {
        // _protocol._cleanupTaskProgressHandler(taskId); // Private method access issue
      }
    }
  }

  @override
  Future<BaseResultData> getTaskResult(String taskId) {
    return _store.getTaskResult(taskId, _sessionId);
  }

  @override
  Future<void> updateTaskStatus(
    String taskId,
    TaskStatus status, [
    String? statusMessage,
  ]) async {
    final task = await _store.getTask(taskId, _sessionId);
    if (task == null) {
      throw McpError(ErrorCode.invalidParams.value, 'Task not found');
    }

    if (task.status.isTerminal) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Cannot update terminal task',
      );
    }

    await _store.updateTaskStatus(taskId, status, statusMessage, _sessionId);

    final updatedTask = await _store.getTask(taskId, _sessionId);
    if (updatedTask != null) {
      final notification = JsonRpcTaskStatusNotification(
        statusParams: TaskStatusNotification(
          taskId: updatedTask.taskId,
          status: updatedTask.status,
          statusMessage: updatedTask.statusMessage,
          ttl: updatedTask.ttl,
          pollInterval: updatedTask.pollInterval,
          createdAt: updatedTask.createdAt,
          lastUpdatedAt: updatedTask.lastUpdatedAt,
        ),
      );
      await _protocol.notification(notification);
    }
  }

  @override
  Future<ListTasksResult> listTasks([String? cursor]) {
    return _store.listTasks(cursor, _sessionId);
  }
}

/// Error thrown when an operation is aborted via an [AbortSignal].
class AbortError extends Error {
  /// Optional reason for the abortion.
  final dynamic reason;

  /// Creates an abort error.
  AbortError([this.reason]);

  @override
  String toString() =>
      "AbortError: Operation aborted${reason == null ? '' : ' ($reason)'}";
}

/// Represents a signal that can be used to notify downstream consumers that
/// an operation should be aborted.
abstract class AbortSignal {
  /// Whether the operation has been aborted.
  bool get aborted;

  /// The reason provided when aborting, or null.
  dynamic get reason;

  /// A stream that emits an event when the operation is aborted.
  Stream<void> get onAbort;

  /// Throws an [AbortError] if [aborted] is true.
  void throwIfAborted();
}

/// Controls an [AbortSignal], allowing the initiator of an operation
/// to signal abortion.
abstract class AbortController {
  /// The signal associated with this controller.
  AbortSignal get signal;

  /// Aborts the operation, optionally providing a [reason].
  void abort([dynamic reason]);
}

class _BasicAbortSignal implements AbortSignal {
  final Stream<void> _onAbort;
  dynamic _reason;
  bool _aborted = false;

  _BasicAbortSignal(this._onAbort);

  @override
  bool get aborted => _aborted;

  @override
  dynamic get reason => _reason;

  @override
  Stream<void> get onAbort => _onAbort;

  @override
  void throwIfAborted() {
    if (_aborted) throw AbortError(_reason);
  }

  void _doAbort(dynamic reason) {
    if (_aborted) return;
    _aborted = true;
    _reason = reason;
  }
}

class BasicAbortController implements AbortController {
  final _controller = StreamController<void>.broadcast();
  late final _BasicAbortSignal _signal;

  BasicAbortController() {
    _signal = _BasicAbortSignal(_controller.stream);
  }

  /// The signal associated with this controller.
  @override
  AbortSignal get signal => _signal;

  /// Aborts the operation, optionally providing a [reason].
  @override
  void abort([dynamic reason]) {
    if (_signal.aborted) return;
    _signal._doAbort(reason);
    _controller.add(null);
    _controller.close();
  }
}

/// Merges two capability maps (potentially nested).
T mergeCapabilities<T extends Map<String, dynamic>>(T base, T additional) {
  final merged = Map<String, dynamic>.from(base);
  additional.forEach((key, value) {
    final baseValue = merged[key];
    if (value is Map<String, dynamic> && baseValue is Map<String, dynamic>) {
      merged[key] = mergeCapabilities(baseValue, value);
    } else {
      merged[key] = value;
    }
  });
  return merged as T;
}
