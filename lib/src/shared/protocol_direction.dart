import 'package:mcp_dart/src/types.dart';

/// Known MCP notification methods that a stateless client must not send.
///
/// MCP 2026-07-28 Core defines only `notifications/cancelled` as a client
/// notification, and only for stdio cancellation. Unknown methods are omitted
/// deliberately so negotiated extensions can define additional client
/// notifications without being blocked by the core SDK.
const Set<String> statelessForbiddenClientNotificationMethods = {
  Method.notificationsInitialized,
  Method.notificationsProgress,
  Method.notificationsResourcesListChanged,
  Method.notificationsResourcesUpdated,
  Method.notificationsSubscriptionsAcknowledged,
  Method.notificationsPromptsListChanged,
  Method.notificationsToolsListChanged,
  Method.notificationsMessage,
  Method.notificationsRootsListChanged,
  Method.notificationsTasksStatus,
  Method.notificationsTasks,
  Method.notificationsElicitationComplete,
};

/// Whether [method] is a known server-to-client or removed legacy
/// notification and therefore has the wrong direction for a stateless client.
bool isStatelessForbiddenClientNotification(String method) =>
    statelessForbiddenClientNotificationMethods.contains(method);
