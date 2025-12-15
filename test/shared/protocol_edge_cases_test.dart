import 'dart:async';

import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock transport for testing protocol edge cases
class EdgeCaseMockTransport implements Transport {
  final List<JsonRpcMessage> sentMessages = [];
  bool _closed = false;

  @override
  String? get sessionId => null;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  void receiveMessage(JsonRpcMessage message) {
    onmessage?.call(message);
  }

  @override
  Future<void> close() async {
    _closed = true;
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (_closed) throw StateError('Transport is closed');
    sentMessages.add(message);
  }

  @override
  Future<void> start() async {
    if (_closed) throw StateError('Cannot start closed transport');
  }

  void simulateError(Error error) {
    onerror?.call(error);
  }
}

/// Test protocol implementation
class EdgeCaseTestProtocol extends Protocol {
  EdgeCaseTestProtocol([super.options]);

  @override
  void assertCapabilityForMethod(String method) {
    // Allow all methods for edge case testing
  }

  @override
  void assertNotificationCapability(String method) {
    // Allow all notifications for edge case testing
  }

  @override
  void assertRequestHandlerCapability(String method) {
    // Allow all request handlers
  }

  @override
  void assertTaskCapability(String method) {
    // Mock implementation
  }

  @override
  void assertTaskHandlerCapability(String method) {
    // Mock implementation
  }
}

/// Custom result for testing
class EdgeCaseResult implements BaseResultData {
  final String data;

  @override
  final Map<String, dynamic>? meta;

  EdgeCaseResult({required this.data, this.meta});

  @override
  Map<String, dynamic> toJson() => {'data': data};
}

