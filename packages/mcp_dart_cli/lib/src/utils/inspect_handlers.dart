import 'dart:async';

import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;

/// Manages client-side handlers for server notifications and requests.
class InspectHandlers {
  final Logger _logger;

  /// Callback invoked when tools list changes.
  void Function()? onToolsListChanged;

  /// Callback invoked when resources list changes.
  void Function()? onResourcesListChanged;

  /// Callback invoked when prompts list changes.
  void Function()? onPromptsListChanged;

  InspectHandlers(this._logger);

  /// Registers all handlers with the given client.
  void registerHandlers(Client client) {
    // Register sampling request handler
    client.onSamplingRequest = _handleSamplingRequest;

    // Register notification handlers using fallback
    client.fallbackNotificationHandler = _handleNotification;
  }

  /// Handles sampling/createMessage requests from the server.
  Future<CreateMessageResult> _handleSamplingRequest(
      CreateMessageRequestParams params) async {
    _logger.info('\n[Sampling Request]');
    _logger.info('System Prompt: ${params.systemPrompt ?? "(none)"}');
    _logger.info('Messages:');
    for (final msg in params.messages) {
      _logger.info('  ${msg.role}: ${msg.content}');
    }

    _logger.info(
        '\n(Interactive sampling not supported yet. Returning placeholder response.)');

    return CreateMessageResult(
      role: SamplingMessageRole.assistant,
      content: const SamplingTextContent(
        text:
            'Sampling is supported by the CLI, but manual input is not yet implemented. '
            'This is a placeholder response.',
      ),
      model: 'mcp-dart-cli-placeholder',
    );
  }

  /// Fallback handler for notifications not handled by specific handlers.
  Future<void> _handleNotification(JsonRpcNotification notification) async {
    final method = notification.method;

    switch (method) {
      case 'notifications/message':
        _handleLoggingNotification(notification);
        break;
      case 'notifications/progress':
        _handleProgressNotification(notification);
        break;
      case 'notifications/tools/list_changed':
        _handleToolsListChanged();
        break;
      case 'notifications/resources/list_changed':
        _handleResourcesListChanged();
        break;
      case 'notifications/prompts/list_changed':
        _handlePromptsListChanged();
        break;
      default:
        _logger.detail('[Notification] $method');
    }
  }

  /// Handles logging message notifications from the server.
  void _handleLoggingNotification(JsonRpcNotification notification) {
    final params = notification.params;
    if (params == null) return;

    final level = params['level'] as String? ?? 'info';
    final loggerName = params['logger'] as String?;
    final data = params['data'];

    final prefix = loggerName != null ? '[$loggerName] ' : '';

    switch (level) {
      case 'debug':
        _logger.detail('${prefix}DEBUG: $data');
        break;
      case 'info':
        _logger.info('${prefix}INFO: $data');
        break;
      case 'notice':
        _logger.info('${prefix}NOTICE: $data');
        break;
      case 'warning':
        _logger.warn('${prefix}WARNING: $data');
        break;
      case 'error':
      case 'critical':
      case 'alert':
      case 'emergency':
        _logger.err('$prefix${level.toUpperCase()}: $data');
        break;
      default:
        _logger.info('$prefix$level: $data');
    }
  }

  /// Handles progress notifications from the server.
  void _handleProgressNotification(JsonRpcNotification notification) {
    final params = notification.params;
    if (params == null) return;

    final progress = params['progress'];
    final total = params['total'];
    final progressToken = params['progressToken'];

    if (total != null) {
      _logger.detail('[Progress $progressToken] $progress / $total');
    } else {
      _logger.detail('[Progress $progressToken] $progress');
    }
  }

  /// Handles tools list changed notification.
  void _handleToolsListChanged() {
    _logger.info('[Server] Tools list changed');
    onToolsListChanged?.call();
  }

  /// Handles resources list changed notification.
  void _handleResourcesListChanged() {
    _logger.info('[Server] Resources list changed');
    onResourcesListChanged?.call();
  }

  /// Handles prompts list changed notification.
  void _handlePromptsListChanged() {
    _logger.info('[Server] Prompts list changed');
    onPromptsListChanged?.call();
  }
}
