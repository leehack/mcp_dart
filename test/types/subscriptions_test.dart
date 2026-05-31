import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('SubscriptionFilter', () {
    test('serializes and parses requested notification filters', () {
      const filter = SubscriptionFilter(
        toolsListChanged: true,
        promptsListChanged: false,
        resourceSubscriptions: ['file:///project/config.json'],
      );

      final json = filter.toJson();
      expect(json['toolsListChanged'], isTrue);
      expect(json['promptsListChanged'], isFalse);
      expect(json['resourceSubscriptions'], ['file:///project/config.json']);
      expect(json.containsKey('resourcesListChanged'), isFalse);

      final parsed = SubscriptionFilter.fromJson(json);
      expect(parsed.toolsListChanged, isTrue);
      expect(parsed.promptsListChanged, isFalse);
      expect(parsed.resourceSubscriptions, ['file:///project/config.json']);
    });

    test('acknowledgedBy returns only supported requested filters', () {
      const requested = SubscriptionFilter(
        toolsListChanged: true,
        promptsListChanged: true,
        resourcesListChanged: true,
        resourceSubscriptions: ['file:///project/config.json'],
      );
      const capabilities = ServerCapabilities(
        tools: ServerCapabilitiesTools(listChanged: true),
        resources: ServerCapabilitiesResources(),
      );

      final acknowledged = requested.acknowledgedBy(capabilities);
      expect(acknowledged.toJson(), {
        'toolsListChanged': true,
        'resourceSubscriptions': ['file:///project/config.json'],
      });
    });

    test('rejects malformed filters', () {
      expect(
        () => SubscriptionFilter.fromJson(
          const {'toolsListChanged': 'yes'},
        ),
        throwsFormatException,
      );
      expect(
        () => SubscriptionFilter.fromJson(
          const {
            'resourceSubscriptions': [1],
          },
        ),
        throwsFormatException,
      );
    });
  });

  group('JsonRpcSubscriptionsListenRequest', () {
    test('serializes and parses subscriptions/listen requests', () {
      final request = JsonRpcSubscriptionsListenRequest(
        id: 'sub-1',
        listenParams: const SubscriptionsListenRequest(
          notifications: SubscriptionFilter(
            toolsListChanged: true,
            resourceSubscriptions: ['file:///project/config.json'],
          ),
        ),
        meta: const {
          McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28,
        },
      );

      final json = request.toJson();
      expect(json['method'], Method.subscriptionsListen);
      expect(json['params']['notifications']['toolsListChanged'], isTrue);
      expect(
        json['params']['_meta'][McpMetaKey.protocolVersion],
        draftProtocolVersion2026_07_28,
      );

      final parsed = JsonRpcMessage.fromJson(json);
      expect(parsed, isA<JsonRpcSubscriptionsListenRequest>());
      final listen = parsed as JsonRpcSubscriptionsListenRequest;
      expect(listen.id, 'sub-1');
      expect(listen.listenParams.notifications.toolsListChanged, isTrue);
      expect(
        listen.meta?[McpMetaKey.protocolVersion],
        draftProtocolVersion2026_07_28,
      );
    });

    test('rejects missing notifications', () {
      expect(
        () => JsonRpcSubscriptionsListenRequest.fromJson(
          const {
            'id': 1,
            'method': Method.subscriptionsListen,
            'params': <String, dynamic>{},
          },
        ),
        throwsFormatException,
      );
    });
  });

  group('JsonRpcSubscriptionsAcknowledgedNotification', () {
    test('serializes and parses subscription acknowledgments', () {
      final notification = JsonRpcSubscriptionsAcknowledgedNotification(
        acknowledgedParams: const SubscriptionsAcknowledgedNotification(
          notifications: SubscriptionFilter(toolsListChanged: true),
        ),
        meta: const {McpMetaKey.subscriptionId: 'sub-1'},
      );

      final json = notification.toJson();
      expect(json['method'], Method.notificationsSubscriptionsAcknowledged);
      expect(json['params']['notifications']['toolsListChanged'], isTrue);
      expect(json['params']['_meta'][McpMetaKey.subscriptionId], 'sub-1');

      final parsed = JsonRpcMessage.fromJson(json);
      expect(parsed, isA<JsonRpcSubscriptionsAcknowledgedNotification>());
      final acknowledged =
          parsed as JsonRpcSubscriptionsAcknowledgedNotification;
      expect(
        acknowledged.acknowledgedParams.notifications.toolsListChanged,
        isTrue,
      );
      expect(acknowledged.meta?[McpMetaKey.subscriptionId], 'sub-1');
    });

    test('rejects malformed acknowledgments', () {
      expect(
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson(
          const {'method': Method.notificationsSubscriptionsAcknowledged},
        ),
        throwsFormatException,
      );
      expect(
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson(
          const {
            'method': Method.notificationsSubscriptionsAcknowledged,
            'params': {
              'notifications': {'toolsListChanged': true},
              '_meta': false,
            },
          },
        ),
        throwsFormatException,
      );
    });
  });
}
