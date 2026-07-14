import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// A class to represent a notification message
class NotificationMessage {
  final int count;
  final String level;
  final String message;
  final DateTime timestamp;

  NotificationMessage({
    required this.count,
    required this.level,
    required this.message,
    required this.timestamp,
  });

  String get formattedTimestamp =>
      '${timestamp.hour}:${timestamp.minute}:${timestamp.second}';
}

/// MCP Client Service with StreamableHttpClientTransport
class StreamableMcpService extends ChangeNotifier {
  // MCP client properties
  McpClient? _client;
  StreamableHttpClientTransport? _transport;
  String serverUrl;
  String? _sessionId;
  int _notificationCount = 0;
  bool _isConnected = false;
  bool _disposed = false;

  // Status state
  bool get isConnected => _isConnected;
  String? get negotiatedProtocolVersion => _client?.getProtocolVersion();
  bool get canTerminateSession {
    final protocolVersion = negotiatedProtocolVersion;
    return _transport?.sessionId != null &&
        (protocolVersion == null ||
            !isStatelessProtocolVersion(protocolVersion));
  }

  String? _connectionError;
  String? get connectionError => _connectionError;

  // Store notifications for UI display
  final List<NotificationMessage> notifications = [];

  // Tools and resources from the server
  List<Tool>? _availableTools;
  List<Tool>? get availableTools => _availableTools;

  List<Resource>? _availableResources;
  List<Resource>? get availableResources => _availableResources;

  List<Prompt>? _availablePrompts;
  List<Prompt>? get availablePrompts => _availablePrompts;

  /// Constructor
  StreamableMcpService({required this.serverUrl});

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  void _addNotification({
    required String level,
    required String message,
    bool notify = true,
  }) {
    if (_disposed) {
      return;
    }
    _notificationCount++;
    notifications.add(
      NotificationMessage(
        count: _notificationCount,
        level: level,
        message: message,
        timestamp: DateTime.now(),
      ),
    );
    if (notify) {
      notifyListeners();
    }
  }

  /// Update server URL
  bool updateServerUrl(String newUrl) {
    // Only update if not connected
    if (_client != null) {
      _connectionError =
          'Cannot change server URL while connected. Disconnect first.';
      notifyListeners();
      return false;
    }

    final uri = Uri.tryParse(newUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      _connectionError = 'Enter an absolute HTTP or HTTPS server URL.';
      notifyListeners();
      return false;
    }

    serverUrl = uri.toString();
    _connectionError = null;
    notifyListeners();
    return true;
  }

  /// Connect to server
  Future<bool> connect() async {
    if (_client != null) {
      _connectionError = 'Already connected. Disconnect first.';
      notifyListeners();
      return false;
    }

    try {
      // Create a new client
      _client = McpClient(
        const Implementation(name: 'flutter-mcp-client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.stable),
      );

      _client!.onerror = (error) {
        if (_disposed) return;
        _connectionError = 'Client error: $error';
        notifyListeners();
      };

      // Create the transport with a sessionId if we have one
      _transport = StreamableHttpClientTransport(
        Uri.parse(serverUrl),
        opts: StreamableHttpClientTransportOptions(sessionId: _sessionId),
      );

      // Set up transport error handler
      _transport!.onerror = (error) {
        if (_disposed) return;
        _connectionError = 'Transport error: $error';
        notifyListeners();
      };

      // These global handlers support initialization-era fallback peers. MCP
      // 2026 uses request-scoped progress and subscriptions/listen instead.
      _client!.setNotificationHandler(
        "notifications/message",
        (notification) async {
          try {
            final params = notification.logParams;
            _addNotification(
              level: params.level.toString(),
              message: params.data,
              notify: false,
            );

            // Schedule UI update
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_disposed) {
                notifyListeners();
              }
            });
          } catch (error) {
            // Add an error notification to make the error more visible
            _addNotification(
              level: 'error',
              message: 'Error processing notification: $error',
            );
            _connectionError = 'Error processing notification: $error';
          }
          return Future.value();
        },
        (params, meta) {
          if (params == null) {
            throw const FormatException(
              'Missing params for logging message notification',
            );
          }

          return JsonRpcLoggingMessageNotification(
            logParams: LoggingMessageNotification.fromJson(params),
            meta: meta,
          );
        },
      );

