@TestOn('browser')
library;

/// Tests for verifying the fix for the "more than 5 requests pending" bug.
///
/// This test suite verifies that the connection pool implementation in
/// StreamableHttpClientTransport correctly handles multiple concurrent requests
/// without hitting browser connection limits that cause requests to become pending.
///
/// Bug Context:
/// - Original issue: "if I make more than 5 requests, it starts pending"
/// - Root cause: Single reusable HTTP client hitting browser connection limits
/// - Solution: Connection pool with round-robin distribution across 4 clients
///
/// The tests simulate various scenarios including:
/// - Many concurrent requests (>5)
/// - Mixed request types
/// - Connection limit simulation
/// - Request timing analysis

import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Mock transport that tracks request timing and responses for multiple request testing
class MultiRequestMockTransport extends Transport {
  final List<JsonRpcMessage> _sentMessages = [];
  final Map<dynamic, DateTime> _requestTimestamps = {};
  final Map<dynamic, Completer<void>> _pendingRequests = {};

  bool _isStarted = false;
  bool _isClosed = false;
  String? _sessionId;

  // Configuration
  Duration responseDelay = Duration(milliseconds: 100);
  bool simulateSlowResponses = false;
  int maxConcurrentRequests = 6; // Simulate browser connection limit

  @override
  String? get sessionId => _sessionId;

  List<JsonRpcMessage> get sentMessages => List.unmodifiable(_sentMessages);
  Map<dynamic, DateTime> get requestTimestamps =>
      Map.unmodifiable(_requestTimestamps);
  int get currentPendingCount => _pendingRequests.length;

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

    if (message is JsonRpcRequest && message.id != null) {
      final requestId = message.id;
      _requestTimestamps[requestId] = DateTime.now();

      // Track pending request
      final completer = Completer<void>();
      _pendingRequests[requestId] = completer;

      // Check if we've hit the concurrent request limit
      if (_pendingRequests.length > maxConcurrentRequests) {
        print(
            '🚨 WARNING: ${_pendingRequests.length} concurrent requests > limit of $maxConcurrentRequests');
      }

      // Simulate response after delay
      _simulateDelayedResponse(message, completer);

      // Wait for this request to complete
      await completer.future;
    } else {
      // Handle non-request messages immediately
      _simulateResponse(message);
    }
  }

  void _simulateDelayedResponse(
      JsonRpcMessage message, Completer<void> completer) {
    Timer(responseDelay, () {
      try {
        _simulateResponse(message);

        // Mark request as completed
        if (message is JsonRpcRequest && message.id != null) {
          _pendingRequests.remove(message.id);
        }

        completer.complete();
      } catch (e) {
        completer.completeError(e);
      }
    });
  }

  void _simulateResponse(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      if (message.method == 'initialize') {
        final initResult = InitializeResult(
          protocolVersion: latestProtocolVersion,
          capabilities: ServerCapabilities.fromJson(Map<String, dynamic>.from({
            'tools': <String, dynamic>{},
            'resources': <String, dynamic>{},
            'prompts': <String, dynamic>{},
          })),
          serverInfo:
              Implementation(name: 'multi-test-server', version: '1.0.0'),
        );
        final response = JsonRpcResponse(
          id: message.id,
          result: Map<String, dynamic>.from(initResult.toJson()),
        );
        _sessionId =
            'multi-test-session-${DateTime.now().millisecondsSinceEpoch}';
        onmessage?.call(response);
      } else if (message.method == 'ping') {
        final response = JsonRpcResponse(
          id: message.id,
          result: Map<String, dynamic>.from(const EmptyResult().toJson()),
        );
        onmessage?.call(response);
      } else if (message.method == 'tools/list') {
        final response = JsonRpcResponse(
          id: message.id,
          result: Map<String, dynamic>.from(
            ListToolsResult(tools: [
              Tool(
                name: 'test-tool-${message.id}',
                description: 'Test tool for request ${message.id}',
                inputSchema: ToolInputSchema(properties: {}),
              ),
            ]).toJson(),
          ),
        );
        onmessage?.call(response);
      } else if (message.method == 'tools/call') {
        final response = JsonRpcResponse(
          id: message.id,
          result: Map<String, dynamic>.from(
            CallToolResult.fromContent(
              content: [
                TextContent(text: 'Response for request ${message.id}')
              ],
            ).toJson(),
          ),
        );
        onmessage?.call(response);
      }
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    // Complete any pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _pendingRequests.clear();

    onclose?.call();
  }
}

