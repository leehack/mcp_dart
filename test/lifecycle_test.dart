import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class LifecycleTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool closed = false;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {}

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
  }

  @override
  Future<void> close() async {
    closed = true;
    onclose?.call();
  }

  void emit(JsonRpcMessage message) {
    onmessage?.call(message);
  }
}

class BlockingInitializedSendTransport extends LifecycleTransport {
  final Completer<void> initializedSendStarted = Completer<void>();
  final Completer<void> initializedSendReleased = Completer<void>();

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
    if (message is JsonRpcNotification &&
        message.method == Method.notificationsInitialized) {
      if (!initializedSendStarted.isCompleted) {
        initializedSendStarted.complete();
      }
      await initializedSendReleased.future;
    }
  }
}

class FailingInitializedSendTransport extends LifecycleTransport {
  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
    if (message is JsonRpcNotification &&
        message.method == Method.notificationsInitialized) {
      throw StateError('failed initialized send');
    }
  }
}

class FailingInitializeResponseTransport extends LifecycleTransport {
  var failNextInitializeResponse = true;

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
    if (message is JsonRpcResponse && failNextInitializeResponse) {
      failNextInitializeResponse = false;
      throw StateError('failed initialize response');
    }
  }
}

JsonRpcInitializeRequest _initializeRequest({RequestId id = 1}) {
  return JsonRpcInitializeRequest(
    id: id,
    initParams: const InitializeRequest(
      protocolVersion: latestProtocolVersion,
      capabilities: ClientCapabilities(),
      clientInfo: Implementation(name: 'client', version: '1.0.0'),
    ),
  );
}

JsonRpcResponse _initializeResponse({RequestId id = -1}) {
  return JsonRpcResponse(
    id: id,
    result: const InitializeResult(
      protocolVersion: latestProtocolVersion,
      capabilities: ServerCapabilities(),
      serverInfo: Implementation(name: 'server', version: '1.0.0'),
    ).toJson(),
  );
}

