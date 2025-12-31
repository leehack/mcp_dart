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

  // Status state
  bool get isConnected => _client != null;
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

  /// Update server URL
  void updateServerUrl(String newUrl) {
    // Only update if not connected
    if (_client != null) {
      _connectionError =
          'Cannot change server URL while connected. Disconnect first.';
      notifyListeners();
      return;
    }

    serverUrl = newUrl;
    notifyListeners();
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
        Implementation(name: 'flutter-mcp-client', version: '1.0.0'),
      );

      _client!.onerror = (error) {
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
        _connectionError = 'Transport error: $error';
        notifyListeners();
      };

      // Set up notification handlers
      _client!.setNotificationHandler(
        "notifications/message",
        (notification) async {
          try {
            _notificationCount++;
            final params = notification.logParams;

            // Add notification to our list
            final message = NotificationMessage(
              count: _notificationCount,
              level: params.level.toString(),
              message: params.data,
              timestamp: DateTime.now(),
            );

            notifications.add(message);

            // Schedule UI update
            WidgetsBinding.instance.addPostFrameCallback((_) {
              notifyListeners();
            });
          } catch (error) {
            // Add an error notification to make the error more visible
            notifications.add(
              NotificationMessage(
                count: _notificationCount + 1,
                level: 'error',
                message: 'Error processing notification: $error',
                timestamp: DateTime.now(),
              ),
            );
            _notificationCount++;
            _connectionError = 'Error processing notification: $error';
            notifyListeners();
          }
          return Future.value();
        },
        (params, meta) => JsonRpcLoggingMessageNotification.fromJson({
          'params': params,
          if (meta != null) '_meta': meta,
        }),
      );

      _client!.setNotificationHandler(
        "notifications/resources/list_changed",
        (notification) async {
          notifications.add(
            NotificationMessage(
              count: _notificationCount + 1,
              level: 'info',
              message: 'Resource list changed notification received',
              timestamp: DateTime.now(),
            ),
          );
          _notificationCount++;

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
        _sessionId = _transport!.sessionId;
        _connectionError = null;

        // Add an initial notification
        notifications.add(
          NotificationMessage(
            count: _notificationCount++,
            level: 'info',
            message: 'Connected to server',
            timestamp: DateTime.now(),
          ),
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
      _client = null;
      _transport = null;
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
      _client = null;
      _transport = null;
      _connectionError = null;
      notifyListeners();
    }
  }

  /// Terminate the session but keep the client/transport objects
  Future<void> terminateSession() async {
    if (_client == null || _transport == null) {
      _connectionError = 'Not connected.';
      notifyListeners();
      return;
    }

    try {
      await _transport!.terminateSession();
      if (_transport!.sessionId == null) {
        _sessionId = null;
      }
      notifyListeners();
    } catch (error) {
      _connectionError = 'Error terminating session: $error';
      notifyListeners();
    }
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
        notifications.add(
          NotificationMessage(
            count: _notificationCount++,
            level: 'info',
            message: 'Reconnection attempt $attempt of $maxAttempts...',
            timestamp: DateTime.now(),
          ),
        );
        notifyListeners();

        // Wait longer between retry attempts
        if (attempt > 1) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }

        connected = await connect();

        if (connected) {
          notifications.add(
            NotificationMessage(
              count: _notificationCount++,
              level: 'info',
              message: 'Reconnection successful on attempt $attempt',
              timestamp: DateTime.now(),
            ),
          );
          notifyListeners();
        }
      } catch (error) {
        // Add a notification about the failed attempt
        notifications.add(
          NotificationMessage(
            count: _notificationCount++,
            level: 'error',
            message: 'Reconnection attempt $attempt failed: $error',
            timestamp: DateTime.now(),
          ),
        );
        notifyListeners();
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

  /// Clean up resources
  @override
  void dispose() {
    if (_client != null && _transport != null) {
      try {
        // First try to terminate the session gracefully if requested
        if (_transport!.sessionId != null) {
          try {
            _transport!.terminateSession();
          } catch (_) {
            // Ignore termination errors during cleanup
          }
        }

        // Then close the transport
        _transport!.close();
      } catch (_) {
        // Ignore errors during cleanup
      }
    }
    super.dispose();
  }

  /// Reset the service state without disconnecting
  void resetState() {
    notifications.clear();
    _notificationCount = 0;
    _connectionError = null;
    notifyListeners();
  }
}