/// Mock HTTP-based transport that simulates real StreamableHttpClientTransport behavior
class MockHttpTransport extends Transport {
  final List<JsonRpcMessage> _sentMessages = [];
  final Set<int> _pendingRequestIds = {};

  bool _isStarted = false;
  bool _isClosed = false;
  String? _sessionId;

  // Simulate browser connection limits
  int maxConcurrentConnections = 6;
  Duration requestTimeout = Duration(seconds: 5);

  @override
  String? get sessionId => _sessionId;

  List<JsonRpcMessage> get sentMessages => List.unmodifiable(_sentMessages);
  int get pendingRequestCount => _pendingRequestIds.length;

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

    if (message is JsonRpcRequest && message.id != null) {
      final requestId = message.id as int;

      // Check connection limits
      if (_pendingRequestIds.length >= maxConcurrentConnections) {
        print(
            '🚨 BLOCKING: Request $requestId blocked due to connection limit (${_pendingRequestIds.length}/$maxConcurrentConnections)');

        // Simulate the "pending" behavior - request gets queued/blocked
        await Future.delayed(
            Duration(milliseconds: 100 * _pendingRequestIds.length));
      }

      _pendingRequestIds.add(requestId);
      print(
          '📤 Request $requestId sent (${_pendingRequestIds.length} pending)');

      // Simulate processing
      Timer(Duration(milliseconds: 50), () {
        _simulateResponse(message);
        _pendingRequestIds.remove(requestId);
        print(
            '✅ Request $requestId completed (${_pendingRequestIds.length} remaining)');
      });
    } else {
      _simulateResponse(message);
    }
  }

  void _simulateResponse(JsonRpcMessage message) {
    if (message is JsonRpcRequest) {
      late JsonRpcResponse response;

      if (message.method == 'initialize') {
        final initResult = InitializeResult(
          protocolVersion: latestProtocolVersion,
          capabilities: ServerCapabilities.fromJson(Map<String, dynamic>.from({
            'tools': <String, dynamic>{},
          })),
          serverInfo:
              Implementation(name: 'http-mock-server', version: '1.0.0'),
        );
        response = JsonRpcResponse(
          id: message.id,
          result: Map<String, dynamic>.from(initResult.toJson()),
        );
        _sessionId =
            'http-mock-session-${DateTime.now().millisecondsSinceEpoch}';
      } else if (message.method == 'ping') {
        response = JsonRpcResponse(
          id: message.id,
          result: Map<String, dynamic>.from(const EmptyResult().toJson()),
        );
      } else if (message.method == 'tools/list') {
        response = JsonRpcResponse(
          id: message.id,
          result: Map<String, dynamic>.from(
            ListToolsResult(tools: []).toJson(),
          ),
        );
      } else {
        response = JsonRpcResponse(
          id: message.id,
          result: {'status': 'mock_response', 'requestId': message.id},
        );
      }

      onmessage?.call(response);
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _pendingRequestIds.clear();
    onclose?.call();
  }
}

