import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];
  final StreamController<JsonRpcMessage> messageController =
      StreamController<JsonRpcMessage>.broadcast();
  bool isStarted = false;
  final String? _sessionId;

  MockTransport([this._sessionId]);

  @override
  String? get sessionId => _sessionId;

  @override
  Future<void> close() async {
    await messageController.close();
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
    if (message is JsonRpcRequest) {
      if (message.method == 'ping') {
        onmessage?.call(JsonRpcResponse(id: message.id, result: {}));
      }
      // Auto-respond to elicitation/create
      if (message.method == Method.elicitationCreate) {
        onmessage?.call(
          JsonRpcResponse(
            id: message.id,
            result: {
              'action': 'accept',
              'content': {'field': 'value'},
            },
          ),
        );
      }
    }
  }

  @override
  Future<void> start() async {
    isStarted = true;
  }

  void receiveMessage(JsonRpcMessage message) {
    messageController.add(message);
    onmessage?.call(message);
  }
}

void main() {
  group('Server Advanced Tests', () {
    late Server server;
    late MockTransport transport;
    late Implementation serverInfo;

    setUp(() {
      serverInfo = const Implementation(name: 'TestServer', version: '1.0.0');
      server = Server(serverInfo);
      transport = MockTransport('test-session');
    });

    test('elicitInput sends correct request and returns result', () async {
      final capabilities = const ServerCapabilities();
      final options = ServerOptions(capabilities: capabilities);
      server = Server(serverInfo, options: options);
      await server.connect(transport);

      // Initialize with elicitation capability
      final clientCaps = const ClientCapabilities(
        elicitation: ClientElicitation.formOnly(),
      );
      final initParams = InitializeRequestParams(
        protocolVersion: latestProtocolVersion,
        capabilities: clientCaps,
        clientInfo: const Implementation(name: 'Client', version: '1.0'),
      );
      transport.receiveMessage(
        JsonRpcInitializeRequest(id: 1, initParams: initParams),
      );
      await Future.delayed(Duration.zero);
      transport.receiveMessage(const JsonRpcInitializedNotification());

      final params = const ElicitRequestParams.form(
        message: "Please fill this",
        requestedSchema: {"type": "object"},
      );

      final result = await server.elicitInput(params);

      expect(
        transport.sentMessages.any(
          (m) => m is JsonRpcRequest && m.method == Method.elicitationCreate,
        ),
        isTrue,
      );
      expect(result.action, equals('accept'));
      expect(result.content, equals({'field': 'value'}));
    });

    test('logging/setLevel updates internal log level', () async {
      final capabilities = const ServerCapabilities(
        logging: {
          "supportedLevels": ["debug", "info", "error"],
        },
      );
      final options = ServerOptions(capabilities: capabilities);
      server = Server(serverInfo, options: options);
      await server.connect(transport);

      // Initialize
      transport.receiveMessage(
        JsonRpcInitializeRequest(
          id: 1,
          initParams: const InitializeRequestParams(
            protocolVersion: latestProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0'),
          ),
        ),
      );
      await Future.delayed(Duration.zero);
      transport.receiveMessage(const JsonRpcInitializedNotification());

      // Send setLevel request
      transport.receiveMessage(
        JsonRpcSetLevelRequest(
          id: 2,
          setParams: const SetLevelRequestParams(level: LoggingLevel.error),
        ),
      );
      await Future.delayed(Duration.zero);

      // Verify response
      expect(transport.sentMessages.last, isA<JsonRpcResponse>());

      // Now send logs. Info should be ignored. Error should be sent.
      transport.sentMessages.clear();

      await server.sendLoggingMessage(
        const LoggingMessageNotificationParams(
          level: LoggingLevel.info,
          data: "info log",
        ),
        sessionId: 'test-session',
      );

      expect(transport.sentMessages, isEmpty); // Should be ignored

      await server.sendLoggingMessage(
        const LoggingMessageNotificationParams(
          level: LoggingLevel.error,
          data: "error log",
        ),
        sessionId: 'test-session',
      );

      expect(transport.sentMessages, isNotEmpty);
      expect(
        (transport.sentMessages.last as JsonRpcNotification).method,
        equals(Method.notificationsMessage),
      );
    });

    test('tools/call validation wrapper detects wrong return type', () async {
      final capabilities = const ServerCapabilities(
        tools: ServerCapabilitiesTools(),
        tasks: ServerCapabilitiesTasks(),
      );
      final options = ServerOptions(capabilities: capabilities);
      server = Server(serverInfo, options: options);

      // Register a tool handler that returns WRONG result type
      server.setRequestHandler<JsonRpcCallToolRequest>(
        Method.toolsCall,
        (req, extra) async {
          // Return wrong type for testing validation
          return const EmptyResult();
        },
        (id, params, meta) => JsonRpcCallToolRequest.fromJson(
          {'id': id, 'params': params, '_meta': meta},
        ),
      );

      await server.connect(transport);

      // Initialize
      transport.receiveMessage(
        JsonRpcInitializeRequest(
          id: 1,
          initParams: const InitializeRequestParams(
            protocolVersion: latestProtocolVersion,
            capabilities: ClientCapabilities(),
            clientInfo: Implementation(name: 'Client', version: '1.0'),
          ),
        ),
      );

      // Send tool call
      transport.receiveMessage(
        JsonRpcCallToolRequest(
          id: 2,
          callParams: const CallToolRequestParams(name: 'tool'),
        ),
      );

      await Future.delayed(Duration.zero);

      // Should receive error response due to validation failure
      expect(transport.sentMessages.last, isA<JsonRpcError>());
      final error = transport.sentMessages.last as JsonRpcError;
      expect(error.error.message, contains("Expected CallToolResult"));
    });

    test('createElicitationCompletionNotifier sends complete notification',
        () async {
      final capabilities = const ServerCapabilities();
      final options = ServerOptions(capabilities: capabilities);
      server = Server(serverInfo, options: options);
      await server.connect(transport);

      // Initialize with URL elicitation capability
      final clientCaps = const ClientCapabilities(
        elicitation: ClientElicitation.all(),
      );
      final initParams = InitializeRequestParams(
        protocolVersion: latestProtocolVersion,
        capabilities: clientCaps,
        clientInfo: const Implementation(name: 'Client', version: '1.0'),
      );
      transport.receiveMessage(
        JsonRpcInitializeRequest(id: 1, initParams: initParams),
      );
      await Future.delayed(Duration.zero);
      transport.receiveMessage(const JsonRpcInitializedNotification());

      const elicitationId = 'my-elicitation-id';
      final completeNotifier =
          server.createElicitationCompletionNotifier(elicitationId);

      await completeNotifier(); // Execute the returned function

      expect(
        transport.sentMessages.any(
          (m) =>
              m is JsonRpcNotification &&
              m.method == Method.notificationsElicitationComplete,
        ),
        isTrue,
      );
      final rawNotification =
          transport.sentMessages.last as JsonRpcNotification;
      final notification = JsonRpcElicitationCompleteNotification.fromJson(
        rawNotification.toJson(),
      );
      expect(notification.completeParams.elicitationId, equals(elicitationId));
    });
  });
}
