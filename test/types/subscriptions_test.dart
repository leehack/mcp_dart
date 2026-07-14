import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

Future<T> _unusedRequest<T extends BaseResultData>(
  JsonRpcRequest request,
  T Function(Map<String, dynamic> resultJson) resultFactory,
  RequestOptions options,
) {
  throw StateError('Unexpected request from subscription helper test');
}

RequestHandlerExtra _subscriptionExtra(List<JsonRpcNotification> sent) {
  final abort = BasicAbortController();
  return RequestHandlerExtra(
    signal: abort.signal,
    requestId: 'sub-1',
    sendNotification: (notification, {relatedTask}) async {
      sent.add(notification);
    },
    sendRequest: _unusedRequest,
  );
}

void main() {
  group('SubscriptionFilter', () {
    test('serializes and parses requested notification filters', () {
      const filter = SubscriptionFilter(
        toolsListChanged: true,
        promptsListChanged: false,
        resourceSubscriptions: ['file:///project/config.json'],
        taskIds: ['task-1'],
      );

      final json = filter.toJson();
      expect(json['toolsListChanged'], isTrue);
      expect(json['promptsListChanged'], isFalse);
      expect(json['resourceSubscriptions'], ['file:///project/config.json']);
      expect(json['taskIds'], ['task-1']);
      expect(json.containsKey('resourcesListChanged'), isFalse);

      final parsed = SubscriptionFilter.fromJson(json);
      expect(parsed.toolsListChanged, isTrue);
      expect(parsed.promptsListChanged, isFalse);
      expect(parsed.resourceSubscriptions, ['file:///project/config.json']);
      expect(parsed.taskIds, ['task-1']);
    });

    test('acknowledgedBy returns only supported requested filters', () {
      const requested = SubscriptionFilter(
        toolsListChanged: true,
        promptsListChanged: true,
        resourcesListChanged: true,
        resourceSubscriptions: ['file:///project/config.json'],
        taskIds: ['task-1'],
      );
      const capabilities = ServerCapabilities(
        extensions: {mcpTasksExtensionId: {}},
        tools: ServerCapabilitiesTools(listChanged: true),
        resources: ServerCapabilitiesResources(subscribe: true),
      );

      final acknowledged = requested.acknowledgedBy(capabilities);
      expect(acknowledged.toJson(), {
        'toolsListChanged': true,
        'resourceSubscriptions': ['file:///project/config.json'],
        'taskIds': ['task-1'],
      });

      final withoutResourceSubscribe = requested.acknowledgedBy(
        const ServerCapabilities(
          extensions: {mcpTasksExtensionId: {}},
          tools: ServerCapabilitiesTools(listChanged: true),
          resources: ServerCapabilitiesResources(),
        ),
      );
      expect(withoutResourceSubscribe.toJson(), {
        'toolsListChanged': true,
        'taskIds': ['task-1'],
      });
    });

    test('acknowledgedBy omits task filters without task extension support',
        () {
      const requested = SubscriptionFilter(taskIds: ['task-1']);

      final acknowledged = requested.acknowledgedBy(const ServerCapabilities());
      expect(acknowledged.toJson(), isEmpty);
    });

    test('checks acknowledged subsets and allowed notifications', () {
      const requested = SubscriptionFilter(
        toolsListChanged: true,
        resourceSubscriptions: [
          'file:///project/config.json',
          'file:///project/other.json',
        ],
      );
      const acknowledged = SubscriptionFilter(
        toolsListChanged: true,
        resourceSubscriptions: ['file:///project/config.json'],
      );

      expect(acknowledged.isSubsetOf(requested), isTrue);
      expect(
        const SubscriptionFilter(promptsListChanged: true).isSubsetOf(
          requested,
        ),
        isFalse,
      );
      expect(
        const SubscriptionFilter(resourcesListChanged: true).isSubsetOf(
          requested,
        ),
        isFalse,
      );
      expect(
        const SubscriptionFilter(
          resourceSubscriptions: ['file:///project/missing.json'],
        ).isSubsetOf(requested),
        isFalse,
      );

      expect(
        acknowledged.allowsNotification(
          const JsonRpcToolListChangedNotification(),
        ),
        isTrue,
      );
      expect(
        acknowledged.allowsNotification(
          JsonRpcResourceUpdatedNotification(
            updatedParams: const ResourceUpdatedNotification(
              uri: 'file:///project/config.json',
            ),
          ),
        ),
        isTrue,
      );
      expect(
        const SubscriptionFilter(
          resourceSubscriptions: ['file:///project'],
        ).allowsNotification(
          JsonRpcResourceUpdatedNotification(
            updatedParams: const ResourceUpdatedNotification(
              uri: 'file:///project/config.json',
            ),
          ),
        ),
        isTrue,
      );
      expect(
        const SubscriptionFilter(
          resourceSubscriptions: ['file:///project'],
        ).allowsNotification(
          JsonRpcResourceUpdatedNotification(
            updatedParams: const ResourceUpdatedNotification(
              uri: 'file:///project-other/config.json',
            ),
          ),
        ),
        isFalse,
      );
      expect(
        acknowledged.allowsNotification(
          JsonRpcResourceUpdatedNotification(
            updatedParams: const ResourceUpdatedNotification(
              uri: 'file:///project/missing.json',
            ),
          ),
        ),
        isFalse,
      );
      expect(
        acknowledged.allowsNotification(
          const JsonRpcPromptListChangedNotification(),
        ),
        isFalse,
      );
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
      expect(
        () => SubscriptionFilter.fromJson(
          const {
            'taskIds': [1],
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
          McpMetaKey.protocolVersion: previewProtocolVersion,
        },
      );

      final json = request.toJson();
      expect(json['method'], Method.subscriptionsListen);
      expect(json['params']['notifications']['toolsListChanged'], isTrue);
      expect(
        json['params']['_meta'][McpMetaKey.protocolVersion],
        previewProtocolVersion,
      );

      final parsed = JsonRpcMessage.fromJson(json);
      expect(parsed, isA<JsonRpcSubscriptionsListenRequest>());
      final listen = parsed as JsonRpcSubscriptionsListenRequest;
      expect(listen.id, 'sub-1');
      expect(listen.listenParams.notifications.toolsListChanged, isTrue);
      expect(
        listen.meta?[McpMetaKey.protocolVersion],
        previewProtocolVersion,
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

    test('rejects malformed listen wire fields', () {
      for (final parse in <Object Function()>[
        () => JsonRpcSubscriptionsListenRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.subscriptionsListen,
              'params': 'bad',
            }),
        () => JsonRpcSubscriptionsListenRequest.fromJson({
              'jsonrpc': jsonRpcVersion,
              'id': 1,
              'method': Method.subscriptionsListen,
              'params': null,
            }),
        () => SubscriptionsListenRequest.fromJson({
              'notifications': 'bad',
            }),
        () => SubscriptionsListenRequest.fromJson({
              'notifications': <Object?, Object?>{
                1: true,
              },
            }),
      ]) {
        expect(parse, throwsFormatException);
      }
    });
  });

  group('JsonRpcSubscriptionsAcknowledgedNotification', () {
    test('preserves subscription metadata on list changed notifications', () {
      for (final notification in [
        const JsonRpcToolListChangedNotification(
          meta: {McpMetaKey.subscriptionId: 'sub-1'},
        ),
        const JsonRpcPromptListChangedNotification(
          meta: {McpMetaKey.subscriptionId: 'sub-1'},
        ),
        const JsonRpcResourceListChangedNotification(
          meta: {McpMetaKey.subscriptionId: 'sub-1'},
        ),
        // ignore: deprecated_member_use_from_same_package, deprecated_member_use
        const JsonRpcCompletionListChangedNotification(
          meta: {McpMetaKey.subscriptionId: 'sub-1'},
        ),
      ]) {
        final parsed = JsonRpcMessage.fromJson(notification.toJson())
            as JsonRpcNotification;

        expect(parsed.meta?[McpMetaKey.subscriptionId], 'sub-1');
      }
    });

    test('experimental completion list changed validates wrapper directly', () {
      // ignore: deprecated_member_use_from_same_package, deprecated_member_use
      final valid = JsonRpcCompletionListChangedNotification.fromJson({
        'jsonrpc': '2.0',
        'method': Method.notificationsExperimentalCompletionsListChanged,
        'params': {
          '_meta': {McpMetaKey.subscriptionId: 'sub-1'},
        },
      });
      expect(valid.meta?[McpMetaKey.subscriptionId], 'sub-1');

      for (final json in [
        {
          'jsonrpc': '1.0',
          'method': Method.notificationsExperimentalCompletionsListChanged,
        },
        {
          'jsonrpc': '2.0',
          // ignore: deprecated_member_use
          'method': Method.notificationsCompletionsListChanged,
        },
        {
          'jsonrpc': '2.0',
          'method': Method.notificationsExperimentalCompletionsListChanged,
          'result': {'ok': true},
        },
        {
          'jsonrpc': '2.0',
          'method': Method.notificationsExperimentalCompletionsListChanged,
          'error': {'code': -32600, 'message': 'Invalid request'},
        },
      ]) {
        expect(
          // ignore: deprecated_member_use_from_same_package, deprecated_member_use
          () => JsonRpcCompletionListChangedNotification.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      }
    });

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
      expect(
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson({
          'method': Method.notificationsSubscriptionsAcknowledged,
          'params': {
            'notifications': {'toolsListChanged': true},
            '_meta': {'bad': Object()},
          },
        }),
        throwsFormatException,
      );
      expect(
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson(
          const {
            'method': Method.notificationsSubscriptionsAcknowledged,
            'params': 'bad',
          },
        ),
        throwsFormatException,
      );
      expect(
        () => JsonRpcSubscriptionsAcknowledgedNotification.fromJson(
          const {
            'method': Method.notificationsSubscriptionsAcknowledged,
            'params': null,
          },
        ),
        throwsFormatException,
      );
      expect(
        () => SubscriptionsAcknowledgedNotification.fromJson({
          'notifications': <Object?, Object?>{
            1: true,
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('RequestHandlerExtra subscription helpers', () {
    test('require acknowledgment before stream notifications', () async {
      final sent = <JsonRpcNotification>[];
      final extra = _subscriptionExtra(sent);

      expect(
        () => extra.sendSubscriptionNotification(
          const JsonRpcToolListChangedNotification(),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains(Method.notificationsSubscriptionsAcknowledged),
          ),
        ),
      );
      expect(sent, isEmpty);
    });

    test('allow only acknowledged notification filters', () async {
      final sent = <JsonRpcNotification>[];
      final extra = _subscriptionExtra(sent);

      await extra.sendSubscriptionAcknowledged(
        const SubscriptionFilter(
          toolsListChanged: true,
          resourcesListChanged: true,
          resourceSubscriptions: ['file:///project/config.json'],
          taskIds: ['task-1'],
        ),
      );
      expect(sent.single.method, Method.notificationsSubscriptionsAcknowledged);
      sent.clear();

      await extra.sendSubscriptionNotification(
        const JsonRpcToolListChangedNotification(),
      );
      await extra.sendSubscriptionNotification(
        JsonRpcResourceUpdatedNotification(
          updatedParams: const ResourceUpdatedNotification(
            uri: 'file:///project/config.json',
          ),
        ),
      );
      await extra.sendSubscriptionNotification(
        const JsonRpcResourceListChangedNotification(),
      );
      await extra.sendSubscriptionNotification(
        JsonRpcTaskNotification(
          task: const TaskExtensionTask(
            taskId: 'task-1',
            status: TaskStatus.working,
            createdAt: '2026-07-28T00:00:00Z',
            lastUpdatedAt: '2026-07-28T00:01:00Z',
            ttlMs: 300000,
          ),
        ),
      );

      expect(sent, hasLength(4));
      expect(
        sent.map(
          (notification) => notification.meta?[McpMetaKey.subscriptionId],
        ),
        everyElement('sub-1'),
      );

      expect(
        () => extra.sendSubscriptionNotification(
          const JsonRpcPromptListChangedNotification(),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('not requested or acknowledged'),
          ),
        ),
      );
      expect(
        () => extra.sendSubscriptionNotification(
          JsonRpcResourceUpdatedNotification(
            updatedParams: const ResourceUpdatedNotification(
              uri: 'file:///project/other.json',
            ),
          ),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('not requested or acknowledged'),
          ),
        ),
      );
      expect(
        () => extra.sendSubscriptionNotification(
          const JsonRpcNotification(method: 'notifications/custom'),
        ),
        throwsA(
          isA<McpError>().having(
            (error) => error.message,
            'message',
            contains('not requested or acknowledged'),
          ),
        ),
      );
    });
  });
}
