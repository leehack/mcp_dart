import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  for (final throwFromErrorCallback in [false, true]) {
    test(
      'fatal overflow stops delivery with a blocked write '
      '(throwing callback: $throwFromErrorCallback)',
      () async {
        final temporaryDirectory =
            await Directory.systemTemp.createTemp('mcp_stdio_overflow_close_');
        final markerPrefix = '${temporaryDirectory.path}/fixture';
        final transport = StdioClientTransport(
          StdioServerParameters(
            command: Platform.resolvedExecutable,
            args: [
              'test/client/fixtures/stdio_overflow_shutdown_server.dart',
              markerPrefix,
            ],
            stderrMode: ProcessStartMode.normal,
            maxIncomingMessageBytes: 1024,
            // Leave automatic recovery enabled to verify overflow is fatal.
          ),
        );
        var discovery = Completer<void>();
        var closed = Completer<void>();
        var closeCount = 0;
        var overflowCount = 0;
        final messagesAfterOverflow = <JsonRpcMessage>[];
        final callbackStartRejected = Completer<bool>();
        Future<void>? writing;
        transport
          ..onmessage = (message) {
            if (overflowCount > 0) messagesAfterOverflow.add(message);
            if (message is JsonRpcResponse && message.id == 1) {
              discovery.complete();
            }
          }
          ..onerror = (error) {
            if (error is! StateError ||
                !error.message.toString().contains('limit of 1024 bytes')) {
              return;
            }
            overflowCount++;
            File('$markerPrefix.overflow-observed').writeAsStringSync('seen');
            if (!callbackStartRejected.isCompleted) {
              unawaited(
                transport.start().then(
                      (_) => callbackStartRejected.complete(false),
                      onError: (Object error) =>
                          callbackStartRejected.complete(error is StateError),
                    ),
              );
            }
            if (throwFromErrorCallback) {
              throw StateError('intentional error callback failure');
            }
          }
          ..onclose = () {
            closeCount++;
            if (!closed.isCompleted) closed.complete();
          };

        try {
          await transport.start();
          await transport.send(
            const JsonRpcRequest(id: 1, method: 'server/discover'),
          );
          await discovery.future.timeout(const Duration(seconds: 15));
          var writeCompleted = false;
          writing = transport
              .send(
                JsonRpcRequest(
                  id: 99,
                  method: 'ping',
                  params: {'padding': 'x' * (2 * 1024 * 1024)},
                ),
              )
              .catchError((Object _) {})
              .whenComplete(() => writeCompleted = true);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(
            writeCompleted,
            isFalse,
            reason: 'stdin must be backpressured',
          );
          File('$markerPrefix.overflow').writeAsStringSync('send');

          await closed.future.timeout(const Duration(seconds: 15));
          await writing.timeout(const Duration(seconds: 5));
          expect(
            File('$markerPrefix.sent-after-overflow').existsSync(),
            isTrue,
          );
          expect(messagesAfterOverflow, isEmpty);
          expect(overflowCount, 1);
          expect(await callbackStartRejected.future, isTrue);
          expect(closeCount, 1);
          expect(File('$markerPrefix.launches').readAsStringSync(), '1');
          await expectLater(
            transport.send(const JsonRpcPingRequest(id: 100)),
            throwsStateError,
          );

          // The fatal-input latch must reset only for a new explicit lifecycle.
          overflowCount = 0;
          discovery = Completer<void>();
          closed = Completer<void>();
          await transport.start();
          await discovery.future.timeout(const Duration(seconds: 15));
          await transport.close();
          expect(closeCount, 2);
          expect(File('$markerPrefix.launches').readAsStringSync(), '2');
        } finally {
          await transport.close();
          await writing?.timeout(const Duration(seconds: 5));
          await temporaryDirectory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}
