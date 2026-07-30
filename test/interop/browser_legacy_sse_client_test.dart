@TestOn('browser')
@Tags(['interop'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

const _fixtureBaseUrl = 'http://127.0.0.1:8766';

void main() {
  test(
    'legacy SSE client exchanges messages and cancels its stream in Chrome',
    () async {
      final inboundMessage = Completer<JsonRpcMessage>();
      final closed = Completer<void>();
      final errors = <Error>[];
      final transport = SseClientTransport(
        Uri.parse('$_fixtureBaseUrl/sse'),
      )
        ..protocolVersion = latestInitializationProtocolVersion
        ..onmessage = (message) {
          if (!inboundMessage.isCompleted) {
            inboundMessage.complete(message);
          }
        }
        ..onerror = errors.add
        ..onclose = () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        };

      try {
        await transport.start().timeout(const Duration(seconds: 15));
        expect(transport.sessionId, 'browser-session-1');

        await transport
            .send(
              const JsonRpcRequest(
                id: 'browser-request-1',
                method: 'browser/echo',
                params: {'value': 'from Chrome'},
              ),
            )
            .timeout(const Duration(seconds: 10));

        final message =
            await inboundMessage.future.timeout(const Duration(seconds: 10));
        expect(message, isA<JsonRpcResponse>());
        final response = message as JsonRpcResponse;
        expect(response.id, 'browser-request-1');
        expect(response.result, {
          'receivedMethod': 'browser/echo',
          'receivedParams': {'value': 'from Chrome'},
        });

        final connectedStatus = await _waitForStatus(
          (status) => status['posts'] == 1 && status['activeConnections'] == 1,
        );
        expect(connectedStatus['connections'], 1);
        expect(connectedStatus['disconnects'], 0);
        expect(connectedStatus['lastRequest'], {
          'jsonrpc': '2.0',
          'id': 'browser-request-1',
          'method': 'browser/echo',
          'params': {'value': 'from Chrome'},
        });

        await transport.close().timeout(const Duration(seconds: 10));
        await closed.future.timeout(const Duration(seconds: 5));

        final closedStatus = await _waitForStatus(
          (status) =>
              status['activeConnections'] == 0 &&
              (status['disconnects'] as num) >= 1,
        );
        expect(closedStatus['posts'], 1);
        expect(errors, isEmpty);
      } finally {
        await transport.close();
      }
    },
  );
}

Future<Map<String, dynamic>> _waitForStatus(
  bool Function(Map<String, dynamic> status) predicate,
) async {
  const timeout = Duration(seconds: 10);
  final deadline = DateTime.now().add(timeout);
  Object? lastObservation;
  var attempt = 0;

  while (DateTime.now().isBefore(deadline)) {
    try {
      final uri = Uri.parse('$_fixtureBaseUrl/status').replace(
        queryParameters: {'attempt': '${attempt++}'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          lastObservation = decoded;
          if (predicate(decoded)) {
            return decoded;
          }
        } else {
          lastObservation = 'Unexpected status body: ${response.body}';
        }
      } else {
        lastObservation = 'HTTP ${response.statusCode}: ${response.body}';
      }
    } on Object catch (error) {
      lastObservation = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  throw TimeoutException(
    'Timed out waiting for legacy SSE fixture status. '
    'Last observation: $lastObservation',
    timeout,
  );
}
