@TestOn('browser')
library;

import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Mock transport that simulates server responses
class MockTransport extends Transport {
  final List<JsonRpcMessage> _sentMessages = [];

  bool _isStarted = false;
  bool _isClosed = false;
  String? _sessionId;

  // Configuration for mock responses
  bool shouldFailInitialization = false;
  bool shouldFailPing = false;
  Map<String, dynamic>? mockServerCapabilities;
  Implementation? mockServerInfo;
  String? mockInstructions;
  List<Tool> mockTools = [];

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

    // Simulate server responses
    _simulateResponse(message);
  }

  void _simulateResponse(JsonRpcMessage message) {
    // Simulate immediate synchronous response for web tests
    // await Future.delayed(const Duration(milliseconds: 1));

    if (message is JsonRpcRequest && message.method == 'initialize') {
      if (shouldFailInitialization) {
        final error = JsonRpcError(
          id: message.id,
          error: JsonRpcErrorData(
            code: ErrorCode.internalError.value,
            message: 'Mock initialization failure',
          ),
        );
        onmessage?.call(error);
        return;
      }

      final capabilitiesData = Map<String, dynamic>.from(
        mockServerCapabilities ??
            {
              'tools': <String, dynamic>{},
              'resources': <String, dynamic>{},
              'prompts': <String, dynamic>{},
            },
      );
      final initResult = InitializeResult(
        protocolVersion: latestProtocolVersion,
        capabilities: ServerCapabilities.fromJson(capabilitiesData),
        serverInfo: mockServerInfo ??
            Implementation(name: 'mock-server', version: '1.0.0'),
        instructions: mockInstructions,
      );
      final response = JsonRpcResponse(
        id: message.id,
        result: Map<String, dynamic>.from(initResult.toJson()),
      );
      _sessionId = 'mock-session-123';
      onmessage?.call(response);
    } else if (message is JsonRpcRequest && message.method == 'ping') {
      if (shouldFailPing) {
        final error = JsonRpcError(
          id: message.id,
          error: JsonRpcErrorData(
            code: ErrorCode.internalError.value,
            message: 'Mock ping failure',
          ),
        );
        onmessage?.call(error);
        return;
      }

      final response = JsonRpcResponse(
        id: message.id,
        result: Map<String, dynamic>.from(const EmptyResult().toJson()),
      );
      onmessage?.call(response);
    } else if (message is JsonRpcRequest && message.method == 'tools/list') {
      final response = JsonRpcResponse(
        id: message.id,
        result: Map<String, dynamic>.from(
            ListToolsResult(tools: mockTools).toJson()),
      );
      onmessage?.call(response);
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    onclose?.call();
  }
}

/// Simple transport that returns initialization error
class SimpleErrorTransport extends Transport {
  bool _isStarted = false;
  bool _isClosed = false;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {
    print("ERROR_TRANSPORT_DEBUG: start() called");
    if (_isStarted) throw StateError('Transport already started');
    _isStarted = true;
    print("ERROR_TRANSPORT_DEBUG: start() completed successfully");
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    print("ERROR_TRANSPORT_DEBUG: send() called with: ${message.toJson()}");
    print(
        "ERROR_TRANSPORT_DEBUG: _isClosed: $_isClosed, _isStarted: $_isStarted");
    if (_isClosed) throw StateError('Transport is closed');
    if (!_isStarted) throw StateError('Transport not started');

    if (message is JsonRpcRequest && message.method == 'initialize') {
      print("ERROR_TRANSPORT_DEBUG: sending initialization error");
      final error = JsonRpcError(
        id: message.id,
        error: JsonRpcErrorData(
          code: ErrorCode.internalError.value,
          message: 'Simple initialization failure',
        ),
      );

      // Call onmessage synchronously to deliver the error
      print("ERROR_TRANSPORT_DEBUG: calling onmessage with error");
      onmessage?.call(error);
      print("ERROR_TRANSPORT_DEBUG: onmessage called");

      // DON'T close the transport here - let the protocol handle cleanup
      print("ERROR_TRANSPORT_DEBUG: error sent, leaving transport open");
    }
  }