      _client!.setNotificationHandler(
        "notifications/resources/list_changed",
        (notification) async {
          _addNotification(
            level: 'info',
            message: 'Resource list changed notification received',
            notify: false,
          );

          // Refresh resources when list changes
          try {
            if (_client == null) return Future.value();
            await listResources();
          } catch (error) {
            // Handle error silently
          }

          notifyListeners();
          return Future.value();
        },
        (params, meta) => JsonRpcResourceListChangedNotification.fromJson({
          'jsonrpc': jsonRpcVersion,
          'method': Method.notificationsResourcesListChanged,
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );

      // Connect the client
      try {
        await _client!
            .connect(_transport!)
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw TimeoutException(
                  'Connection timed out after 15 seconds. Server may be overloaded or unreachable.',
                );
              },
            );
        _isConnected = true;
        _sessionId = _transport!.sessionId;
        _connectionError = null;

        // Add an initial notification
        _addNotification(
          level: 'info',
          message: 'Connected to server',
          notify: false,
        );
      } catch (e) {
        rethrow;
      }

      notifyListeners();
      return true;
    } catch (error) {
      String errorMessage = 'Failed to connect: $error';
      // Add more specific error messages for network issues
      if (error.toString().contains('SocketException') ||
          error.toString().contains('Connection refused')) {
        errorMessage +=
            '\n\nCheck that the server is running and the URL is correct. '
            'If you\'re using a physical device, make sure to use the actual IP address instead of localhost.';
      }
      _connectionError = errorMessage;
      _isConnected = false;
      final failedTransport = _transport;
      _client = null;
      _transport = null;
      try {
        await failedTransport?.close();
      } catch (_) {
        // Connection failures may already have closed the transport.
      }
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    if (_client == null || _transport == null) {
      _connectionError = 'Not connected.';
      notifyListeners();
      return;
    }

    try {
      // First try to gracefully close the transport
      await _transport!.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          // If timeout, force cleanup
          throw TimeoutException('Disconnect operation timed out');
        },
      );
    } catch (error) {
      // Log the error but continue with cleanup
      _connectionError =
          'Warning during disconnect: $error - Cleaning up anyway';
    } finally {
      // Always clean up client and transport regardless of errors
      _isConnected = false;
      _client = null;
      _transport = null;
      _availableTools = null;
      _availableResources = null;
      _availablePrompts = null;
      _connectionError = null;
      notifyListeners();
    }
  }

  /// Terminate the stateful session and disconnect the local client.
  Future<bool> terminateSession() async {
    final transport = _transport;
    if (_client == null || transport == null || !canTerminateSession) {
      _connectionError = 'No stateful session is available to terminate.';
      notifyListeners();
      return false;
    }

    _connectionError = null;
    Object? terminationError;
    try {
      await transport.terminateSession();
    } catch (error) {
      terminationError = error;
      _connectionError = 'Error terminating session: $error';
    } finally {
      try {
        await transport.close();
      } catch (error) {
        terminationError ??= error;
        _connectionError ??= 'Error closing terminated session: $error';
      }
      _isConnected = false;
      _client = null;
      _transport = null;
      _sessionId = null;
      _availableTools = null;
      _availableResources = null;
      _availablePrompts = null;
    }

    notifyListeners();
    return terminationError == null;
  }

  /// Reconnect to server
  Future<bool> reconnect() async {
    // First try a clean disconnect
    try {
      await disconnect();
    } catch (error) {
      // Ignore errors during disconnect, we're trying to reconnect anyway
      _connectionError = null;
    }

    // Progressive retry with increased timeouts
    bool connected = false;
    int attempt = 1;
    const maxAttempts = 3;

    while (!connected && attempt <= maxAttempts) {
      try {
        _addNotification(
          level: 'info',
          message: 'Reconnection attempt $attempt of $maxAttempts...',
        );

        // Wait longer between retry attempts
        if (attempt > 1) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }

        connected = await connect();

        if (connected) {
          _addNotification(
            level: 'info',
            message: 'Reconnection successful on attempt $attempt',
          );
        }
      } catch (error) {
        // Add a notification about the failed attempt
        _addNotification(
          level: 'error',
          message: 'Reconnection attempt $attempt failed: $error',
        );
      }

      attempt++;
    }

    return connected;
  }

  /// List available tools from the server
  Future<void> listTools() async {
    if (_client == null) {
      _connectionError = 'Not connected to server.';
      notifyListeners();
      return;
    }

    try {
      final toolsResult = await _client!.listTools();
      _availableTools = toolsResult.tools;
      notifyListeners();
    } catch (error) {
      _connectionError = 'Tools not supported by this server ($error)';
      notifyListeners();
    }
  }

  /// Call a tool on the server
  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    if (_client == null) {
      throw Exception('Not connected to server.');
    }

    final params = CallToolRequest(name: name, arguments: args);

    return await _client!.callTool(
      params,
      options: RequestOptions(
        onprogress: (progress) {
          final position =
              progress.total == null
                  ? '${progress.progress}'
                  : '${progress.progress}/${progress.total}';
          final detail =
              progress.message == null
                  ? position
                  : '${progress.message} ($position)';
          _addNotification(level: 'progress', message: '$name: $detail');
        },
        timeout: const Duration(seconds: 30),
        resetTimeoutOnProgress: true,
      ),
    );
  }

  /// List available prompts from the server
  Future<void> listPrompts() async {
    if (_client == null) {
      _connectionError = 'Not connected to server.';
      notifyListeners();
      return;
    }

    try {
      final promptsResult = await _client!.listPrompts();
      _availablePrompts = promptsResult.prompts;
      notifyListeners();
    } catch (error) {
      _connectionError = 'Prompts not supported by this server ($error)';
      notifyListeners();
    }
  }

  /// Get a prompt from the server
  Future<dynamic> getPrompt(String name, Map<String, dynamic> args) async {
    if (_client == null) {
      throw Exception('Not connected to server.');
    }

    final params = GetPromptRequest(
      name: name,
      arguments: Map<String, String>.from(
        args.map((key, value) => MapEntry(key, value.toString())),
      ),
    );

    return await _client!.getPrompt(params);
  }

  /// List resources from the server
  Future<void> listResources() async {
    if (_client == null) {
      _connectionError = 'Not connected to server.';
      notifyListeners();
      return;
    }

    try {
      final resourcesResult = await _client!.listResources();
      _availableResources = resourcesResult.resources;
      notifyListeners();
    } catch (error) {
      _connectionError = 'Resources not supported by this server ($error)';
      notifyListeners();
    }
  }

  /// Public method to refresh the UI
  void refresh() {
    notifyListeners();
  }

  /// Clears displayed notifications and resets their sequence numbers.
  void clearNotifications() {
    notifications.clear();
    _notificationCount = 0;
    notifyListeners();
  }

  /// Clean up resources
  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final client = _client;
    final transport = _transport;
    client?.onerror = null;
    transport?.onerror = null;
    _isConnected = false;
    _client = null;
    _transport = null;
    if (transport != null) {
      unawaited(_disposeTransport(transport));
    }
    super.dispose();
  }

  Future<void> _disposeTransport(
    StreamableHttpClientTransport transport,
  ) async {
    if (transport.sessionId != null) {
      try {
        await transport.terminateSession();
      } catch (_) {
        // Ignore termination errors during cleanup.
      }
    }
    try {
      await transport.close();
    } catch (_) {
      // Ignore close errors during cleanup.
    }
  }

  /// Reset the service state without disconnecting
  void resetState() {
    notifications.clear();
    _notificationCount = 0;
    _connectionError = null;
    notifyListeners();
  }
}
