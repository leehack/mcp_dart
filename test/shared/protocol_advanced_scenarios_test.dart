import 'dart:async';

import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock transport for testing protocol advanced scenarios
class AdvancedScenarioMockTransport implements Transport {
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
}

/// Test protocol implementation for advanced scenarios
class AdvancedScenarioTestProtocol extends Protocol {
  AdvancedScenarioTestProtocol([super.options]);

  @override
  void assertCapabilityForMethod(String method) {
    // Allow all methods for testing
  }

  @override
  void assertNotificationCapability(String method) {
    // Allow all notifications for testing
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

/// Advanced protocol scenarios
void main() {
  group('Protocol Advanced Scenarios', () {
    late AdvancedScenarioTestProtocol protocol;
    late AdvancedScenarioMockTransport transport;

    setUp(() {
      protocol = AdvancedScenarioTestProtocol();
      transport = AdvancedScenarioMockTransport();
    });

    tearDown(() async {
      try {
        await protocol.close();
      } catch (_) {}
      try {
        await transport.close();
      } catch (_) {}
    });

    test('progress notification with invalid progressToken calls onerror',
        () async {
      await protocol.connect(transport);

      final errors = <Error>[];
      protocol.onerror = (error) => errors.add(error);

      // Send progress notification with string progressToken (should be int)
      transport.receiveMessage(
        JsonRpcProgressNotification(
          progressParams: const ProgressNotificationParams(
            progressToken: 'invalid-token' as dynamic,
            progress: 50,
            total: 100,
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Should have received an error
      expect(errors.length, greaterThan(0));
      expect(errors.first, isA<ArgumentError>());
    });

    test('request with timeout times out correctly', () async {
      await protocol.connect(transport);

      var timeoutCallbackCalled = false;
      final timeoutDuration = const Duration(milliseconds: 100);

      // Send a request with timeout - it will timeout since we never send a response
      try {
        await protocol.request<EmptyResult>(
          const JsonRpcPingRequest(id: 0),
          (json) => EmptyResult(meta: json['_meta'] as Map<String, dynamic>?),
          RequestOptions(
            timeout: timeoutDuration,
          ),
        );
        fail('Request should have timed out');
      } catch (e) {
        if (e is McpError && e.code == ErrorCode.requestTimeout.value) {
          timeoutCallbackCalled = true;
        } else {
          rethrow;
        }
      }

      // Should have timed out
      expect(timeoutCallbackCalled, isTrue);
    });

    test('abort signal cancels pending request', () async {
      await protocol.connect(transport);

      final controller = BasicAbortController();
      var requestAborted = false;

      // Send a request with abort signal
      protocol
          .request<EmptyResult>(
        const JsonRpcPingRequest(id: 0),
        (json) => EmptyResult(meta: json['_meta'] as Map<String, dynamic>?),
        RequestOptions(
          signal: controller.signal,
        ),
      )
          .catchError((e) {
        requestAborted = true;
        return const EmptyResult();
      });

      // Wait a moment, then abort
      await Future.delayed(const Duration(milliseconds: 50));
      controller.abort('Test abort');

      // Wait for the abortion to be processed
      await Future.delayed(const Duration(milliseconds: 100));

      // Should have been aborted
      expect(requestAborted, isTrue);
    });
  });
}