JsonRpcCreateMessageRequest _samplingRequest({RequestId id = 20}) {
  return JsonRpcCreateMessageRequest(
    id: id,
    createParams: const CreateMessageRequest(
      messages: [
        SamplingMessage(
          role: SamplingMessageRole.user,
          content: SamplingTextContent(text: 'hello'),
        ),
      ],
      maxTokens: 1,
    ),
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('Lifecycle gating', () {
    test('server rejects normal requests before initialize', () async {
      final transport = LifecycleTransport();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      var handlerCalled = false;
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          handlerCalled = true;
          return const ListToolsResult(tools: []);
        },
        (id, params, meta) =>
            JsonRpcListToolsRequest(id: id, params: params, meta: meta),
      );

      await server.connect(transport);
      transport.emit(const JsonRpcListToolsRequest(id: 10));
      await _settle();

      expect(handlerCalled, isFalse);
      expect(transport.sentMessages.single, isA<JsonRpcError>());
      final error = transport.sentMessages.single as JsonRpcError;
      expect(error.id, 10);
      expect(error.error.code, ErrorCode.invalidRequest.value);
      expect(error.error.message, contains('before initialize'));
    });

    test('server gates operation requests until initialized notification',
        () async {
      final transport = LifecycleTransport();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      var handlerCallCount = 0;
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async {
          handlerCallCount += 1;
          return const ListToolsResult(tools: []);
        },
        (id, params, meta) =>
            JsonRpcListToolsRequest(id: id, params: params, meta: meta),
      );

      await server.connect(transport);
      transport.emit(_initializeRequest());
      await _settle();
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());

      transport.sentMessages.clear();
      transport.emit(const JsonRpcListToolsRequest(id: 11));
      await _settle();

      expect(handlerCallCount, 0);
      expect(transport.sentMessages.single, isA<JsonRpcError>());
      final gatedError = transport.sentMessages.single as JsonRpcError;
      expect(gatedError.error.code, ErrorCode.invalidRequest.value);
      expect(gatedError.error.message, contains('notifications/initialized'));

      transport.sentMessages.clear();
      transport.emit(const JsonRpcInitializedNotification());
      transport.emit(const JsonRpcListToolsRequest(id: 12));
      await _settle();

      expect(handlerCallCount, 1);
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
      expect((transport.sentMessages.single as JsonRpcResponse).id, 12);
    });

    test('server reports lifecycle notification ordering errors', () async {
      final transport = LifecycleTransport();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      final errors = <Error>[];
      server.onerror = errors.add;

      await server.connect(transport);
      transport.emit(const JsonRpcNotification(method: 'custom/event'));
      await _settle();
      expect(errors.single, isA<McpError>());
      expect(errors.single.toString(), contains('before initialize'));

      errors.clear();
      transport.emit(const JsonRpcInitializedNotification());
      await _settle();
      expect(errors.single, isA<McpError>());
      expect(errors.single.toString(), contains('before initialize'));

      transport.emit(_initializeRequest());
      await _settle();
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());

      transport.sentMessages.clear();
      transport.emit(_initializeRequest(id: 2));
      await _settle();
      expect(transport.sentMessages.single, isA<JsonRpcError>());
      final duplicateInitializeError =
          transport.sentMessages.single as JsonRpcError;
      expect(duplicateInitializeError.id, 2);
      expect(
        duplicateInitializeError.error.code,
        ErrorCode.invalidRequest.value,
      );
      expect(duplicateInitializeError.error.message, contains('duplicate'));

      errors.clear();
      transport.emit(const JsonRpcNotification(method: 'custom/event'));
      await _settle();
      expect(errors.single, isA<McpError>());
      expect(errors.single.toString(), contains('notifications/initialized'));

      errors.clear();
      transport.emit(const JsonRpcInitializedNotification());
      await _settle();
      transport.emit(const JsonRpcInitializedNotification());
      await _settle();
      expect(errors.single, isA<McpError>());
      expect(errors.single.toString(), contains('duplicate'));
    });

    test('server does not mark initialize received when response send fails',
        () async {
      final transport = FailingInitializeResponseTransport();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      final errors = <Error>[];
      server.onerror = errors.add;
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async => const ListToolsResult(tools: []),
        (id, params, meta) =>
            JsonRpcListToolsRequest(id: id, params: params, meta: meta),
      );

      await server.connect(transport);
      transport.emit(_initializeRequest());
      await _settle();
      await _settle();
      expect(errors.single.toString(), contains('failed initialize response'));

      transport.sentMessages.clear();
      transport.emit(_initializeRequest(id: 2));
      await _settle();
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
      expect((transport.sentMessages.single as JsonRpcResponse).id, 2);

      transport.sentMessages.clear();
      transport.emit(const JsonRpcInitializedNotification());
      await _settle();
      transport.emit(const JsonRpcListToolsRequest(id: 32));
      await _settle();
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
    });

    test('server remains pre-ready when initialized handler throws', () async {
      final transport = LifecycleTransport();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      final errors = <Error>[];
      var initializedCalls = 0;
      server.onerror = errors.add;
      server.oninitialized = () {
        initializedCalls += 1;
        if (initializedCalls == 1) {
          throw StateError('failed initialized handler');
        }
      };
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async => const ListToolsResult(tools: []),
        (id, params, meta) =>
            JsonRpcListToolsRequest(id: id, params: params, meta: meta),
      );

      await server.connect(transport);
      transport.emit(_initializeRequest());
      await _settle();
      transport.sentMessages.clear();

      transport.emit(const JsonRpcInitializedNotification());
      await _settle();
      expect(errors.single.toString(), contains('failed initialized handler'));

      transport.emit(const JsonRpcListToolsRequest(id: 33));
      await _settle();
      expect(transport.sentMessages.single, isA<JsonRpcError>());
      final gatedError = transport.sentMessages.single as JsonRpcError;
      expect(gatedError.error.message, contains('notifications/initialized'));

      transport.sentMessages.clear();
      transport.emit(const JsonRpcInitializedNotification());
      await _settle();
      transport.emit(const JsonRpcListToolsRequest(id: 34));
      await _settle();
      expect(initializedCalls, 2);
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
    });

    test('server resets lifecycle state across reconnects', () async {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      server.setRequestHandler<JsonRpcListToolsRequest>(
        Method.toolsList,
        (request, extra) async => const ListToolsResult(tools: []),
        (id, params, meta) =>
            JsonRpcListToolsRequest(id: id, params: params, meta: meta),
      );

      final firstTransport = LifecycleTransport();
      await server.connect(firstTransport);
      firstTransport.emit(_initializeRequest());
      await _settle();
      firstTransport.emit(const JsonRpcInitializedNotification());
      await _settle();
      firstTransport.sentMessages.clear();
      firstTransport.emit(const JsonRpcListToolsRequest(id: 30));
      await _settle();
      expect(firstTransport.sentMessages.single, isA<JsonRpcResponse>());

      await server.close();

      final secondTransport = LifecycleTransport();
      await server.connect(secondTransport);
      secondTransport.emit(_initializeRequest());
      await _settle();
      expect(secondTransport.sentMessages.single, isA<JsonRpcResponse>());

      secondTransport.sentMessages.clear();
      secondTransport.emit(const JsonRpcInitializedNotification());
      await _settle();
      secondTransport.emit(const JsonRpcListToolsRequest(id: 31));
      await _settle();
      expect(secondTransport.sentMessages.single, isA<JsonRpcResponse>());
    });

    test(
        'client rejects server requests before initialized notification is sent',
        () async {
      final transport = LifecycleTransport();
      final client = Client(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const ClientOptions(
          useServerDiscover: false,
          capabilities: ClientCapabilities(
            sampling: ClientCapabilitiesSampling(),
          ),
        ),
      );
      var handlerCalled = false;
      client.onSamplingRequest = (params) async {
        handlerCalled = true;
        return const CreateMessageResult(
          model: 'model',
          role: SamplingMessageRole.assistant,
          content: SamplingTextContent(text: 'ok'),
        );
      };

      final connectFuture = client.connect(transport);
      await _settle();
      transport.sentMessages.clear();

      transport.emit(_samplingRequest());
      await _settle();

      expect(handlerCalled, isFalse);
      expect(transport.sentMessages.single, isA<JsonRpcError>());
      final error = transport.sentMessages.single as JsonRpcError;
      expect(error.id, 20);
      expect(error.error.code, ErrorCode.invalidRequest.value);
      expect(error.error.message, contains('notifications/initialized'));

      await client.close();
      await expectLater(connectFuture, throwsA(isA<McpError>()));
    });

    test('client rejects notifications before initialized notification is sent',
        () async {
      final transport = LifecycleTransport();
      final client = Client(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const ClientOptions(useServerDiscover: false),
      );
      final errors = <Error>[];
      client.onerror = errors.add;

      final connectFuture = client.connect(transport);
      await _settle();
      transport.emit(const JsonRpcNotification(method: 'custom/event'));
      await _settle();

      expect(errors.single, isA<McpError>());
      expect(errors.single.toString(), contains('notifications/initialized'));

      await client.close();
      await expectLater(connectFuture, throwsA(isA<McpError>()));
    });

    test('client rejects server requests while initialized send is pending',
        () async {
      final transport = BlockingInitializedSendTransport();
      final client = Client(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const ClientOptions(
          useServerDiscover: false,
          capabilities: ClientCapabilities(
            sampling: ClientCapabilitiesSampling(),
          ),
        ),
      );
      var handlerCallCount = 0;
      client.onSamplingRequest = (params) async {
        handlerCallCount += 1;
        return const CreateMessageResult(
          model: 'model',
          role: SamplingMessageRole.assistant,
          content: SamplingTextContent(text: 'ok'),
        );
      };

      final connectFuture = client.connect(transport);
      await _settle();
      final initRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.emit(_initializeResponse(id: initRequest.id));
      await transport.initializedSendStarted.future;

      transport.sentMessages.clear();
      transport.emit(_samplingRequest(id: 21));
      await _settle();

      expect(handlerCallCount, 0);
      expect(transport.sentMessages.single, isA<JsonRpcError>());
      final error = transport.sentMessages.single as JsonRpcError;
      expect(error.id, 21);
      expect(error.error.code, ErrorCode.invalidRequest.value);
      expect(error.error.message, contains('notifications/initialized'));

      transport.sentMessages.clear();
      transport.initializedSendReleased.complete();
      await connectFuture.timeout(const Duration(seconds: 1));
      transport.emit(_samplingRequest(id: 22));
      await _settle();

      expect(handlerCallCount, 1);
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
      expect((transport.sentMessages.single as JsonRpcResponse).id, 22);
      await client.close();
    });

    test('client keeps lifecycle closed when initialized send fails', () async {
      final transport = FailingInitializedSendTransport();
      final client = Client(
        const Implementation(name: 'client', version: '1.0.0'),
        options: const ClientOptions(useServerDiscover: false),
      );

      final connectFuture = client.connect(transport);
      await _settle();
      final initRequest = transport.sentMessages.single as JsonRpcRequest;
      transport.emit(_initializeResponse(id: initRequest.id));

      await expectLater(connectFuture, throwsA(isA<StateError>()));
      expect(transport.closed, isTrue);
    });
  });
}