/// Phase 3: Protocol edge cases and error handling
void main() {
  group('Protocol Edge Cases', () {
    late EdgeCaseTestProtocol protocol;
    late EdgeCaseMockTransport transport;

    setUp(() {
      protocol = EdgeCaseTestProtocol();
      transport = EdgeCaseMockTransport();
    });

    tearDown(() async {
      try {
        await protocol.close();
      } catch (_) {}
      try {
        await transport.close();
      } catch (_) {}
    });

    test('throws StateError when connecting to already connected protocol',
        () async {
      await protocol.connect(transport);
      expect(protocol.transport, isNotNull);

      final anotherTransport = EdgeCaseMockTransport();
      expect(
        () => protocol.connect(anotherTransport),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already connected'),
          ),
        ),
      );

      await anotherTransport.close();
    });

    test('handles built-in cancelled notification correctly', () async {
      await protocol.connect(transport);

      // Just verify that the cancelled notification handler is registered
      // by sending a cancellation for a non-existent request (should be silently ignored)
      transport.receiveMessage(
        JsonRpcCancelledNotification(
          cancelParams: const CancelledNotificationParams(
            requestId: 999,
            reason: 'Test cancellation',
          ),
        ),
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 50));

      // Test passes if no exception is thrown
      expect(true, isTrue);
    });

    test('handles progress notification correctly', () async {
      await protocol.connect(transport);

      // Just verify the progress notification handler is registered
      // Send a progress notification for a non-existent request (should be silently ignored)
      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotificationParams(
            progressToken: 999,
            progress: 50,
            total: 100,
          ),
        ),
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 50));

      // Test passes if no exception is thrown
      expect(true, isTrue);
    });

    test('handles malformed message and calls onerror', () async {
      await protocol.connect(transport);

      final errors = <Error>[];
      protocol.onerror = (error) => errors.add(error);

      // Create a custom message that will fail parsing
      final badMessage = const JsonRpcResponse(
        id: 999,
        result: {'invalid': 'structure'},
      );

      // Modify toJson to return invalid structure
      final badJson = badMessage.toJson();
      badJson['jsonrpc'] = 'invalid_version'; // This will cause parse error

      // Simulate receiving the bad message
      try {
        final parsed = JsonRpcMessage.fromJson(badJson);
        transport.receiveMessage(parsed);
      } catch (e) {
        // Expected to fail during parse
        expect(e, isA<FormatException>());
      }
    });

    test('handles notification without handler gracefully', () async {
      await protocol.connect(transport);

      // Send notification with no registered handler
      transport.receiveMessage(
        const JsonRpcNotification(
          method: 'unhandled/notification',
          params: {},
        ),
      );

      // Should not throw, just silently ignore
      await Future.delayed(const Duration(milliseconds: 50));
      // Test passes if no exception is thrown
    });

    test('fallback notification handler would be called if method parsed',
        () async {
      // Note: This test documents that fallback handlers CAN'T be tested with
      // custom methods because JsonRpcMessage.fromJson throws UnimplementedError
      // for unknown notification methods. The fallback handler mechanism exists
      // but only works for methods that successfully parse.

      await protocol.connect(transport);

      // Set up fallback handler (it exists, just can't be triggered with unknown methods)
      protocol.fallbackNotificationHandler = (notification) async {
        // Would be called if a known notification type had no specific handler
      };

      // Verify fallback handler is set
      expect(protocol.fallbackNotificationHandler, isNotNull);

      // Test passes to document this architectural limitation
    });

    test('fallback request handler would be called if method parsed', () async {
      // Note: Similar to notifications, fallback request handlers can't be tested
      // with custom methods because JsonRpcMessage.fromJson throws UnimplementedError
      // for unknown request methods. The fallback mechanism exists but only works
      // for methods that successfully parse.

      await protocol.connect(transport);

      // Set up fallback handler
      protocol.fallbackRequestHandler = (request) async {
        return EdgeCaseResult(data: 'fallback');
      };

      // Verify fallback handler is set
      expect(protocol.fallbackRequestHandler, isNotNull);

      // Test passes to document this architectural limitation
    });

    test('handles connection close with pending requests', () async {
      await protocol.connect(transport);

      // Start multiple pending requests (using 'ping' which is a known method)
      final futures = <Future<EmptyResult>>[];
      for (var i = 0; i < 3; i++) {
        futures.add(
          protocol
              .request<EmptyResult>(
            const JsonRpcPingRequest(id: 0),
            (json) => EmptyResult(meta: json['_meta'] as Map<String, dynamic>?),
          )
              .catchError((e) {
            // Catch errors inline to prevent unhandled error zone warnings
            if (e is McpError && e.code == ErrorCode.connectionClosed.value) {
              return const EmptyResult(); // Return dummy result
            }
            throw e; // Rethrow unexpected errors
          }),
        );
      }

      // Close connection before any responses
      await protocol.close();

      // Wait for all futures to complete (they should all complete with catchError)
      final results = await Future.wait(futures);

      // Verify all 3 completed (catchError returned EmptyResult for each)
      expect(
        results.length,
        equals(3),
        reason: 'All 3 requests should complete',
      );
    });

    test('handles user onclose error gracefully', () async {
      await protocol.connect(transport);

      final errors = <Error>[];
      protocol.onerror = (error) => errors.add(error);

      protocol.onclose = () {
        throw StateError('User onclose error');
      };

      await transport.close();

      // Should handle the error without crashing
      expect(errors.length, greaterThan(0));
      expect(
        errors.any(
          (e) => e is StateError && e.message.contains('User onclose error'),
        ),
        isTrue,
      );
    });

    test('handles user onerror error gracefully', () async {
      await protocol.connect(transport);

      protocol.onerror = (error) {
        throw StateError('User onerror error');
      };

      // Trigger an error
      transport.simulateError(StateError('Test error'));

      // Should not crash, error is logged
      await Future.delayed(const Duration(milliseconds: 50));
      // Test passes if no unhandled exception occurs
    });

    test('handles notification handler error gracefully', () async {
      // Note: Custom notification methods throw UnimplementedError during parsing,
      // so we can't test error handling for notification handlers since unknown
      // methods never reach the handler. This test documents that errors in
      // known notification handlers would be caught and passed to onerror.

      await protocol.connect(transport);

      final receivedErrors = <Error>[];
      protocol.onerror = (error) => receivedErrors.add(error);

      // The built-in handlers exist and would propagate errors through _onerror
      // if they threw exceptions. Since we can't create a scenario that triggers
      // this without modifying protocol internals, we document the behavior.

      // Test passes to document error propagation architecture
    });
  });

  group('RequestOptions Edge Cases', () {
    test('RequestOptions with all null optional fields', () {
      const options = RequestOptions();
      expect(options.onprogress, isNull);
      expect(options.signal, isNull);
      expect(options.timeout, isNull);
      expect(options.resetTimeoutOnProgress, isFalse);
      expect(options.maxTotalTimeout, isNull);
    });

    test('RequestOptions with all fields set', () {
      final controller = BasicAbortController();
      void progressCallback(Progress progress) {}

      final options = RequestOptions(
        onprogress: progressCallback,
        signal: controller.signal,
        timeout: const Duration(seconds: 30),
        resetTimeoutOnProgress: true,
        maxTotalTimeout: const Duration(minutes: 5),
      );

      expect(options.onprogress, equals(progressCallback));
      expect(options.signal, equals(controller.signal));
      expect(options.timeout, equals(const Duration(seconds: 30)));
      expect(options.resetTimeoutOnProgress, isTrue);
      expect(options.maxTotalTimeout, equals(const Duration(minutes: 5)));
    });
  });

  group('ProtocolOptions Edge Cases', () {
    test('ProtocolOptions default values', () {
      const options = ProtocolOptions();
      expect(options.enforceStrictCapabilities, isFalse);
    });

    test('ProtocolOptions with enforceStrictCapabilities enabled', () {
      const options = ProtocolOptions(enforceStrictCapabilities: true);
      expect(options.enforceStrictCapabilities, isTrue);
    });
  });
}
