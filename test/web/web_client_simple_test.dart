@TestOn('browser')
library;

import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Simple mock transport for testing Client functionality
class SimpleTestTransport extends Transport {
  final List<JsonRpcMessage> _sentMessages = [];
  bool _isStarted = false;
  bool _isClosed = false;
  String? _sessionId;

  // Response configuration
  bool failInitialization = false;
  bool failPing = false;

  @override
  String? get sessionId => _sessionId;

  List<JsonRpcMessage> get sentMessages => List.unmodifiable(_sentMessages);

  @override
  Future<void> start() async {
    if (_isStarted) throw StateError('Transport already started');
    _isStarted = true;
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_isClosed) throw StateError('Transport is closed');
    if (!_isStarted) throw StateError('Transport not started');

    _sentMessages.add(message);

    // Immediately simulate response
    _simulateResponse(message);
  }

  void _simulateResponse(JsonRpcMessage message) {
    Timer.run(() {
      if (message is JsonRpcInitializeRequest) {
        if (failInitialization) {
          final error = JsonRpcError(
            id: message.id,
            error: JsonRpcErrorData(
              code: ErrorCode.internalError.value,
              message: 'Test initialization failure',
            ),
          );
          onmessage?.call(error);
          return;
        }

        final response = JsonRpcResponse(
          id: message.id,
          result: InitializeResult(
            protocolVersion: latestProtocolVersion,
            capabilities: ServerCapabilities.fromJson({
              'tools': {},
              'resources': {},
              'prompts': {},
            }),
            serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
          ).toJson(),
        );
        _sessionId = 'test-session-123';
        onmessage?.call(response);
      } else if (message is JsonRpcPingRequest) {
        if (failPing) {
          final error = JsonRpcError(
            id: message.id,
            error: JsonRpcErrorData(
              code: ErrorCode.internalError.value,
              message: 'Test ping failure',
            ),
          );
          onmessage?.call(error);
          return;
        }

        final response = JsonRpcResponse(
          id: message.id,
          result: const EmptyResult().toJson(),
        );
        onmessage?.call(response);
      }
    });
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    onclose?.call();
  }
}

void main() {
  group('Web Client Simple Tests', () {
    late SimpleTestTransport transport;
    late Client client;

    setUp(() {
      transport = SimpleTestTransport();
      client = Client(
        Implementation(name: 'test-client', version: '1.0.0'),
        options: ClientOptions(
          capabilities: ClientCapabilities(
            roots: ClientCapabilitiesRoots(listChanged: true),
          ),
        ),
      );
    });

    tearDown(() async {
      await client.close();
      await transport.close();
    });

    test('creates client with capabilities', () {
      expect(client, isA<Client>());
    });

    test('can register capabilities before connection', () {
      final testClient = Client(
        Implementation(name: 'test', version: '1.0.0'),
      );

      expect(
        () => testClient.registerCapabilities(
          ClientCapabilities(experimental: {'test': true}),
        ),
        returnsNormally,
      );
    });

    test('throws when registering capabilities after connection', () async {
      await client.connect(transport);

      expect(
        () => client.registerCapabilities(
          ClientCapabilities(experimental: {'test': true}),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('successfully connects and initializes', () async {
      await client.connect(transport);

      expect(client.getServerVersion()?.name, equals('test-server'));
      expect(client.getServerVersion()?.version, equals('1.0.0'));
      expect(client.getServerCapabilities(), isNotNull);
      expect(transport.sentMessages,
          hasLength(2)); // Init + initialized notification
    });

    test('handles initialization failure', () async {
      transport.failInitialization = true;

      expect(
        () async => await client.connect(transport),
        throwsA(isA<McpError>()),
      );
    });

    test('ping succeeds after connection', () async {
      await client.connect(transport);

      final result = await client.ping();
      expect(result, isA<EmptyResult>());

      final pingMessages =
          transport.sentMessages.whereType<JsonRpcPingRequest>().toList();
      expect(pingMessages, hasLength(1));
    });

    test('ping fails when transport configured to fail', () async {
      await client.connect(transport);
      transport.failPing = true;

      expect(
        () async => await client.ping(),
        throwsA(isA<McpError>()),
      );
    });

    test('throws when checking capabilities before initialization', () {
      expect(
        () => client.assertCapabilityForMethod('tools/list'),
        throwsA(isA<StateError>()),
      );
    });

    test('returns null for server info before initialization', () {
      expect(client.getServerVersion(), isNull);
      expect(client.getServerCapabilities(), isNull);
      expect(client.getInstructions(), isNull);
    });

    test('allows capability checking after initialization', () async {
      await client.connect(transport);

      expect(
        () => client.assertCapabilityForMethod('tools/list'),
        returnsNormally,
      );
    });
  });
}