  @override
  Future<void> close() async {
    print("ERROR_TRANSPORT_DEBUG: close() called");
    print("ERROR_TRANSPORT_DEBUG: close() stack trace:");
    print(StackTrace.current);
    if (_isClosed) return;
    _isClosed = true;
    print("ERROR_TRANSPORT_DEBUG: calling onclose");
    onclose?.call();
    print("ERROR_TRANSPORT_DEBUG: onclose called");
  }
}

/// Completely isolated transport for error testing (won't be affected by tearDown)
class IsolatedErrorTransport extends Transport {
  bool _isStarted = false;
  bool _isClosed = false;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {
    if (_isStarted) throw StateError('Transport already started');
    _isStarted = true;
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_isClosed) throw StateError('Transport is closed');
    if (!_isStarted) throw StateError('Transport not started');

    if (message is JsonRpcRequest && message.method == 'initialize') {
      final error = JsonRpcError(
        id: message.id,
        error: JsonRpcErrorData(
          code: ErrorCode.internalError.value,
          message: 'Isolated initialization failure',
        ),
      );

      // Call onmessage synchronously to deliver the error
      onmessage?.call(error);
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    // NOTE: Do NOT call onclose here unless explicitly requested
    // onclose?.call();
  }
}

/// Custom transport that returns unsupported protocol version
class CustomProtocolVersionTransport extends Transport {
  bool _isStarted = false;
  bool _isClosed = false;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {
    if (_isStarted) throw StateError('Transport already started');
    _isStarted = true;
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_isClosed) throw StateError('Transport is closed');
    if (!_isStarted) throw StateError('Transport not started');

    if (message is JsonRpcRequest && message.method == 'initialize') {
      final initResult = InitializeResult(
        protocolVersion: '999.0.0', // Unsupported version
        capabilities: ServerCapabilities.fromJson(
            Map<String, dynamic>.from({'tools': <String, dynamic>{}})),
        serverInfo: Implementation(name: 'test', version: '1.0.0'),
      );
      final response = JsonRpcResponse(
        id: message.id,
        result: Map<String, dynamic>.from(initResult.toJson()),
      );
      onmessage?.call(response);
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    onclose?.call();
  }
}

