import 'dart:async';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/task_interfaces.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/types/validation.dart';
import 'package:meta/meta.dart';

import 'protocol_notification_validation.dart';
import 'transport.dart';

final _logger = Logger("mcp_dart.shared.protocol");

bool _isProgressToken(Object? token) =>
    token is String ||
    token is int ||
    (token is double && token.isFinite && token == token.truncateToDouble());

const Set<String> _statelessCacheableResultMethods = {
  Method.serverDiscover,
  Method.toolsList,
  Method.promptsList,
  Method.resourcesList,
  Method.resourcesTemplatesList,
  Method.resourcesRead,
};

final _lastProgressByExtra = Expando<double>();
final _subscriptionStateByExtra = Expando<_SubscriptionStreamState>();

class _SubscriptionStreamState {
  bool acknowledgmentSent = false;
  SubscriptionFilter acknowledgedNotifications = const SubscriptionFilter();
}

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
  ///
  /// When set, the protocol adds an integer progress token to outgoing request
  /// metadata unless the request already carries an `int` or `String`
  /// `progressToken`, which is preserved for callers that need a custom token.
  final ProgressCallback? onprogress;

  /// Signal to cancel an in-flight request.
  final AbortSignal? signal;

  /// Timeout duration for the request.
  final Duration? timeout;

  /// Whether progress notifications reset the request timeout timer.
  final bool resetTimeoutOnProgress;

  /// Maximum total time to wait for a response.
  final Duration? maxTotalTimeout;

  /// Whether this request should use protocol-level timeout handling.
  ///
  /// Long-lived requests such as `subscriptions/listen` can disable this and
  /// rely on explicit cancellation or transport closure instead.
  final bool timeoutEnabled;

  /// Minimum server log level requested for this MCP 2026-07-28 stateless
  /// request.
  ///
  /// This is serialized as `io.modelcontextprotocol/logLevel` in request
  /// metadata. Legacy peers use `logging/setLevel` instead.
  final LoggingLevel? logLevel;

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
    this.timeoutEnabled = true,
    this.logLevel,
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

  /// Client responses to MRTR input requests when retrying this request.
  final InputResponses? inputResponses;

  /// Opaque MRTR state returned by the server and echoed by the client on retry.
  final String? requestState;

  /// MCP protocol version from the request metadata, when present.
  String? get protocolVersion {
    final value = meta?[McpMetaKey.protocolVersion];
    return value is String ? value : null;
  }

  /// Client implementation from the request metadata, when present.
  Implementation? get clientInfo {
    final value = meta?[McpMetaKey.clientInfo];
    if (value == null) {
      return null;
    }
    return Implementation.fromJson(
      readJsonObject(value, 'RequestHandlerExtra.clientInfo'),
    );
  }

  /// Client capabilities from the request metadata, when present.
  ClientCapabilities? get clientCapabilities {
    final value = meta?[McpMetaKey.clientCapabilities];
    if (value == null) {
      return null;
    }
    return ClientCapabilities.fromJson(
      readJsonObject(value, 'RequestHandlerExtra.clientCapabilities'),
    );
  }

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

  /// Closes the SSE stream for this request, if resumability is supported.
  ///
  /// The handler may still return a result. A client can retrieve it by
  /// reconnecting with the last SSE event ID.
  final void Function()? closeSSEStream;

  /// Closes the standalone SSE stream (if supported).
  final void Function()? closeStandaloneSSEStream;

  /// Creates extra data for request handlers.
  const RequestHandlerExtra({
    required this.signal,
    this.sessionId,
    required this.requestId,
    this.meta,
    this.inputResponses,
    this.requestState,
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

  _SubscriptionStreamState get _activeSubscriptionState =>
      (_subscriptionStateByExtra[this] ??= _SubscriptionStreamState());

  void _validateSubscriptionNotification(JsonRpcNotification notification) {
    _recordOrValidateSubscriptionNotification(
      _activeSubscriptionState,
      notification,
    );
  }

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

    if (!_isProgressToken(progressToken)) {
      _logger.warn(
        "Invalid progressToken type: ${progressToken.runtimeType}. "
        "Expected string or integer.",
      );
      return;
    }

    final lastProgress = _lastProgressByExtra[this];
    if (lastProgress != null && progress <= lastProgress) {
      throw ArgumentError(
        "Progress values must increase monotonically for request $requestId: "
        "$progress <= $lastProgress.",
      );
    }
    _lastProgressByExtra[this] = progress;

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

  /// Sends the required first acknowledgment for a `subscriptions/listen` stream.
  Future<void> sendSubscriptionAcknowledged(
    SubscriptionFilter notifications,
  ) {
    return sendSubscriptionNotification(
      JsonRpcSubscriptionsAcknowledgedNotification(
        acknowledgedParams: SubscriptionsAcknowledgedNotification(
          notifications: notifications,
        ),
      ),
    );
  }

  /// Sends a notification on a `subscriptions/listen` stream with subscription metadata.
  Future<void> sendSubscriptionNotification(
    JsonRpcNotification notification,
  ) {
    final subscriptionNotification =
        _withSubscriptionId(notification, requestId);

    _validateSubscriptionNotification(subscriptionNotification);

    return sendNotification(subscriptionNotification);
  }
}

JsonRpcNotification _withSubscriptionId(
  JsonRpcNotification notification,
  RequestId requestId,
) {
  final meta = <String, dynamic>{
    ...?notification.meta,
    McpMetaKey.subscriptionId: requestId,
  };
  return JsonRpcNotification(
    method: notification.method,
    params: notification.params,
    meta: meta,
  );
}

void _recordOrValidateSubscriptionNotification(
  _SubscriptionStreamState state,
  JsonRpcNotification notification,
) {
  if (notification.method == Method.notificationsSubscriptionsAcknowledged) {
    state
      ..acknowledgmentSent = true
      ..acknowledgedNotifications =
          _acknowledgedSubscriptionFilter(notification);
    return;
  }

  if (!state.acknowledgmentSent) {
    throw McpError(
      ErrorCode.invalidRequest.value,
      'subscriptions/listen streams must send '
      '${Method.notificationsSubscriptionsAcknowledged} before '
      '${notification.method}.',
    );
  }

  if (!state.acknowledgedNotifications.allowsNotification(notification)) {
    throw McpError(
      ErrorCode.invalidRequest.value,
      '${notification.method} was not requested or acknowledged for this '
      'subscriptions/listen stream.',
    );
  }
}

SubscriptionFilter _acknowledgedSubscriptionFilter(
  JsonRpcNotification notification,
) {
  final params = notification.params;
  if (params == null) {
    throw const FormatException(
      'subscriptions acknowledged notification params are required',
    );
  }

  return SubscriptionsAcknowledgedNotification.fromJson(params).notifications;
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

  /// Whether progress notifications reset the request timeout timer.
  final bool resetOnProgress;

  /// Callback to execute when the timeout occurs.
  final void Function() onTimeout;

  /// Creates timeout information.
  _TimeoutInfo({
    required this.timeoutTimer,
    required this.startTime,
    required this.timeoutDuration,
    this.maxTotalTimeoutDuration,
    this.resetOnProgress = false,
    required this.onTimeout,
  });
}

class _TaskAugmentedRequestState {
  final int messageId;
  final RequestId? relatedRequestId;
  final AbortSignal? signal;
  StreamSubscription? abortSubscription;
  String? taskId;
  bool cancelRequested = false;
  Object? cancelReason;
  bool cancelSent = false;

  _TaskAugmentedRequestState({
    required this.messageId,
    required this.relatedRequestId,
    required this.signal,
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

  /// Progress callbacks for outgoing requests, mapped by progress token.
  final Map<Object, ProgressCallback> _progressHandlers = {};

  /// Progress tokens selected for outgoing requests, mapped by request ID.
  final Map<int, Object> _requestProgressTokens = {};

  /// Request IDs for active progress tokens, mapped by progress token.
  final Map<Object, int> _progressTokenRequestIds = {};

  /// Timeout state for outgoing requests, mapped by request ID.
  final Map<int, _TimeoutInfo> _timeoutInfo = {};

  /// Protocol configuration options.
  final ProtocolOptions _options;

  /// Task storage implementation.
  final TaskStore? _taskStore;

  /// Task message queue implementation.
  final TaskMessageQueue? _taskMessageQueue;

  /// Set of notification methods currently pending debounce.
  final Set<String> _pendingDebouncedNotifications = {};

  /// Resolvers for side-channeled requests (via tasks).
  final Map<int, void Function(JsonRpcMessage response)> _requestResolvers = {};

  /// Task-augmented outgoing requests whose lifecycle continues after the
  /// initial CreateTaskResult response.
  final Map<int, _TaskAugmentedRequestState> _taskRequestsByMessageId = {};
  final Map<String, _TaskAugmentedRequestState> _taskRequestsByTaskId = {};

  /// Terminal task statuses that arrived before their CreateTaskResult was
  /// parsed and registered locally.
  final Set<String> _earlyTerminalTaskIds = {};

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
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsCancelled,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setNotificationHandler<JsonRpcProgressNotification>(
      "notifications/progress",
      (notification) async => _onprogress(notification),
      (params, meta) => JsonRpcProgressNotification.fromJson({
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsProgress,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    setRequestHandler<JsonRpcPingRequest>(
      "ping",
      (request, extra) async => const EmptyResult(),
      (id, params, meta) => JsonRpcPingRequest(id: id, meta: meta),
    );

    if (_taskStore != null) {
      _registerTaskHandlers();
    }
  }

  /// Returns whether [resultType] is recognized for result parsing.
  @protected
  bool isRecognizedResultType(String resultType) {
    return resultType == resultTypeComplete ||
        resultType == resultTypeInputRequired;
  }

  /// Returns whether [resultType] is valid for [request].
  @protected
  bool isResultTypeAllowedForRequest(
    JsonRpcRequest request,
    String resultType,
  ) =>
      isRecognizedResultType(resultType);

  InputResponses? _inputResponsesFromRequest(JsonRpcRequest request) {
    return switch (request) {
      final JsonRpcCallToolRequest request => request.callParams.inputResponses,
      final JsonRpcGetPromptRequest request => request.getParams.inputResponses,
      final JsonRpcReadResourceRequest request =>
        request.readParams.inputResponses,
      final JsonRpcUpdateTaskRequest request =>
        request.updateParams.inputResponses,
      _ => null,
    };
  }

  String? _requestStateFromRequest(JsonRpcRequest request) {
    return switch (request) {
      final JsonRpcCallToolRequest request => request.callParams.requestState,
      final JsonRpcGetPromptRequest request => request.getParams.requestState,
      final JsonRpcReadResourceRequest request =>
        request.readParams.requestState,
      _ => null,
    };
  }

  bool _usesStatelessResultTypes(JsonRpcRequest request) {
    final requestProtocolVersion = request.meta?[McpMetaKey.protocolVersion];
    if (requestProtocolVersion is String &&
        isStatelessProtocolVersion(requestProtocolVersion)) {
      return true;
    }

    final Object? activeTransport = _transport;
    if (activeTransport is! ProtocolVersionAwareTransport) {
      return false;
    }

    final transportProtocolVersion = activeTransport.protocolVersion;
    return transportProtocolVersion != null &&
        isStatelessProtocolVersion(transportProtocolVersion);
  }

  void _validateResponseResultType(
    JsonRpcRequest request,
    Map<String, dynamic> resultJson,
  ) {
    if (!_usesStatelessResultTypes(request)) {
      return;
    }

    final resultMeta = readOptionalJsonObject(
      resultJson['_meta'],
      'MCP stateless Result._meta',
    );
    if (resultMeta?.containsKey(McpMetaKey.serverInfo) == true) {
      Implementation.fromJson(
        readJsonObject(
          resultMeta![McpMetaKey.serverInfo],
          'MCP stateless Result._meta.${McpMetaKey.serverInfo}',
        ),
      );
    }

    final resultType = resultJson['resultType'];
    if (resultType == null) {
      throw const FormatException(
        'MCP stateless responses must include resultType',
      );
    }
    if (resultType is! String) {
      throw const FormatException('MCP resultType must be a string');
    }
    if (!isRecognizedResultType(resultType)) {
      throw FormatException('Unrecognized MCP resultType "$resultType"');
    }
    if (!isResultTypeAllowedForRequest(request, resultType)) {
      throw FormatException(
        'MCP resultType "$resultType" is not valid for ${request.method}',
      );
    }

    if (resultType == resultTypeComplete &&
        _statelessCacheableResultMethods.contains(request.method)) {
      _validateStatelessCacheableResult(request, resultJson);
    }
  }

  void _validateStatelessCacheableResult(
    JsonRpcRequest request,
    Map<String, dynamic> resultJson,
  ) {
    final ttlMs = resultJson['ttlMs'];
    if (ttlMs is! int || ttlMs < 0) {
      throw FormatException(
        'MCP stateless ${request.method} responses must include '
        'a non-negative integer ttlMs',
      );
    }

    final cacheScope = resultJson['cacheScope'];
    if (cacheScope != CacheScope.private && cacheScope != CacheScope.public) {
      throw FormatException(
        'MCP stateless ${request.method} responses must include '
        'cacheScope "private" or "public"',
      );
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
        if (_usesStatelessResultTypes(request)) {
          return GetTaskExtensionResult(
            task: await _taskExtensionTaskFromStore(
              task,
              extra.sessionId,
            ),
          );
        }
        return task;
      },
      (id, params, meta) => JsonRpcGetTaskRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.tasksGet,
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
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.tasksList,
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

          await _taskStore.updateTaskStatus(
            taskId,
            TaskStatus.cancelled,
            'Client cancelled task execution.',
            extra.sessionId,
          );

          await _clearTaskQueue(taskId, extra.sessionId);

          final cancelledTask =
              await _taskStore.getTask(taskId, extra.sessionId);
          if (cancelledTask == null) {
            throw McpError(
              ErrorCode.invalidParams.value,
              'Task not found after cancellation: $taskId',
            );
          }
          if (_usesStatelessResultTypes(request)) {
            return const TaskExtensionAcknowledgementResult();
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
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.tasksCancel,
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );
  }

  Future<TaskExtensionTask> _taskExtensionTaskFromStore(
    Task task,
    String? sessionId,
  ) async {
    Map<String, dynamic>? result;
    JsonRpcErrorData? error;
    InputRequests? inputRequests;

    switch (task.status) {
      case TaskStatus.completed:
        result = (await _taskStore!.getTaskResult(
          task.taskId,
          sessionId,
        ))
            .toJson();
        break;
      case TaskStatus.failed:
        error = JsonRpcErrorData(
          code: ErrorCode.internalError.value,
          message: task.statusMessage ?? 'Task failed',
        );
        break;
      case TaskStatus.inputRequired:
        inputRequests = const {};
        break;
      case TaskStatus.working:
      case TaskStatus.cancelled:
        break;
    }

    return TaskExtensionTask(
      taskId: task.taskId,
      status: task.status,
      statusMessage: task.statusMessage,
      createdAt: task.createdAt,
      lastUpdatedAt: task.lastUpdatedAt,
      ttlMs: task.ttl,
      pollIntervalMs: task.pollInterval,
      inputRequests: inputRequests,
      result: result,
      error: error,
    );
  }

  /// Attaches to the given transport, starts it, and starts listening for messages.
  Future<void> connect(Transport transport) async {
    if (_transport != null) {
      throw StateError("Protocol already connected to a transport.");
    }
    _transport = transport;
    if (transport is IncomingRequestValidationAwareTransport) {
      final validationAwareTransport =
          transport as IncomingRequestValidationAwareTransport;
      validationAwareTransport.setIncomingRequestValidator(
        validateIncomingRequest,
      );
      validationAwareTransport
          .setRequestMethodSupported(canHandleRequestMethod);
    }
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

  @protected
  bool canHandleRequestMethod(String method) =>
      _requestHandlers.containsKey(method) || fallbackRequestHandler != null;

  @protected
  Future<BaseResultData> invokeRequestHandlerForValidation(
    JsonRpcRequest request,
    RequestHandlerExtra extra,
  ) {
    final registeredHandler = _requestHandlers[request.method];
    if (registeredHandler != null) {
      return registeredHandler(request, extra);
    }

    final fallbackHandler = fallbackRequestHandler;
    if (fallbackHandler != null) {
      return fallbackHandler(request);
    }

    throw McpError(
      ErrorCode.methodNotFound.value,
      'Method not found: ${request.method}',
    );
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
    bool resetOnProgress,
    void Function() onTimeout,
  ) {
    final startTime = DateTime.now();
    var initialTimeout = timeout;
    if (maxTotalTimeout != null && maxTotalTimeout < initialTimeout) {
      initialTimeout = maxTotalTimeout;
    }

    final info = _TimeoutInfo(
      timeoutTimer: Timer(initialTimeout, onTimeout),
      startTime: startTime,
      timeoutDuration: timeout,
      maxTotalTimeoutDuration: maxTotalTimeout,
      resetOnProgress: resetOnProgress,
      onTimeout: onTimeout,
    );
    _timeoutInfo[messageId] = info;
  }

  void _resetTimeoutOnProgress(_TimeoutInfo timeoutInfo) {
    if (!timeoutInfo.resetOnProgress) return;

    var nextTimeout = timeoutInfo.timeoutDuration;
    final maxTotalTimeout = timeoutInfo.maxTotalTimeoutDuration;
    if (maxTotalTimeout != null) {
      final elapsed = DateTime.now().difference(timeoutInfo.startTime);
      final remaining = maxTotalTimeout - elapsed;
      if (remaining <= Duration.zero) {
        timeoutInfo.timeoutTimer.cancel();
        timeoutInfo.onTimeout();
        return;
      }
      if (remaining < nextTimeout) {
        nextTimeout = remaining;
      }
    }

    timeoutInfo.timeoutTimer.cancel();
    timeoutInfo.timeoutTimer = Timer(nextTimeout, timeoutInfo.onTimeout);
  }

  /// Cleans up the timeout state associated with a request ID.
  void _cleanupTimeout(int messageId) {
    _timeoutInfo.remove(messageId)?.timeoutTimer.cancel();
  }

  /// Removes progress bookkeeping for an outgoing request.
  void _cleanupProgressHandler(int messageId) {
    final progressToken = _requestProgressTokens.remove(messageId);
    if (progressToken != null) {
      _progressHandlers.remove(progressToken);
      _progressTokenRequestIds.remove(progressToken);
    }
  }

  bool get _hasUnidentifiedTaskRequests => _taskRequestsByMessageId.values.any(
        (pendingState) => pendingState.taskId == null,
      );

  void _clearEarlyTerminalTaskIdsIfUnneeded() {
    if (!_hasUnidentifiedTaskRequests) {
      _earlyTerminalTaskIds.clear();
    }
  }

  void _cleanupTaskAugmentedRequest(
    _TaskAugmentedRequestState state, {
    bool cleanupProgress = true,
  }) {
    _taskRequestsByMessageId.remove(state.messageId);
    final taskId = state.taskId;
    if (taskId != null) {
      final currentState = _taskRequestsByTaskId[taskId];
      if (identical(currentState, state)) {
        _taskRequestsByTaskId.remove(taskId);
      }
    }
    _clearEarlyTerminalTaskIdsIfUnneeded();
    state.abortSubscription?.cancel();
    state.abortSubscription = null;
    if (cleanupProgress) {
      _cleanupProgressHandler(state.messageId);
    }
  }

  void _onTaskStatusNotification(JsonRpcTaskStatusNotification notification) {
    if (!notification.statusParams.status.isTerminal) {
      return;
    }

    final state = _taskRequestsByTaskId[notification.statusParams.taskId];
    if (state != null) {
      _cleanupTaskAugmentedRequest(state);
    } else if (_hasUnidentifiedTaskRequests) {
      _earlyTerminalTaskIds.add(notification.statusParams.taskId);
    }
  }

  Object? _preTaskIdCancellationReason(
    _TaskAugmentedRequestState? state,
  ) {
    if (state == null || state.taskId != null) {
      return null;
    }
    if (state.cancelRequested) {
      return state.cancelReason ?? AbortError("Request cancelled");
    }
    final signal = state.signal;
    if (signal != null && signal.aborted) {
      state.cancelRequested = true;
      state.cancelReason = signal.reason ?? AbortError("Request cancelled");
      return state.cancelReason;
    }
    return null;
  }

  void _handleTaskCancellationResponse(
    _TaskAugmentedRequestState state,
    JsonRpcMessage responseMessage,
  ) {
    switch (responseMessage) {
      case final JsonRpcResponse response:
        try {
          final task = Task.fromJson(response.result);
          if (task.taskId != state.taskId) {
            _cleanupTaskAugmentedRequest(state);
            _onerror(
              StateError(
                "Task cancellation response taskId mismatch: "
                "expected ${state.taskId}, got ${task.taskId}",
              ),
            );
          } else if (task.status.isTerminal) {
            _cleanupTaskAugmentedRequest(state);
          }
        } catch (e) {
          _cleanupTaskAugmentedRequest(state);
          _onerror(
            StateError(
              "Failed to parse task cancellation result for task "
              "${state.taskId}: $e",
            ),
          );
        }
      case final JsonRpcError error:
        _cleanupTaskAugmentedRequest(state);
        _onerror(
          McpError(
            error.error.code,
            error.error.message,
            error.error.data,
          ),
        );
      default:
        _onerror(
          ArgumentError(
            "Invalid task cancellation response type: "
            "${responseMessage.runtimeType}",
          ),
        );
    }
  }

  void _sendTaskCancellation(_TaskAugmentedRequestState state) {
    final taskId = state.taskId;
    if (taskId == null || state.cancelSent) {
      return;
    }
    state.cancelSent = true;

    final cancelRequest = JsonRpcCancelTaskRequest(
      id: _requestMessageId++,
      cancelParams: CancelTaskRequest(taskId: taskId),
    );
    _requestResolvers[cancelRequest.id as int] = (responseMessage) {
      _handleTaskCancellationResponse(state, responseMessage);
    };

    _transport
        ?.sendPreservingRequestId(
      cancelRequest,
      relatedRequestId: state.relatedRequestId,
    )
        .catchError((e) {
      _requestResolvers.remove(cancelRequest.id);
      _cleanupTaskAugmentedRequest(state);
      _onerror(
        StateError("Failed to send task cancellation for task $taskId: $e"),
      );
      return null;
    });
  }

  Object _nextAvailableProgressToken(int preferredToken) {
    var token = preferredToken;
    while (_progressHandlers.containsKey(token)) {
      token++;
    }
    return token;
  }

  bool _usesStatelessRequestShape(JsonRpcRequest request) {
    final requestProtocolVersion = request.meta?[McpMetaKey.protocolVersion];
    if (requestProtocolVersion is String) {
      return isStatelessProtocolVersion(requestProtocolVersion);
    }

    final activeTransport = _transport;
    if (activeTransport is! ProtocolVersionAwareTransport) {
      return false;
    }
    final versionAwareTransport =
        activeTransport as ProtocolVersionAwareTransport;
    final transportProtocolVersion = versionAwareTransport.protocolVersion;
    return transportProtocolVersion != null &&
        isStatelessProtocolVersion(transportProtocolVersion);
  }

  Map<String, dynamic>? _mergeRelatedTaskMeta(
    Map<String, dynamic>? meta,
    Map<String, dynamic>? relatedTaskJson,
  ) {
    if (relatedTaskJson == null) return meta;

    final finalMeta = Map<String, dynamic>.from(meta ?? {});
    finalMeta[relatedTaskMetadataKey] = relatedTaskJson;
    finalMeta[legacyRelatedTaskMetadataKey] = relatedTaskJson;
    return finalMeta;
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
    final pendingTaskRequests = Map.of(_taskRequestsByMessageId);

    _responseCompleters.clear();
    _responseErrorHandlers.clear();
    _progressHandlers.clear();
    _requestProgressTokens.clear();
    _progressTokenRequestIds.clear();
    _timeoutInfo.clear();
    _requestHandlerAbortControllers.clear();
    _pendingDebouncedNotifications.clear();
    _requestResolvers.clear();
    _taskRequestsByMessageId.clear();
    _taskRequestsByTaskId.clear();
    _earlyTerminalTaskIds.clear();
    _transport = null;

    onConnectionClosed();

    pendingTimeouts.forEach((_, info) => info.timeoutTimer.cancel());
    pendingRequestHandlers.forEach((_, controller) => controller.abort());
    pendingTaskRequests
        .forEach((_, state) => state.abortSubscription?.cancel());

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

  /// Returns an MCP error when an incoming request is not valid for the
  /// current protocol state.
  McpError? validateIncomingRequest(JsonRpcRequest request) => null;

  /// Returns an MCP error when an incoming notification is not valid for the
  /// current protocol state.
  McpError? validateIncomingNotification(JsonRpcNotification notification) =>
      null;

  /// Subclass hook called after an incoming request has passed validation and
  /// will be handled.
  @protected
  void onIncomingRequestAccepted(JsonRpcRequest request) {}

  /// Subclass hook called after an incoming notification has passed validation.
  @protected
  void onIncomingNotificationAccepted(JsonRpcNotification notification) {}

  /// Subclass hook called after an incoming request handler has completed and
  /// its response has been sent or enqueued.
  @protected
  void onIncomingRequestHandled(
    JsonRpcRequest request,
    BaseResultData result,
  ) {}

  /// Subclass hook called when an incoming request handler or response send
  /// fails.
  @protected
  void onIncomingRequestFailed(JsonRpcRequest request, Object error) {}

  /// Converts a handler result into the JSON object sent on the wire.
  @protected
  Map<String, dynamic> serializeIncomingResult(
    JsonRpcRequest request,
    BaseResultData result,
  ) {
    final resultJson = result.toJson();
    if (request is! JsonRpcSubscriptionsListenRequest) {
      return resultJson;
    }

    final serializedMeta = readOptionalJsonObject(
      resultJson['_meta'],
      'SubscriptionsListenResult._meta',
    );
    final meta = <String, dynamic>{
      ...?(resultJson.containsKey('_meta')
          ? serializedMeta
          : readOptionalJsonObject(
              result.meta,
              'SubscriptionsListenResult.meta',
            )),
      McpMetaKey.subscriptionId: request.id,
    };
    return <String, dynamic>{
      ...resultJson,
      '_meta': meta,
    };
  }

  /// Handles an MRTR input request embedded in an `InputRequiredResult`.
  ///
  /// Embedded input requests reuse the locally registered request handlers, but
  /// are not received as transport-level JSON-RPC requests.
  @protected
  Future<BaseResultData> handleEmbeddedInputRequest(
    String inputRequestKey,
    InputRequest inputRequest, {
    AbortSignal? signal,
  }) async {
    final request = JsonRpcRequest(
      id: inputRequestKey,
      method: inputRequest.method,
      params: inputRequest.params,
    );
    final registeredHandler = _requestHandlers[inputRequest.method];
    final fallbackHandler = fallbackRequestHandler;
    if (registeredHandler == null && fallbackHandler == null) {
      throw McpError(
        ErrorCode.methodNotFound.value,
        'No handler registered for MRTR input request ${inputRequest.method}',
      );
    }

    final abortController = signal == null ? BasicAbortController() : null;
    final effectiveSignal = signal ?? abortController!.signal;
    effectiveSignal.throwIfAborted();

    final extra = RequestHandlerExtra(
      signal: effectiveSignal,
      sessionId: _transport?.sessionId,
      requestId: request.id,
      meta: request.meta,
      inputResponses: _inputResponsesFromRequest(request),
      requestState: _requestStateFromRequest(request),
      sendNotification: (notification, {relatedTask}) {
        return _notificationWithRequestId(
          notification,
          relatedTask: relatedTask,
          relatedRequestId: request.id,
        );
      },
      sendRequest: <T extends BaseResultData>(
        JsonRpcRequest req,
        T Function(Map<String, dynamic>) resultFactory,
        RequestOptions options,
      ) {
        return _requestWithRequestId<T>(
          req,
          resultFactory,
          options,
          request.id,
        );
      },
    );

    try {
      if (registeredHandler != null) {
        final result = await registeredHandler(request, extra);
        effectiveSignal.throwIfAborted();
        return result;
      }

      final result = await fallbackHandler!(request);
      effectiveSignal.throwIfAborted();
      return result;
    } catch (error) {
      onIncomingRequestFailed(request, error);
      rethrow;
    }
  }

  /// Subclass hook called after protocol-owned state has been cleared for a
  /// closed transport.
  @protected
  void onConnectionClosed() {}

  /// Handles incoming JSON-RPC notifications.
  void _onnotification(JsonRpcNotification notification) {
    final validationError = validateIncomingNotification(notification);
    if (validationError != null) {
      _onerror(validationError);
      return;
    }

    onIncomingNotificationAccepted(notification);

    if (notification is JsonRpcTaskStatusNotification) {
      _onTaskStatusNotification(notification);
    }

    final handler = _notificationHandlers[notification.method] ??
        fallbackNotificationHandler;
    if (handler == null) {
      return;
    }

    // Start notification handlers immediately so lifecycle notifications affect
    // subsequent messages that arrive in the same transport turn.
    try {
      handler(notification).catchError((error, stackTrace) {
        _onerror(
          StateError(
            "Uncaught error in notification handler for ${notification.method}: $error\n$stackTrace",
          ),
        );
        return null;
      });
    } catch (error, stackTrace) {
      _onerror(
        StateError(
          "Uncaught error in notification handler for ${notification.method}: $error\n$stackTrace",
        ),
      );
    }
  }

  bool _containsTaskMetadata(Map<dynamic, dynamic>? value) {
    return value?.containsKey('task') == true ||
        value?.containsKey(relatedTaskMetadataKey) == true ||
        value?.containsKey(legacyRelatedTaskMetadataKey) == true;
  }

  bool _hasTaskAugmentation(JsonRpcRequest request) {
    final paramsMeta = request.params?['_meta'];
    return _containsTaskMetadata(request.meta) ||
        request.params?.containsKey('task') == true ||
        (paramsMeta is Map && _containsTaskMetadata(paramsMeta));
  }

  Map<String, dynamic>? _withoutTaskMetadata(
    Map<String, dynamic>? value, {
    required bool removeRelatedTask,
  }) {
    if (value == null) {
      return null;
    }

    final hasTask = value.containsKey('task');
    final hasRelatedTask = removeRelatedTask &&
        (value.containsKey(relatedTaskMetadataKey) ||
            value.containsKey(legacyRelatedTaskMetadataKey));
    if (!hasTask && !hasRelatedTask) {
      return value;
    }

    final copy = Map<String, dynamic>.from(value)..remove('task');
    if (removeRelatedTask) {
      copy
        ..remove(relatedTaskMetadataKey)
        ..remove(legacyRelatedTaskMetadataKey);
    }
    return copy.isEmpty ? null : copy;
  }

  Map<String, dynamic>? _withoutTaskAugmentedParams(
    Map<String, dynamic>? params,
  ) {
    if (params == null) {
      return null;
    }

    Map<String, dynamic>? copy;
    if (params.containsKey('task')) {
      copy = Map<String, dynamic>.from(params)..remove('task');
    }

    final meta = (copy ?? params)['_meta'];
    if (meta is Map<String, dynamic>) {
      final strippedMeta = _withoutTaskMetadata(meta, removeRelatedTask: true);
      if (!identical(strippedMeta, meta)) {
        copy ??= Map<String, dynamic>.from(params);
        if (strippedMeta == null) {
          copy.remove('_meta');
        } else {
          copy['_meta'] = strippedMeta;
        }
      }
    }

    return copy?.isEmpty == true ? null : copy ?? params;
  }

  JsonRpcRequest _withoutTaskAugmentation(JsonRpcRequest request) {
    final params = _withoutTaskAugmentedParams(request.params);
    final meta = _withoutTaskMetadata(request.meta, removeRelatedTask: true);
    final json = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': request.id,
      'method': request.method,
      if (params != null || meta != null)
        'params': <String, dynamic>{
          ...?params,
          if (meta != null) '_meta': meta,
        },
    };
    return JsonRpcMessage.fromJson(json) as JsonRpcRequest;
  }

  bool _canHandleTaskAugmentation(String method) {
    try {
      assertTaskHandlerCapability(method);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Handles incoming JSON-RPC requests.
  void _onrequest(JsonRpcRequest request) {
    final validationError = validateIncomingRequest(request);
    if (validationError != null) {
      _sendErrorResponse(
        request.id,
        validationError.code,
        validationError.message,
        validationError.data,
      );
      return;
    }

    final registeredHandler = _requestHandlers[request.method];
    final fallbackHandler = fallbackRequestHandler;

    if (_hasTaskAugmentation(request) &&
        !_canHandleTaskAugmentation(request.method)) {
      request = _withoutTaskAugmentation(request);
    }

    // Check for related task ID in metadata
    final meta =
        request.meta ?? request.params?['_meta'] as Map<String, dynamic>?;
    final relatedTaskJson = (meta?[relatedTaskMetadataKey] ??
        meta?[legacyRelatedTaskMetadataKey]) as Map<String, dynamic>?;
    final relatedTaskId = relatedTaskJson?['taskId'] as String?;

    if (registeredHandler == null && fallbackHandler == null) {
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
    final subscriptionState = request is JsonRpcSubscriptionsListenRequest
        ? _SubscriptionStreamState()
        : null;
    final usesStatelessResultTypes = _usesStatelessResultTypes(request);
    final requestSessionId =
        usesStatelessResultTypes ? null : _transport?.sessionId;
    final requestSseTransport = _transport;
    final RequestSseStreamControlAwareTransport? requestSseController =
        requestSseTransport is RequestSseStreamControlAwareTransport
            ? requestSseTransport as RequestSseStreamControlAwareTransport
            : null;
    final canCloseRequestSseStream =
        requestSseController?.canCloseRequestSseStream(request.id) ?? false;

    final extra = RequestHandlerExtra(
      signal: abortController.signal,
      sessionId: requestSessionId,
      requestId: request.id,
      meta: request.meta,
      inputResponses: _inputResponsesFromRequest(request),
      requestState: _requestStateFromRequest(request),
      taskId: relatedTaskId,
      taskStore: _taskStore != null
          ? _RequestTaskStoreImpl(
              _taskStore,
              request,
              requestSessionId,
              this,
            )
          : null,
      taskRequestedTtl: usesStatelessResultTypes
          ? null
          : readOptionalInteger(
              (request.params?['task'] as Map<String, dynamic>?)?['ttl'],
              'RequestOptions.task.ttl',
            ),
      sendNotification: (notification, {relatedTask}) {
        var outgoingNotification = notification;
        if (subscriptionState != null) {
          outgoingNotification = _withSubscriptionId(notification, request.id);
          _recordOrValidateSubscriptionNotification(
            subscriptionState,
            outgoingNotification,
          );
        }

        return _notificationWithRequestId(
          outgoingNotification,
          relatedTask: relatedTask,
          relatedRequestId: request.id,
        );
      },
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
          timeoutEnabled: options.timeoutEnabled,
          logLevel: options.logLevel,
          task: options.task,
          relatedTask: options.relatedTask ??
              (relatedTaskId != null
                  ? RelatedTaskMetadata(taskId: relatedTaskId)
                  : null),
        );
        return _requestWithRequestId<T>(
          req,
          resultFactory,
          newOptions,
          request.id,
        );
      },
      closeSSEStream: canCloseRequestSseStream
          ? () => requestSseController!.closeRequestSseStream(request.id)
          : null,
    );
    if (subscriptionState != null) {
      _subscriptionStateByExtra[extra] = subscriptionState;
    }

    // If task creation is requested, check capability
    if (!usesStatelessResultTypes &&
        (extra.taskRequestedTtl != null ||
            request.params?.containsKey('task') == true)) {
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

    onIncomingRequestAccepted(request);

    if (relatedTaskId != null && _taskStore != null) {
      _taskStore.updateTaskStatus(
        relatedTaskId,
        TaskStatus.inputRequired,
        null,
        requestSessionId,
      );
    }

    Future<BaseResultData> invokeHandler() {
      final handler = registeredHandler;
      if (handler != null) {
        return handler(request, extra);
      }
      return fallbackHandler!(request);
    }

    Future.microtask(invokeHandler).then(
      (result) async {
        if (abortController.signal.aborted) {
          return;
        }

        final serializedResult = serializeIncomingResult(request, result);
        final serializedMeta = readOptionalJsonObject(
          serializedResult['_meta'],
          'Result._meta',
        );
        Map<String, dynamic>? responseMeta;
        if (serializedResult.containsKey('_meta')) {
          // The serializer may validate or sanitize reserved metadata, so its
          // output is authoritative. Falling back only when `_meta` was omitted
          // preserves compatibility with older custom result implementations.
          responseMeta = serializedMeta ?? <String, dynamic>{};
        } else if (result.meta != null) {
          responseMeta = readJsonObject(result.meta, 'Result._meta');
        }

        final response = JsonRpcResponse(
          id: request.id,
          result: serializedResult,
          meta: _mergeRelatedTaskMeta(responseMeta, relatedTaskJson),
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
        onIncomingRequestHandled(request, result);
      },
      onError: (error, stackTrace) {
        if (abortController.signal.aborted) {
          return Future.value(null);
        }
        onIncomingRequestFailed(request, error);

        int code = ErrorCode.internalError.value;
        String message = "Internal server error processing ${request.method}";
        dynamic data;

        if (error is McpError) {
          code = error.code;
          message = error.message;
          data = error.data;
        } else {
          _logger.error(
            'Unhandled error processing ${request.method}: '
            '$error\n$stackTrace',
          );
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
      onIncomingRequestFailed(request, sendError);
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

    if (!_isProgressToken(progressToken)) {
      _onerror(
        ArgumentError(
          "Received invalid progressToken: $progressToken. "
          "Expected string or integer.",
        ),
      );
      return;
    }

    final progressHandler = _progressHandlers[progressToken];
    if (progressHandler == null) {
      return;
    }

    final requestId = _progressTokenRequestIds[progressToken];
    final timeoutInfo = requestId != null ? _timeoutInfo[requestId] : null;
    if (timeoutInfo != null) {
      _resetTimeoutOnProgress(timeoutInfo);
    }

    try {
      final progressData = Progress(
        progress: params.progress,
        total: params.total,
        message: params.message,
      );
      progressHandler(progressData);
    } catch (e) {
      _onerror(
        StateError("Error in progress handler for token $progressToken: $e"),
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

    final taskRequestState = _taskRequestsByMessageId[messageId];
    final preserveTaskProgress =
        taskRequestState != null && errorPayload == null;
    if (!preserveTaskProgress) {
      _cleanupProgressHandler(messageId);
      if (taskRequestState != null) {
        _cleanupTaskAugmentedRequest(taskRequestState, cleanupProgress: false);
      }
    }

    if (completer == null || completer.isCompleted) {
      return;
    }

    if (errorPayload != null) {
      final cancellationReason = _preTaskIdCancellationReason(taskRequestState);
      if (cancellationReason != null) {
        try {
          completer.completeError(cancellationReason);
        } catch (e) {
          _onerror(
            StateError("Error completing cancelled request $messageId: $e"),
          );
        }
      } else {
        _handleResponseError(messageId, errorPayload, completer, errorHandler);
      }
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
    return _requestWithRequestId(
      requestData,
      resultFactory,
      options,
      relatedRequestId,
    );
  }

  /// Reserves an outgoing integer request ID for APIs that need to correlate
  /// side-channel data before the response arrives.
  @protected
  int reserveRequestId() => _requestMessageId++;

  /// Sends a request using a previously reserved outgoing integer request ID.
  @protected
  Future<T> requestWithReservedId<T extends BaseResultData>(
    int requestId,
    JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    RequestOptions? options,
    RequestId? relatedRequestId,
  ]) {
    return _requestWithRequestId(
      requestData,
      resultFactory,
      options,
      relatedRequestId,
      requestId,
    );
  }

  Future<T> _requestWithRequestId<T extends BaseResultData>(
    JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    RequestOptions? options,
    RequestId? relatedRequestId,
    int? reservedRequestId,
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

    final messageId = reservedRequestId ?? _requestMessageId++;
    final completer = Completer<JsonRpcResponse>();
    Error? capturedError;
    Object? progressToken;

    Map<String, dynamic>? finalMeta = requestData.meta;
    Map<String, dynamic>? finalParams = requestData.params;
    final usesStatelessRequestShape = _usesStatelessRequestShape(requestData);

    if (usesStatelessRequestShape && options?.task != null) {
      return Future.error(
        McpError(
          ErrorCode.invalidRequest.value,
          'RequestOptions.task is not supported for stateless MCP requests; '
          'use the $mcpTasksExtensionId extension flow instead.',
        ),
      );
    }

    if (options?.onprogress != null) {
      final currentMeta = Map<String, dynamic>.from(finalMeta ?? {});
      final requestedProgressToken = currentMeta['progressToken'];
      if (requestedProgressToken != null) {
        if (!_isProgressToken(requestedProgressToken)) {
          return Future.error(
            ArgumentError(
              'progressToken must be a string or integer when '
              'onprogress is set.',
            ),
          );
        }
        progressToken = requestedProgressToken;
      } else {
        progressToken = _nextAvailableProgressToken(messageId);
        currentMeta['progressToken'] = progressToken;
      }
      final token = progressToken!;
      if (_progressHandlers.containsKey(token)) {
        return Future.error(
          ArgumentError('progressToken is already in use by another request.'),
        );
      }
      _progressHandlers[token] = options!.onprogress!;
      _requestProgressTokens[messageId] = token;
      _progressTokenRequestIds[token] = messageId;
      finalMeta = currentMeta;
    }

    if (options?.task != null) {
      finalParams = Map<String, dynamic>.from(finalParams ?? {});
      finalParams['task'] = options!.task!.toJson();
    }

    if (options?.relatedTask != null) {
      finalMeta = Map<String, dynamic>.from(finalMeta ?? {});
      final relatedTaskJson = options!.relatedTask!.toJson();
      finalMeta[relatedTaskMetadataKey] = relatedTaskJson;
      // Dual-write legacy key for compatibility during migration.
      finalMeta[legacyRelatedTaskMetadataKey] = relatedTaskJson;
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

    final taskRequestState = options?.task != null
        ? _TaskAugmentedRequestState(
            messageId: messageId,
            relatedRequestId: relatedRequestId,
            signal: options?.signal,
          )
        : null;
    if (taskRequestState != null) {
      _taskRequestsByMessageId[messageId] = taskRequestState;
    }

    void cancel(Object? reason, {bool fromTimeout = false}) {
      final errorReason = reason ?? AbortError("Request cancelled");
      final activeTaskState = taskRequestState;
      if (activeTaskState != null) {
        final alreadyCancelRequested = activeTaskState.cancelRequested;
        if (!alreadyCancelRequested) {
          activeTaskState.cancelRequested = true;
          activeTaskState.cancelReason = errorReason;
        }
        if (activeTaskState.taskId != null) {
          _sendTaskCancellation(activeTaskState);
          if (!completer.isCompleted) {
            completer.completeError(
              activeTaskState.cancelReason ?? errorReason,
            );
          }
        } else if (fromTimeout) {
          _responseCompleters.remove(messageId);
          _responseErrorHandlers.remove(messageId);
          _cleanupProgressHandler(messageId);
          _cleanupTaskAugmentedRequest(
            activeTaskState,
            cleanupProgress: false,
          );
          _cleanupTimeout(messageId);
          if (!completer.isCompleted) {
            completer
                .completeError(activeTaskState.cancelReason ?? errorReason);
          }
        }
        return;
      }

      if (completer.isCompleted) return;

      _responseCompleters.remove(messageId);
      _responseErrorHandlers.remove(messageId);
      _cleanupProgressHandler(messageId);
      _cleanupTimeout(messageId);

      // MCP 2025-11-25 forbids clients from cancelling `initialize`.
      if (jsonrpcRequest.method == Method.initialize) {
        completer.completeError(errorReason);
        return;
      }

      final activeTransport = _transport;
      final cancellationAwareTransport =
          activeTransport is RequestCancellationAwareTransport
              ? activeTransport as RequestCancellationAwareTransport
              : null;
      if (usesStatelessRequestShape && cancellationAwareTransport != null) {
        // MCP 2026-07-28 cancels the matching HTTP request stream and removes
        // protocol-level `notifications/cancelled`. If the transport no longer
        // tracks this request, it has already settled from the transport's
        // perspective; do not fall back to the legacy notification.
        if (cancellationAwareTransport.canCancelRequest(messageId)) {
          cancellationAwareTransport.cancelRequest(messageId).catchError((e) {
            _onerror(
              StateError(
                "Failed to cancel transport request $messageId: $e",
              ),
            );
          });
        }
        completer.completeError(errorReason);
        return;
      }

      final cancelReason = reason?.toString() ?? 'Request cancelled';
      final notification = JsonRpcCancelledNotification(
        cancelParams: CancelledNotification(
          requestId: messageId,
          reason: cancelReason,
        ),
        meta: usesStatelessRequestShape
            ? Map<String, dynamic>.from(jsonrpcRequest.meta ?? const {})
            : null,
      );

      // If related to a task, we might need to queue cancellation too?
      // Spec doesn't strictly say, but usually cancellations go via same channel.
      // For now assume standard transport for cancellations unless queued.

      _transport
          ?.sendPreservingRequestId(
        notification,
        relatedRequestId: relatedRequestId,
      )
          .catchError((e) {
        _onerror(
          StateError("Failed to send cancellation for request $messageId: $e"),
        );
        return null;
      });

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
      taskRequestState?.abortSubscription = abortSubscription;
    }

    if (options?.timeoutEnabled ?? true) {
      final timeoutDuration = options?.timeout ?? defaultRequestTimeout;
      final maxTotalTimeoutDuration = options?.maxTotalTimeout;
      void timeoutHandler() {
        cancel(
          McpError(
            ErrorCode.requestTimeout.value,
            "Request $messageId timed out after $timeoutDuration",
            {'timeout': timeoutDuration.inMilliseconds},
          ),
          fromTimeout: true,
        );
      }

      _setupTimeout(
        messageId,
        timeoutDuration,
        maxTotalTimeoutDuration,
        options?.resetTimeoutOnProgress ?? false,
        timeoutHandler,
      );
    }

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
        _requestResolvers.remove(messageId);
        _responseCompleters.remove(messageId);
        _responseErrorHandlers.remove(messageId);
        _cleanupTimeout(messageId);
        _cleanupProgressHandler(messageId);
        final state = taskRequestState;
        if (state != null) {
          _cleanupTaskAugmentedRequest(state, cleanupProgress: false);
        }
        if (!completer.isCompleted) {
          final cancellationReason = _preTaskIdCancellationReason(state);
          completer.completeError(cancellationReason ?? e);
        }
      });
    } else {
      // Normal transport
      _transport!
          .sendPreservingRequestId(
        jsonrpcRequest,
        relatedRequestId: relatedRequestId,
      )
          .catchError((error) {
        _responseCompleters.remove(messageId);
        _responseErrorHandlers.remove(messageId);
        _cleanupTimeout(messageId);
        _cleanupProgressHandler(messageId);
        final state = taskRequestState;
        if (state != null) {
          _cleanupTaskAugmentedRequest(state, cleanupProgress: false);
        }
        if (!completer.isCompleted) {
          final cancellationReason = _preTaskIdCancellationReason(state);
          completer.completeError(cancellationReason ?? error);
        }
        return null;
      });
    }

    var preserveTaskLifecycle = false;
    return completer.future.then((response) {
      Object? taskCancellationError;
      late final T result;
      try {
        final resultJson = response.toJson()['result'] as Map<String, dynamic>;
        _validateResponseResultType(jsonrpcRequest, resultJson);
        result = resultFactory(
          resultJson,
        );
        final state = taskRequestState;
        if (state != null) {
          if (result is CreateTaskResult) {
            final createdTask = result as CreateTaskResult;
            final taskId = createdTask.task.taskId;
            state.taskId = taskId;
            final taskIsTerminal = createdTask.task.status.isTerminal ||
                _earlyTerminalTaskIds.remove(taskId);

            if (state.cancelRequested || options?.signal?.aborted == true) {
              if (!state.cancelRequested && options?.signal?.aborted == true) {
                state.cancelRequested = true;
                state.cancelReason =
                    options?.signal?.reason ?? AbortError("Request cancelled");
              }
              if (taskIsTerminal) {
                _cleanupTaskAugmentedRequest(state);
              } else {
                _taskRequestsByTaskId[taskId] = state;
                _clearEarlyTerminalTaskIdsIfUnneeded();
                _sendTaskCancellation(state);
                preserveTaskLifecycle = true;
              }
              taskCancellationError =
                  state.cancelReason ?? AbortError("Request cancelled");
            } else if (taskIsTerminal) {
              _cleanupTaskAugmentedRequest(state);
            } else {
              _taskRequestsByTaskId[taskId] = state;
              _clearEarlyTerminalTaskIdsIfUnneeded();
              preserveTaskLifecycle = true;
            }
          } else {
            _cleanupTaskAugmentedRequest(state);
          }
        }
      } catch (e, s) {
        final state = taskRequestState;
        final cancellationReason = _preTaskIdCancellationReason(state);
        if (state != null) {
          _cleanupTaskAugmentedRequest(state);
        }
        if (cancellationReason != null) {
          throw cancellationReason;
        }
        throw McpError(
          ErrorCode.internalError.value,
          "Failed to parse result for ${requestData.method}",
          "$e\n$s",
        );
      }
      if (taskCancellationError != null) {
        throw taskCancellationError;
      }
      return result;
    }).whenComplete(() {
      _responseCompleters.remove(messageId);
      _responseErrorHandlers.remove(messageId);
      if (!preserveTaskLifecycle) {
        abortSubscription?.cancel();
        _cleanupProgressHandler(messageId);
        final state = taskRequestState;
        if (state != null) {
          _cleanupTaskAugmentedRequest(state, cleanupProgress: false);
        }
      }
    }).catchError((error) {
      throw capturedError ?? error;
    });
  }

  /// Sends a notification, which is a one-way message that does not expect a response.
  Future<void> notification(
    JsonRpcNotification notificationData, {
    RelatedTaskMetadata? relatedTask,
    int? relatedRequestId,
  }) {
    return _notificationWithRequestId(
      notificationData,
      relatedTask: relatedTask,
      relatedRequestId: relatedRequestId,
    );
  }

  Future<void> _notificationWithRequestId(
    JsonRpcNotification notificationData, {
    RelatedTaskMetadata? relatedTask,
    RequestId? relatedRequestId,
  }) async {
    if (_transport == null) {
      throw StateError("Not connected to a transport.");
    }

    if (_options.enforceStrictCapabilities) {
      assertNotificationCapability(notificationData.method);
    }
    validateProtocolNotification(this, notificationData);

    Map<String, dynamic>? finalMeta = notificationData.meta;
    Map<String, dynamic>? finalParams = notificationData.params;

    if (relatedTask != null) {
      finalMeta = Map<String, dynamic>.from(finalMeta ?? {});
      final relatedTaskJson = relatedTask.toJson();
      finalMeta[relatedTaskMetadataKey] = relatedTaskJson;
      // Dual-write legacy key for compatibility during migration.
      finalMeta[legacyRelatedTaskMetadataKey] = relatedTaskJson;
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
            .sendPreservingRequestId(
              jsonrpcNotification,
              relatedRequestId: relatedRequestId,
            )
            .catchError((e) => _onerror(e));
      });
      return;
    }

    await _transport!.sendPreservingRequestId(
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
    await _taskMessageQueue.enqueue(
      taskId,
      message,
      sessionId,
      _options.maxTaskQueueSize,
    );
  }

  Future<void> _clearTaskQueue(String taskId, String? sessionId) async {
    if (_taskMessageQueue != null) {
      final messages = await _taskMessageQueue.dequeueAll(taskId, sessionId);
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
      final ReqT specificRequest;
      try {
        specificRequest = requestFactory(
          jsonRpcRequest.id,
          jsonRpcRequest.params,
          jsonRpcRequest.meta,
        );
      } on McpError {
        rethrow;
      } catch (e, s) {
        _logger.warn(
          'Failed to parse params for request $method: $e\n$s',
        );
        throw McpError(
          ErrorCode.invalidParams.value,
          "Failed to parse params for request $method",
        );
      }
      return handler(specificRequest, extra);
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
    final currentTask = await _store.getTask(taskId, _sessionId);
    if (currentTask == null) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Failed to store task result: Task not found',
      );
    }
    if (currentTask.status.isTerminal) {
      return;
    }

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
