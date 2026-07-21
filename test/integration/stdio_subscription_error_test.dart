import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('stdio subscription exposes a handler error through done', () async {
    await _expectSubscriptionFailure(
      code: ErrorCode.invalidRequest.value,
      message: 'subscription failed',
    );
  });

  test('stdio subscription exposes a serialization error through done',
      () async {
    await _expectSubscriptionFailure(
      fixtureArguments: const ['--serialization-error'],
      code: ErrorCode.internalError.value,
      message: 'Internal server error processing ${Method.subscriptionsListen}',
    );
  });
}

Future<void> _expectSubscriptionFailure({
  List<String> fixtureArguments = const [],
  required int code,
  required String message,
}) async {
  final transport = StdioClientTransport(
    StdioServerParameters(
      command: Platform.resolvedExecutable,
      args: [
        'test/client/fixtures/stdio_subscription_error_server.dart',
        ...fixtureArguments,
      ],
      stderrMode: ProcessStartMode.normal,
    ),
  );
  final client = McpClient(
    const Implementation(
      name: 'stdio-subscription-error-client',
      version: '1.0.0',
    ),
    options: const McpClientOptions(protocol: McpProtocol.require2026),
  );
  StreamSubscription<JsonRpcNotification>? notificationSubscription;

  try {
    await client.connect(transport);
    final subscription = client.listenSubscriptions(
      const SubscriptionsListenRequest(
        notifications: SubscriptionFilter(toolsListChanged: true),
      ),
    );
    notificationSubscription = subscription.notifications.listen(
      null,
      onError: (_) {},
    );

    await subscription.acknowledged.timeout(const Duration(seconds: 10));
    await expectLater(
      subscription.done.timeout(const Duration(seconds: 10)),
      throwsA(
        isA<McpError>()
            .having(
              (error) => error.code,
              'code',
              code,
            )
            .having(
              (error) => error.message,
              'message',
              message,
            ),
      ),
    );
  } finally {
    await client.close();
    await notificationSubscription?.cancel();
  }
}