void main() {
  group('Web Client Tests', () {
    late MockTransport mockTransport;
    late Client client;

    setUp(() {
      mockTransport = MockTransport();
      client = Client(
        Implementation(name: 'test-client', version: '1.0.0'),
        options: ClientOptions(
          capabilities: ClientCapabilities(
            roots: ClientCapabilitiesRoots(listChanged: true),
            sampling: {},
          ),
        ),
      );
    });

    tearDown(() async {
      await client.close();
      await mockTransport.close();
    });

    group('Client Instantiation', () {
      test('creates client with default options', () {
        final testClient = Client(
          Implementation(name: 'test', version: '1.0.0'),
        );
        expect(testClient, isA<Client>());
      });

      test('creates client with custom capabilities', () {
        final capabilities = ClientCapabilities(
          roots: ClientCapabilitiesRoots(listChanged: false),
          sampling: {'custom': true},
        );
        final testClient = Client(
          Implementation(name: 'test', version: '1.0.0'),
          options: ClientOptions(capabilities: capabilities),
        );
        expect(testClient, isA<Client>());
      });

      test('can register additional capabilities before connection', () {
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
        await client.connect(mockTransport);

        expect(
          () => client.registerCapabilities(
            ClientCapabilities(experimental: {'test': true}),
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('Client Connection', () {
      test('successfully connects and initializes', () async {
        mockTransport.mockServerInfo =
            Implementation(name: 'test-server', version: '2.0.0');
        mockTransport.mockInstructions = 'Test instructions';

        await client.connect(mockTransport);

        expect(client.getServerVersion()?.name, equals('test-server'));
        expect(client.getServerVersion()?.version, equals('2.0.0'));
        expect(client.getInstructions(), equals('Test instructions'));
        expect(client.getServerCapabilities(), isNotNull);
      });

      test('handles initialization failure', () async {
        mockTransport.shouldFailInitialization = true;

        expect(
          () async => await client.connect(mockTransport),
          throwsA(isA<McpError>()),
        );
      });

      test('validates protocol version compatibility - isolated', () async {
        // Completely self-contained test with isolated transport
        final isolatedTransport = CustomProtocolVersionTransport();
        final isolatedClient = Client(
          Implementation(name: 'isolated-version-test', version: '1.0.0'),
        );

        try {
          await isolatedClient.connect(isolatedTransport);
          fail('Should have thrown McpError for unsupported protocol version');
        } catch (e) {
          expect(e, isA<McpError>());
        } finally {
          await isolatedClient.close();
          await isolatedTransport.close();
        }
      });
    });

    group('Client Methods', () {
      setUp(() async {
        await client.connect(mockTransport);
      });

      test('ping succeeds', () async {
        final result = await client.ping();
        expect(result, isA<EmptyResult>());

        final sentMessages = mockTransport.sentMessages;
        final pingMessage = sentMessages.firstWhere(
          (msg) => msg is JsonRpcRequest && msg.method == 'ping',
        ) as JsonRpcRequest;
        expect(pingMessage, isNotNull);
      });

      test('ping handles failure', () async {
        mockTransport.shouldFailPing = true;

        expect(
          () async => await client.ping(),
          throwsA(isA<McpError>()),
        );
      });

      test('listTools returns available tools', () async {
        mockTransport.mockTools = [
          Tool(
            name: 'test-tool',
            description: 'A test tool',
            inputSchema: ToolInputSchema(properties: {}),
          ),
        ];

        final result = await client.listTools();
        expect(result.tools, hasLength(1));
        expect(result.tools.first.name, equals('test-tool'));
        expect(result.tools.first.description, equals('A test tool'));
      });

      test('listTools with parameters', () async {
        final params = ListToolsRequestParams(cursor: 'test-cursor');
        await client.listTools(params: params);

        final sentMessages = mockTransport.sentMessages;
        final listMessage = sentMessages.firstWhere(
          (msg) => msg is JsonRpcRequest && msg.method == 'tools/list',
        ) as JsonRpcRequest;
        expect(listMessage.params?['cursor'], equals('test-cursor'));
      });
    });

    group('Capability Checking', () {
      setUp(() async {
        await client.connect(mockTransport);
      });

      test('allows methods when server supports capability', () {
        expect(
          () => client.assertCapabilityForMethod('tools/list'),
          returnsNormally,
        );
      });

      test('throws when server lacks required capability', () async {
        // Create client with server that has no capabilities
        final noCapTransport = MockTransport();
        noCapTransport.mockServerCapabilities = {};
        final noCapClient = Client(
          Implementation(name: 'test', version: '1.0.0'),
        );

        await noCapClient.connect(noCapTransport);

        expect(
          () => noCapClient.assertCapabilityForMethod('tools/list'),
          throwsA(isA<McpError>()),
        );

        await noCapClient.close();
        await noCapTransport.close();
      });

      test('handles custom methods gracefully', () {
        expect(
          () => client.assertCapabilityForMethod('custom/method'),
          returnsNormally,
        );
      });
    });

    group('Error Handling', () {
      test('handles transport errors during connection - isolated', () async {
        // Completely self-contained test with isolated transport
        final isolatedErrorTransport = IsolatedErrorTransport();
        final isolatedClient = Client(
          Implementation(name: 'isolated-error-test', version: '1.0.0'),
        );

        try {
          await isolatedClient.connect(isolatedErrorTransport);
          fail('Should have thrown McpError for initialization failure');
        } catch (e) {
          expect(e, isA<McpError>());
        } finally {
          await isolatedClient.close();
          await isolatedErrorTransport.close();
        }
      });

      test('closes properly on initialization failure', () async {
        mockTransport.shouldFailInitialization = true;

        try {
          await client.connect(mockTransport);
          fail('Should have thrown');
        } catch (e) {
          // Expected
        }

        // Client should be closed
        expect(client.transport, isNull);
      });
    });

    group('State Management', () {
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
    });
  });
}