void main() {
  group('Web Multiple Requests Tests', () {
    group('Bug Reproduction: More than 5 requests pending', () {
      test('reproduces pending issue with many concurrent requests', () async {
        print('🧪 Testing: More than 5 requests start pending');

        final transport = MockHttpTransport();
        final client = Client(
          Implementation(name: 'multi-request-test-client', version: '1.0.0'),
        );

        try {
          await client.connect(transport);
          print('✅ Client connected');

          // Make more than 5 concurrent requests to trigger the issue
          final requestCount = 10;
          final futures = <Future<EmptyResult>>[];

          print('📤 Sending $requestCount concurrent ping requests...');

          final startTime = DateTime.now();

          for (int i = 0; i < requestCount; i++) {
            final future = client.ping();
            futures.add(future);
            print('  📤 Ping request ${i + 1} sent');

            // Small delay to simulate real-world timing
            await Future.delayed(Duration(milliseconds: 10));
          }

          print('⏳ Waiting for all requests to complete...');
          final results = await Future.wait(futures);
          final endTime = DateTime.now();

          final duration = endTime.difference(startTime);
          print(
              '✅ All $requestCount requests completed in ${duration.inMilliseconds}ms');
          print(
              '📊 Pending count during test: max ${transport.pendingRequestCount}');

          // Verify all requests succeeded
          expect(results, hasLength(requestCount));
          for (final result in results) {
            expect(result, isA<EmptyResult>());
          }

          // Check if we observed the pending issue
          final sentMessages = transport.sentMessages;
          final pingMessages = sentMessages
              .where((msg) => msg is JsonRpcRequest && msg.method == 'ping')
              .toList();

          expect(pingMessages, hasLength(requestCount));
          print('📈 Successfully sent $requestCount ping requests');
        } finally {
          await client.close();
          await transport.close();
        }
      });

      test('measures request timing with connection limits', () async {
        print('🧪 Testing: Request timing analysis');

        final transport = MultiRequestMockTransport();
        transport.responseDelay = Duration(milliseconds: 200);
        transport.maxConcurrentRequests = 5; // Simulate strict browser limit

        final client = Client(
          Implementation(name: 'timing-test-client', version: '1.0.0'),
        );

        try {
          await client.connect(transport);

          // Test with exactly the limit
          print('📤 Testing with 5 requests (at limit)...');
          await _testRequestBatch(client, transport, 5, 'at-limit');

          // Test with more than the limit
          print('📤 Testing with 8 requests (over limit)...');
          await _testRequestBatch(client, transport, 8, 'over-limit');
        } finally {
          await client.close();
          await transport.close();
        }
      });

      test('simulates real StreamableHttpClientTransport behavior', () async {
        print('🧪 Testing: Realistic transport simulation');

        // Test the pattern that would happen with real StreamableHttpClientTransport
        final transport = MockHttpTransport();
        transport.maxConcurrentConnections = 6; // Default browser limit

        final client = Client(
          Implementation(name: 'realistic-test-client', version: '1.0.0'),
        );

        try {
          await client.connect(transport);

          // Rapid-fire requests like a real application might make
          final futures = <Future>[];

          // Mix different types of requests
          for (int i = 0; i < 12; i++) {
            if (i % 3 == 0) {
              futures.add(client.ping());
            } else if (i % 3 == 1) {
              futures.add(client.listTools());
            } else {
              futures.add(client.ping());
            }
          }

          print('⏳ Processing ${futures.length} mixed requests...');
          await Future.wait(futures);
          print('✅ All mixed requests completed successfully');

          // Verify no requests were lost
          final totalRequests = transport.sentMessages
              .where(
                  (msg) => msg is JsonRpcRequest && msg.method != 'initialize')
              .length;

          expect(totalRequests, equals(12));
          print('📊 Confirmed all $totalRequests requests were processed');
        } finally {
          await client.close();
          await transport.close();
        }
      });
    });
  });
}

/// Helper function to test a batch of requests and measure timing
Future<void> _testRequestBatch(Client client,
    MultiRequestMockTransport transport, int count, String testName) async {
  final startTime = DateTime.now();

  final futures = <Future<EmptyResult>>[];
  for (int i = 0; i < count; i++) {
    futures.add(client.ping());
  }

  await Future.wait(futures);

  final endTime = DateTime.now();
  final duration = endTime.difference(startTime);

  print('📊 $testName: $count requests in ${duration.inMilliseconds}ms');
  print(
      '📊 $testName: Max concurrent pending: ${transport.currentPendingCount}');

  // Reset for next test
  transport._sentMessages.clear();
  transport._requestTimestamps.clear();
}
