import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:mcp_dart/src/client/client.dart';
import 'package:mcp_dart/src/client/stdio.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

final _stdioRecoveryTimeout = io.Platform.isWindows
    ? const Duration(seconds: 30)
    : const Duration(seconds: 10);

void _stdioRecoveryTest(String description, Future<void> Function() body) {
  test(
    description,
    body,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

void main() {
  group('StdioClientTransport', () {
    test('can launch a child without inheriting the parent environment',
        () async {
      final inheritedEntry = io.Platform.environment.entries.firstWhere(
        (entry) => entry.key != 'MCP_DART_EXPLICIT_SENTINEL',
      );
      final parameters = StdioServerParameters(
        command: io.Platform.resolvedExecutable,
        args: [
          'test/client/fixtures/stdio_environment_probe.dart',
          inheritedEntry.key,
        ],
        environment: const {'MCP_DART_EXPLICIT_SENTINEL': 'explicit-value'},
        includeParentEnvironment: false,
        stderrMode: io.ProcessStartMode.normal,
      );
      final transport = StdioClientTransport(parameters);
      final messageReceived = Completer<JsonRpcMessage>();
      transport.onmessage = messageReceived.complete;

      await transport.start();
      final message = await messageReceived.future.timeout(
        const Duration(seconds: 10),
      );

      expect(parameters.includeParentEnvironment, isFalse);
      expect(message, isA<JsonRpcNotification>());
      expect(message.toJson()['params'], {
        'inherited': isNull,
        'explicit': 'explicit-value',
      });

      await transport.close();
    });

    test('continues after a malformed frame in the same stdout chunk',
        () async {
      final temporaryDirectory =
          await io.Directory.systemTemp.createTemp('mcp_stdio_malformed_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
            'malformed-then-valid',
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );
      final parseError = Completer<Error>();
      final validMessage = Completer<JsonRpcMessage>();
      transport
        ..onerror = (error) {
          if (!parseError.isCompleted) {
            parseError.complete(error);
          }
        }
        ..onmessage = (message) {
          if (!validMessage.isCompleted) {
            validMessage.complete(message);
          }
        };

      try {
        await transport.start();
        expect(
          await parseError.future.timeout(const Duration(seconds: 10)),
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Message parsing error'),
          ),
        );
        expect(
          await validMessage.future.timeout(const Duration(seconds: 10)),
          isA<JsonRpcNotification>().having(
            (message) => message.method,
            'method',
            'fixture/after-malformed',
          ),
        );
      } finally {
        await transport.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('throws StateError when process fails to start', () async {
      // Use a command that doesn't exist
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'nonexistent_command_that_does_not_exist_12345',
          args: ['arg1'],
        ),
      );

      expect(() => transport.start(), throwsA(isA<StateError>()));
    });

    test('throws StateError when started twice', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      await transport.start();

      expect(() => transport.start(), throwsA(isA<StateError>()));

      await transport.close();
    });

    test('rejects start until an in-progress close completes', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      await transport.start();
      final closing = transport.close();

      await expectLater(
        transport.start(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('closing'),
          ),
        ),
      );
      await closing;

      await transport.start();
      await transport.close();
    });

    test('send throws StateError when not started', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'echo',
          args: ['test'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      expect(
        () => transport.send(
          const JsonRpcNotification(method: 'test', params: {}),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('send throws StateError after close', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      await transport.start();
      await transport.close();

      expect(
        () => transport.send(
          const JsonRpcNotification(method: 'test', params: {}),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('onclose callback is called when closing', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      bool oncloseCalled = false;
      transport.onclose = () {
        oncloseCalled = true;
      };

      await transport.start();
      await transport.close();

      expect(oncloseCalled, isTrue);
    });

    test('sessionId is always null for stdio transport', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      expect(transport.sessionId, isNull);

      await transport.start();
      expect(transport.sessionId, isNull);

      await transport.close();
    });

    test('close does nothing if not started', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'echo',
          args: ['test'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      // Should not throw
      await transport.close();
    });

    test('stderr is accessible when stderrMode is normal', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      await transport.start();

      expect(transport.stderr, isNotNull);

      await transport.close();
    });

    test('stderr preserves bounded output emitted before the first listener',
        () async {
      final temporaryDirectory =
          await io.Directory.systemTemp.createTemp('mcp_stdio_early_stderr_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final ready = io.File('${launchCountFile.path}.stderr-ready');
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
            'stderr-before-first-listener',
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      try {
        await transport.start();
        for (var attempt = 0;
            attempt < 1000 && !ready.existsSync();
            attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(ready.existsSync(), isTrue);

        final lines = StreamIterator(
          transport.stderr!.transform(utf8.decoder).transform(
                const LineSplitter(),
              ),
        );
        expect(
          await lines.moveNext().timeout(const Duration(seconds: 10)),
          isTrue,
        );
        expect(lines.current, 'stderr-before-first-listener');
        await lines.cancel();
      } finally {
        await transport.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('multiple close calls are safe', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      await transport.start();
      await transport.close();
      await transport.close();
      await transport.close();

      // Should not throw
    });

    test('send writes message to process stdin', () async {
      // Use cat which echoes stdin to stdout
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'cat',
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      await transport.start();

      // Send a message - this tests that send doesn't throw
      final notification = const JsonRpcNotification(
        method: 'test',
        params: {'data': 'hello'},
      );

      // Should not throw
      await transport.send(notification);

      await transport.close();
    });

    test('onerror callback can be set', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      transport.onerror = (error) {};

      // Verify callback is registered
      expect(transport.onerror, isNotNull);

      await transport.start();
      await transport.close();
    });

    test('onmessage callback can be set', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'sleep',
          args: ['5'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      transport.onmessage = (msg) {
        // Handle message
      };

      // Verify callback is registered
      expect(transport.onmessage, isNotNull);

      await transport.start();
      await transport.close();
    });

    test(
      'restores an active subscription across repeated child exits',
      () async {
        final temporaryDirectory =
            await io.Directory.systemTemp.createTemp('mcp_stdio_restart_');
        final launchCountFile = io.File(
          '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
        );
        final transport = StdioClientTransport(
          StdioServerParameters(
            command: io.Platform.resolvedExecutable,
            args: [
              'test/client/fixtures/stdio_restart_server.dart',
              launchCountFile.path,
            ],
            stderrMode: io.ProcessStartMode.normal,
          ),
        );
        final client = McpClient(
          const Implementation(name: 'restart-test-client', version: '1.0.0'),
          options: const McpClientOptions(protocol: McpProtocol.require2026),
        );
        var closeCount = 0;
        final errors = <Error>[];
        client.onclose = () => closeCount++;
        client.onerror = errors.add;

        try {
          await client.connect(transport);
          final subscription = client.listenSubscriptions(
            const SubscriptionsListenRequest(
              notifications: SubscriptionFilter(
                resourcesListChanged: true,
              ),
            ),
          );
          final notifications = StreamIterator(subscription.notifications);
          final firstNotification = notifications.moveNext();
          await subscription.acknowledged.timeout(const Duration(seconds: 10));

          expect(
            await firstNotification.timeout(const Duration(seconds: 10)),
            isTrue,
          );
          expect(_stdioFixtureLaunchCount(launchCountFile), 1);

          final restartedNotification = notifications.moveNext();
          await client.notification(
            const JsonRpcNotification(method: 'fixture/exit'),
          );

          expect(
            await restartedNotification.timeout(const Duration(seconds: 10)),
            isTrue,
          );
          expect(_stdioFixtureLaunchCount(launchCountFile), 2);
          expect(closeCount, 0);
          expect(client.isConnected, isTrue);

          final secondRestartNotification = notifications.moveNext();
          await client.notification(
            const JsonRpcNotification(method: 'fixture/crash'),
          );
          expect(
            await secondRestartNotification.timeout(
              const Duration(seconds: 10),
            ),
            isTrue,
          );
          expect(_stdioFixtureLaunchCount(launchCountFile), 3);
          expect(errors, hasLength(2));
          expect(
            errors.every(
              (error) => error.toString().contains('in-flight requests'),
            ),
            isTrue,
          );

          final resources =
              await client.listResources().timeout(const Duration(seconds: 10));
          expect(resources.resources, isEmpty);

          subscription.cancel();
          await subscription.done.timeout(const Duration(seconds: 10));
          await notifications.cancel();
          await client.close();
          await Future<void>.delayed(const Duration(milliseconds: 300));

          expect(closeCount, 1);
          expect(_stdioFixtureLaunchCount(launchCountFile), 3);
        } finally {
          await transport.close();
          await temporaryDirectory.delete(recursive: true);
        }
      },
    );

    test('inbound notification-only activity re-arms repeated recovery',
        () async {
      final harness = await _RawRecoveryHarness.start(
        bootstrapSubscription: false,
      );
      const clientInfo = Implementation(
        name: 'notification-recovery-client',
        version: '1.0.0',
      );
      final meta = buildProtocolRequestMeta(
        protocolVersion: previewProtocolVersion,
        clientInfo: clientInfo,
        clientCapabilities: const ClientCapabilities(),
      );
      try {
        final discovery = harness._nextMessage();
        await harness.transport.send(
          JsonRpcServerDiscoverRequest(id: 1, meta: meta),
        );
        expect(await discovery, isA<JsonRpcResponse>());

        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        await harness.waitForLaunchCount(2);

        final healthyNotification = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcNotification(
            method: 'fixture/notification-only-activity',
          ),
        );
        expect(
          await healthyNotification.timeout(const Duration(seconds: 10)),
          isA<JsonRpcNotification>().having(
            (message) => message.method,
            'method',
            'fixture/healthy-notification',
          ),
        );

        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        await harness.waitForLaunchCount(3);
        expect(harness.closeCount, 0);

        final response = harness._nextMessage();
        await harness.transport.send(
          JsonRpcRequest(
            id: 2,
            method: Method.resourcesList,
            meta: meta,
          ),
        );
        expect(
          await response.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 2),
        );
      } finally {
        await harness.dispose();
      }
    });

    test('restarts when a modern discovery error precedes child exit',
        () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'modern-discovery-error-exit',
        bootstrapSubscription: false,
      );
      final meta = buildProtocolRequestMeta(
        protocolVersion: '1900-01-01',
        clientInfo: const Implementation(
          name: 'discovery-recovery-client',
          version: '1.0.0',
        ),
        clientCapabilities: const ClientCapabilities(),
      );
      try {
        final rejectedDiscovery = harness._nextMessage();
        await harness.transport.send(
          JsonRpcServerDiscoverRequest(id: 1, meta: meta),
        );
        expect(
          await rejectedDiscovery.timeout(const Duration(seconds: 10)),
          isA<JsonRpcError>().having((message) => message.id, 'id', 1).having(
                (message) => message.error.code,
                'code',
                ErrorCode.unsupportedProtocolVersion.value,
              ),
        );

        await harness.waitForLaunchCount(2);
        expect(harness.closeCount, 0);

        final retriedDiscovery = harness._nextMessage();
        await harness.transport.send(
          JsonRpcServerDiscoverRequest(
            id: 2,
            meta: buildProtocolRequestMeta(
              protocolVersion: previewProtocolVersion,
              clientInfo: const Implementation(
                name: 'discovery-recovery-client',
                version: '1.0.0',
              ),
              clientCapabilities: const ClientCapabilities(),
            ),
          ),
        );
        expect(
          await retriedDiscovery.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 2),
        );
      } finally {
        await harness.dispose();
      }
    });

    _stdioRecoveryTest(
        'settles a discovery retry lost during modern child recovery',
        () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'modern-discovery-error-exit-after-retry',
        bootstrapSubscription: false,
      );
      const clientInfo = Implementation(
        name: 'discovery-race-client',
        version: '1.0.0',
      );
      try {
        final rejectedDiscovery = harness._nextMessage();
        await harness.transport.send(
          JsonRpcServerDiscoverRequest(
            id: 1,
            meta: buildProtocolRequestMeta(
              protocolVersion: '1900-01-01',
              clientInfo: clientInfo,
              clientCapabilities: const ClientCapabilities(),
            ),
          ),
        );
        expect(
          await rejectedDiscovery.timeout(const Duration(seconds: 10)),
          isA<JsonRpcError>().having(
            (message) => message.error.code,
            'code',
            ErrorCode.unsupportedProtocolVersion.value,
          ),
        );

        final lostRetry = harness._nextMessage();
        await harness.transport.send(
          JsonRpcServerDiscoverRequest(
            id: 2,
            meta: buildProtocolRequestMeta(
              protocolVersion: previewProtocolVersion,
              clientInfo: clientInfo,
              clientCapabilities: const ClientCapabilities(),
            ),
          ),
        );
        expect(
          await lostRetry.timeout(const Duration(seconds: 10)),
          isA<JsonRpcError>().having((message) => message.id, 'id', 2).having(
                (message) => message.error.code,
                'code',
                ErrorCode.connectionClosed.value,
              ),
        );
        await harness.waitForLaunchCount(2);
        expect(harness.closeCount, 0);

        final replacementDiscovery = harness._nextMessage();
        await harness.transport.send(
          JsonRpcServerDiscoverRequest(
            id: 3,
            meta: buildProtocolRequestMeta(
              protocolVersion: previewProtocolVersion,
              clientInfo: clientInfo,
              clientCapabilities: const ClientCapabilities(),
            ),
          ),
        );
        expect(
          await replacementDiscovery.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 3),
        );
      } finally {
        await harness.dispose();
      }
    });

    test(
      'stderr is drained, stable across restart, and renewed after close',
      () async {
        final harness = await _RawRecoveryHarness.start();
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );

        Future<void> writeStderr(
          int id,
          String marker, {
          int bytes = 0,
        }) async {
          final response = harness._nextMessage();
          await harness.transport.send(
            JsonRpcRequest(
              id: id,
              method: 'fixture/stderr',
              params: {'marker': marker, 'bytes': bytes},
            ),
          );
          expect(
            await response.timeout(const Duration(seconds: 10)),
            isA<JsonRpcResponse>().having(
              (message) => message.id,
              'id',
              id,
            ),
          );
        }

        try {
          final stderrStream = harness.transport.stderr!;
          expect(stderrStream.isBroadcast, isTrue);

          // A burst larger than a typical pipe buffer must not block the
          // child. The transport preserves only a bounded suffix for the
          // normal `await start(); stderr.listen(...)` attachment pattern.
          await writeStderr(
            10,
            'buffered-before-listen',
            bytes: 1024 * 1024,
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));

          final stderrLines = StreamIterator(
            stderrStream.transform(utf8.decoder).transform(
                  const LineSplitter(),
                ),
          );
          var nextLine = stderrLines.moveNext();
          expect(
            await nextLine.timeout(const Duration(seconds: 10)),
            isTrue,
          );
          expect(stderrLines.current, endsWith('buffered-before-listen'));
          expect(stderrLines.current.length, lessThanOrEqualTo(64 * 1024));

          nextLine = stderrLines.moveNext();
          await writeStderr(11, 'before-restart');
          expect(
            await nextLine.timeout(const Duration(seconds: 10)),
            isTrue,
          );
          expect(stderrLines.current, 'before-restart');

          final restartedNotification = harness._nextMessage();
          await harness.transport.send(
            const JsonRpcNotification(method: 'fixture/crash'),
          );
          expect(
            await restartedNotification.timeout(const Duration(seconds: 10)),
            isA<JsonRpcNotification>().having(
              (message) => message.method,
              'method',
              Method.notificationsResourcesListChanged,
            ),
          );
          expect(harness.launchCount, 2);
          expect(harness.transport.stderr, same(stderrStream));

          nextLine = stderrLines.moveNext();
          await writeStderr(12, 'after-restart');
          expect(
            await nextLine.timeout(const Duration(seconds: 10)),
            isTrue,
          );
          expect(stderrLines.current, 'after-restart');

          await harness.transport.close();
          expect(harness.transport.stderr, isNull);
          expect(
            await stderrLines.moveNext().timeout(const Duration(seconds: 10)),
            isFalse,
          );
          await stderrLines.cancel();

          await harness.transport.start();
          final nextLifecycleStream = harness.transport.stderr!;
          expect(nextLifecycleStream, isNot(same(stderrStream)));
          final nextLifecycleLines = StreamIterator(
            nextLifecycleStream.transform(utf8.decoder).transform(
                  const LineSplitter(),
                ),
          );
          nextLine = nextLifecycleLines.moveNext();
          await writeStderr(13, 'after-explicit-start');
          expect(
            await nextLine.timeout(const Duration(seconds: 10)),
            isTrue,
          );
          expect(nextLifecycleLines.current, 'after-explicit-start');

          await harness.transport.close();
          expect(
            await nextLifecycleLines
                .moveNext()
                .timeout(const Duration(seconds: 10)),
            isFalse,
          );
          await nextLifecycleLines.cancel();
          expect(harness.closeCount, 2);
          expect(harness.launchCount, 3);
        } finally {
          await harness.dispose();
        }
      },
    );

    test('malformed cancellation does not disable subscription replay',
        () async {
      final harness = await _RawRecoveryHarness.start();
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );

        final malformedCancellation = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcNotification(
            method: 'fixture/malformed-cancellation',
          ),
        );
        expect(
          await malformedCancellation.timeout(const Duration(seconds: 10)),
          isA<JsonRpcCancelledNotification>()
              .having(
                (message) => message.cancelParams.requestId,
                'requestId',
                2,
              )
              .having(
                (message) => message.meta?[McpMetaKey.subscriptionId],
                'subscriptionId',
                'different-subscription',
              ),
        );

        final replayedNotification = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        expect(
          await replayedNotification.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResourceListChangedNotification>(),
        );
        expect(harness.launchCount, 2);
      } finally {
        await harness.dispose();
      }
    });

    test('recovery ignores non-filter acknowledgment metadata changes',
        () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'changed-acknowledgment-meta',
      );
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );

        final replayedNotification = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        expect(
          await replayedNotification.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResourceListChangedNotification>(),
        );
        expect(harness.launchCount, 2);
        expect(harness.closeCount, 0);

        final response = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcRequest(id: 10, method: Method.resourcesList),
        );
        expect(
          await response.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 10),
        );
      } finally {
        await harness.dispose();
      }
    });

    _stdioRecoveryTest(
        'a smaller replay acknowledgment updates one subscription without closing siblings',
        () async {
      final temporaryDirectory =
          await io.Directory.systemTemp.createTemp('mcp_stdio_subset_replay_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
            'smaller-acknowledgment',
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );
      final client = McpClient(
        const Implementation(name: 'subset-replay-client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.require2026),
      );
      final errors = <Error>[];
      client.onerror = errors.add;

      try {
        await client.connect(transport);
        final narrowed = client.listenSubscriptions(
          const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(
              resourcesListChanged: true,
              toolsListChanged: true,
            ),
          ),
        );
        final sibling = client.listenSubscriptions(
          const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(
              resourcesListChanged: true,
            ),
          ),
        );
        final narrowedNotifications = StreamIterator(narrowed.notifications);
        final siblingNotifications = StreamIterator(sibling.notifications);
        final narrowedAcknowledgmentChanges =
            StreamIterator(narrowed.acknowledgmentChanges);

        await Future.wait([
          narrowed.acknowledged,
          sibling.acknowledged,
        ]).timeout(_stdioRecoveryTimeout);
        expect(await narrowedNotifications.moveNext(), isTrue);
        expect(await siblingNotifications.moveNext(), isTrue);

        final narrowedReplay = narrowedNotifications.moveNext();
        final siblingReplay = siblingNotifications.moveNext();
        final changedAcknowledgment = narrowedAcknowledgmentChanges.moveNext();
        await client.notification(
          const JsonRpcNotification(method: 'fixture/crash'),
        );

        expect(
          await changedAcknowledgment.timeout(_stdioRecoveryTimeout),
          isTrue,
        );
        expect(
          narrowedAcknowledgmentChanges.current.notifications.toJson(),
          const {'resourcesListChanged': true},
        );

        expect(
          await narrowedReplay.timeout(_stdioRecoveryTimeout),
          isTrue,
        );
        expect(
          narrowedNotifications.current,
          isA<JsonRpcResourceListChangedNotification>(),
        );
        expect(
          await siblingReplay.timeout(_stdioRecoveryTimeout),
          isTrue,
        );
        expect(
          siblingNotifications.current,
          isA<JsonRpcResourceListChangedNotification>(),
        );
        expect(_stdioFixtureLaunchCount(launchCountFile), 2);
        expect(client.isConnected, isTrue);
        expect(
          errors.where(
            (error) => error.toString().contains('not requested'),
          ),
          isEmpty,
        );

        final resources =
            await client.listResources().timeout(_stdioRecoveryTimeout);
        expect(resources.resources, isEmpty);

        narrowed.cancel();
        sibling.cancel();
        await Future.wait([narrowed.done, sibling.done]);
        await narrowedNotifications.cancel();
        await siblingNotifications.cancel();
        await narrowedAcknowledgmentChanges.cancel();
      } finally {
        await client.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('recovery accepts reordered subscription filter acknowledgments',
        () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'reordered-acknowledgment',
        subscriptionFilter: const SubscriptionFilter(
          resourcesListChanged: true,
          resourceSubscriptions: [
            'file:///project/config.json',
            'file:///project/data.json',
          ],
          taskIds: ['task-1', 'task-2'],
        ),
      );
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );

        final replayedNotification = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        expect(
          await replayedNotification.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResourceListChangedNotification>(),
        );
        expect(harness.launchCount, 2);
        expect(harness.closeCount, 0);
      } finally {
        await harness.dispose();
      }
    });

    test(
        'a child exit after server subscription cancellation settles the '
        'pending terminal response', () async {
      final temporaryDirectory =
          await io.Directory.systemTemp.createTemp('mcp_stdio_cancel_exit_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
            'cancel-then-crash-before-terminal',
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );
      final client = McpClient(
        const Implementation(name: 'cancel-exit-client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.require2026),
      );
      client.onerror = (_) {};

      try {
        await client.connect(transport);
        final subscription = client.listenSubscriptions(
          const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(resourcesListChanged: true),
          ),
        );

        await subscription.acknowledged.timeout(const Duration(seconds: 10));
        await expectLater(
          subscription.done.timeout(const Duration(seconds: 10)),
          throwsA(
            isA<McpError>().having(
              (error) => error.code,
              'code',
              ErrorCode.connectionClosed.value,
            ),
          ),
        );
        expect(client.isConnected, isTrue);
      } finally {
        await client.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('does not replay a subscription whose stdin write failed', () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'closed-stdin-after-restart',
        bootstrapSubscription: false,
      );
      const clientInfo = Implementation(
        name: 'failed-write-client',
        version: '1.0.0',
      );
      final meta = buildProtocolRequestMeta(
        protocolVersion: previewProtocolVersion,
        clientInfo: clientInfo,
        clientCapabilities: const ClientCapabilities(),
      );
      try {
        final discovery = harness._nextMessage();
        await harness.transport.send(
          JsonRpcServerDiscoverRequest(id: 1, meta: meta),
        );
        expect(await discovery, isA<JsonRpcResponse>());

        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        await harness.waitForLaunchCount(2);
        await harness.waitForMarker('.stdin-closed');

        await expectLater(
          harness.transport.send(
            JsonRpcSubscriptionsListenRequest(
              id: 2,
              listenParams: const SubscriptionsListenRequest(
                notifications: SubscriptionFilter(
                  resourcesListChanged: true,
                ),
              ),
              meta: meta,
            ),
          ),
          throwsA(isA<StateError>()),
        );

        await harness.waitForLaunchCount(3);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(harness.closeCount, 0);
      } finally {
        await harness.dispose();
      }
    });

    test(
      'escalates termination when a broken-stdin child ignores SIGTERM',
      () => _expectBrokenStdinRecovery(
        'closed-stdin-ignore-sigterm-after-restart',
      ),
      skip: io.Platform.isWindows
          ? 'POSIX signal resistance is not available on Windows.'
          : false,
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'restarts a broken-stdin child that handles SIGTERM with exit zero',
      () => _expectBrokenStdinRecovery(
        'closed-stdin-exit-zero-on-sigterm-after-restart',
      ),
      skip: io.Platform.isWindows
          ? 'POSIX signal handling is not available on Windows.'
          : false,
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('stateless mode rejects direct JSON-RPC response writes', () async {
      final harness = await _RawRecoveryHarness.start();
      final responseMarker =
          io.File('${harness.launchCountFile.path}.response');
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );

        for (final message in <JsonRpcMessage>[
          const JsonRpcResponse(id: 999, result: {'ok': true}),
          const JsonRpcError(
            id: 999,
            error: JsonRpcErrorData(code: -32000, message: 'not sent'),
          ),
        ]) {
          await expectLater(
            harness.transport.send(message),
            throwsA(
              isA<McpError>()
                  .having(
                    (error) => error.code,
                    'code',
                    ErrorCode.invalidRequest.value,
                  )
                  .having(
                    (error) => error.message,
                    'message',
                    contains('must not send JSON-RPC responses'),
                  ),
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(responseMarker.existsSync(), isFalse);

        final response = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcRequest(id: 10, method: Method.resourcesList),
        );
        expect(
          await response.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 10),
        );
      } finally {
        await harness.dispose();
      }
    });

    test(
        'replays later subscriptions when an earlier replay completes immediately',
        () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'complete-first-replay',
      );
      final errors = <Error>[];
      final errorSubscription = harness.errors.listen(errors.add);
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );

        const clientInfo = Implementation(
          name: 'raw-recovery-client',
          version: '1.0.0',
        );
        final meta = buildProtocolRequestMeta(
          protocolVersion: '2026-07-28',
          clientInfo: clientInfo,
          clientCapabilities: const ClientCapabilities(),
        );
        final acknowledgment = harness._nextMessage();
        await harness.transport.send(
          JsonRpcSubscriptionsListenRequest(
            id: 3,
            listenParams: const SubscriptionsListenRequest(
              notifications: SubscriptionFilter(resourcesListChanged: true),
            ),
            meta: meta,
          ),
        );
        expect(
          await acknowledgment,
          isA<JsonRpcSubscriptionsAcknowledgedNotification>().having(
            (message) => message.meta?[McpMetaKey.subscriptionId],
            'subscriptionId',
            3,
          ),
        );
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>().having(
            (message) => message.meta?[McpMetaKey.subscriptionId],
            'subscriptionId',
            3,
          ),
        );

        final completedReplay = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        expect(
          await completedReplay.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 2),
        );
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>().having(
            (message) => message.meta?[McpMetaKey.subscriptionId],
            'subscriptionId',
            3,
          ),
        );
        expect(harness.launchCount, 2);
        expect(harness.closeCount, 0);
        expect(
          errors.where(
            (error) => error.toString().contains('Concurrent modification'),
          ),
          isEmpty,
        );

        final response = harness._nextMessage();
        await harness.transport.send(
          JsonRpcRequest(
            id: 4,
            method: Method.resourcesList,
            meta: meta,
          ),
        );
        expect(
          await response.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 4),
        );
      } finally {
        await errorSubscription.cancel();
        await harness.dispose();
      }
    });

    test('superseded replay failures preserve the newer child and send barrier',
        () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'superseded-replay-write-failure',
      );
      final errors = <Error>[];
      final errorSubscription = harness.errors.listen(errors.add);
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>().having(
            (message) => message.meta?[McpMetaKey.subscriptionId],
            'subscriptionId',
            2,
          ),
        );

        const clientInfo = Implementation(
          name: 'restart-generation-client',
          version: '1.0.0',
        );
        final meta = buildProtocolRequestMeta(
          protocolVersion: '2026-07-28',
          clientInfo: clientInfo,
          clientCapabilities: const ClientCapabilities(),
        );
        final secondAcknowledgment = harness._nextMessage();
        await harness.transport.send(
          JsonRpcSubscriptionsListenRequest(
            id: 3,
            listenParams: SubscriptionsListenRequest(
              notifications: SubscriptionFilter(
                resourcesListChanged: true,
                resourceSubscriptions: [
                  'file:///${'x' * (4 * 1024 * 1024)}',
                ],
              ),
            ),
            meta: meta,
          ),
        );
        expect(
          await secondAcknowledgment,
          isA<JsonRpcSubscriptionsAcknowledgedNotification>().having(
            (message) => message.meta?[McpMetaKey.subscriptionId],
            'subscriptionId',
            3,
          ),
        );
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>().having(
            (message) => message.meta?[McpMetaKey.subscriptionId],
            'subscriptionId',
            3,
          ),
        );

        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        await harness.waitForLaunchCount(3);
        await harness.transport.send(
          JsonRpcRequest(
            id: 4,
            method: 'fixture/recovery-probe',
            meta: meta,
          ),
        );

        final replayedSubscriptionIds = <Object?>{};
        JsonRpcResponse? probeResponse;
        while (replayedSubscriptionIds.length < 2 || probeResponse == null) {
          final message = await harness._nextMessage();
          if (message is JsonRpcResourceListChangedNotification) {
            replayedSubscriptionIds
                .add(message.meta?[McpMetaKey.subscriptionId]);
          } else if (message is JsonRpcResponse && message.id == 4) {
            probeResponse = message;
          }
        }

        expect(replayedSubscriptionIds, {2, 3});
        expect(
          probeResponse.result['replayedSubscriptionIds'],
          [2, 3],
        );
        expect(harness.launchCount, 3);
        expect(harness.closeCount, 0);
        expect(
          errors.where(
            (error) => error.toString().contains('Failed to restart'),
          ),
          isEmpty,
        );

        final response = harness._nextMessage();
        await harness.transport.send(
          JsonRpcRequest(
            id: 5,
            method: Method.resourcesList,
            meta: meta,
          ),
        );
        expect(
          await response.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 5),
        );
      } finally {
        await errorSubscription.cancel();
        await harness.dispose();
      }
    });

    test('does not restart an initialization-era child after exit', () async {
      final temporaryDirectory =
          await io.Directory.systemTemp.createTemp('mcp_stdio_legacy_exit_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );
      final closed = Completer<void>();
      transport.onclose = closed.complete;

      try {
        await transport.start();
        await transport.send(
          const JsonRpcRequest(
            id: 1,
            method: Method.initialize,
            params: <String, dynamic>{},
          ),
        );
        await transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );

        await closed.future.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(_stdioFixtureLaunchCount(launchCountFile), 1);
      } finally {
        await transport.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('initialization-era mode preserves direct response writes', () async {
      final temporaryDirectory = await io.Directory.systemTemp
          .createTemp('mcp_stdio_legacy_response_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final responseMarker = io.File('${launchCountFile.path}.response');
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      try {
        await transport.start();
        await transport.send(
          JsonRpcInitializeRequest(
            id: 1,
            initParams: const InitializeRequestParams(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: ClientCapabilities(),
              clientInfo: Implementation(
                name: 'legacy-response-client',
                version: '1.0.0',
              ),
            ),
          ),
        );
        await transport.send(
          const JsonRpcResponse(id: 999, result: {'ok': true}),
        );
        for (var attempt = 0;
            attempt < 100 && !responseMarker.existsSync();
            attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(responseMarker.existsSync(), isTrue);
        expect(
          jsonDecode(responseMarker.readAsStringSync()),
          containsPair('id', 999),
        );
      } finally {
        await transport.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('drops server requests on stateless stdio without replying', () async {
      final temporaryDirectory =
          await io.Directory.systemTemp.createTemp('mcp_stdio_direction_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final responseMarker = io.File('${launchCountFile.path}.response');
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
            'send-server-request',
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );
      final client = McpClient(
        const Implementation(name: 'direction-test-client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.require2026),
      );
      final violation = Completer<Error>();
      client.onerror = (error) {
        if (!violation.isCompleted &&
            error.toString().contains('must not send JSON-RPC requests')) {
          violation.complete(error);
        }
      };

      try {
        await client.connect(transport);
        await violation.future.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(responseMarker.existsSync(), isFalse);
        expect(client.isConnected, isTrue);
      } finally {
        await client.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('does not restart a stateless child that exits normally', () async {
      final temporaryDirectory =
          await io.Directory.systemTemp.createTemp('mcp_stdio_normal_exit_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );
      final client = McpClient(
        const Implementation(name: 'normal-exit-client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.require2026),
      );
      final closed = Completer<void>();
      client.onclose = closed.complete;

      try {
        await client.connect(transport);
        await client.notification(
          const JsonRpcNotification(method: 'fixture/exit'),
        );

        await closed.future.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(_stdioFixtureLaunchCount(launchCountFile), 1);
        expect(client.isConnected, isFalse);
      } finally {
        await transport.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('restarts code-zero exit with an ordinary request in flight',
        () async {
      final temporaryDirectory = await io.Directory.systemTemp
          .createTemp('mcp_stdio_request_recovery_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );
      final client = McpClient(
        const Implementation(name: 'request-recovery-client', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.require2026),
      );
      final errors = <Error>[];
      client.onerror = errors.add;

      try {
        await client.connect(transport);
        final lostRequest = client.request<EmptyResult>(
          const JsonRpcRequest(
            id: -1,
            method: 'fixture/exit-zero-request',
          ),
          EmptyResult.fromJson,
          const RequestOptions(timeoutEnabled: false),
        );

        await expectLater(
          lostRequest.timeout(const Duration(seconds: 10)),
          throwsA(
            isA<McpError>().having(
              (error) => error.code,
              'code',
              ErrorCode.connectionClosed.value,
            ),
          ),
        );
        final resources =
            await client.listResources().timeout(const Duration(seconds: 10));

        expect(resources.resources, isEmpty);
        expect(_stdioFixtureLaunchCount(launchCountFile), 2);
        expect(client.isConnected, isTrue);
        expect(
          errors.any(
            (error) => error.toString().contains('in-flight requests'),
          ),
          isTrue,
        );
      } finally {
        await client.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('drains a final response before classifying process exit', () async {
      final temporaryDirectory = await io.Directory.systemTemp
          .createTemp('mcp_stdio_final_response_exit_');
      final launchCountFile = io.File(
        '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
      );
      final transport = StdioClientTransport(
        StdioServerParameters(
          command: io.Platform.resolvedExecutable,
          args: [
            'test/client/fixtures/stdio_restart_server.dart',
            launchCountFile.path,
          ],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );
      final messages = StreamController<JsonRpcMessage>();
      final messageIterator = StreamIterator(messages.stream);
      final errors = <Error>[];
      final closed = Completer<void>();
      transport
        ..onmessage = messages.add
        ..onerror = errors.add
        ..onclose = closed.complete;

      Future<JsonRpcMessage> nextMessage() async {
        final hasMessage = await messageIterator.moveNext().timeout(
              const Duration(seconds: 10),
            );
        if (!hasMessage) {
          throw StateError('stdio transport closed before the next message');
        }
        return messageIterator.current;
      }

      try {
        await transport.start();
        const clientInfo = Implementation(
          name: 'drain-test-client',
          version: '1.0.0',
        );
        final meta = buildProtocolRequestMeta(
          protocolVersion: '2026-07-28',
          clientInfo: clientInfo,
          clientCapabilities: const ClientCapabilities(),
        );
        final discovery = nextMessage();
        await transport.send(JsonRpcServerDiscoverRequest(id: 1, meta: meta));
        expect(await discovery, isA<JsonRpcResponse>());

        final finalResponse = nextMessage();
        await transport.send(
          JsonRpcRequest(
            id: 2,
            method: 'fixture/final-response-exit',
            meta: meta,
          ),
        );
        expect(
          await finalResponse.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>()
              .having((message) => message.id, 'id', 2)
              .having(
                (message) => message.result['payload'],
                'payload',
                isA<String>().having(
                  (payload) => payload.length,
                  'length',
                  1024 * 1024,
                ),
              ),
        );
        await closed.future.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(_stdioFixtureLaunchCount(launchCountFile), 1);
        expect(
          errors.where(
            (error) => error.toString().contains('request was not replayed'),
          ),
          isEmpty,
        );
      } finally {
        await transport.close();
        await messageIterator.cancel();
        await messages.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('restartOnUnexpectedExit false closes instead of recovering',
        () async {
      final harness = await _RawRecoveryHarness.start(
        restartOnUnexpectedExit: false,
      );
      try {
        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );
        await harness.closed.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(harness.launchCount, 1);
        expect(harness.closeCount, 1);
        await harness.transport.close();
        expect(harness.closeCount, 1);
      } finally {
        await harness.dispose();
      }
    });

    test('an invalid replay acknowledgment fails only its subscription',
        () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'mismatched-acknowledgment',
      );
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );
        final failure = harness.errors.firstWhere(
          (error) => error.toString().contains('not requested'),
        );
        final subscriptionError = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );

        expect(
          await failure.timeout(const Duration(seconds: 10)),
          isA<StateError>(),
        );
        expect(
          await subscriptionError.timeout(const Duration(seconds: 10)),
          isA<JsonRpcError>().having((message) => message.id, 'id', 2),
        );
        expect(harness.launchCount, 2);
        expect(harness.closeCount, 0);

        final response = harness._nextMessage();
        await harness.transport.send(
          const JsonRpcRequest(id: 3, method: Method.resourcesList),
        );
        expect(
          await response.timeout(const Duration(seconds: 10)),
          isA<JsonRpcResponse>().having((message) => message.id, 'id', 3),
        );
      } finally {
        await harness.dispose();
      }
    });

    test('fails recovery cleanly for an event before replay acknowledgment',
        () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'event-before-acknowledgment',
      );
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );
        final failure = harness.errors.firstWhere(
          (error) => error
              .toString()
              .contains('before notifications/subscriptions/acknowledged'),
        );
        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );

        expect(
          await failure.timeout(const Duration(seconds: 10)),
          isA<StateError>(),
        );
        await harness.closed.timeout(const Duration(seconds: 10));
        expect(harness.launchCount, 2);
        expect(harness.closeCount, 1);
      } finally {
        await harness.dispose();
      }
    });

    test('bounds an acknowledge-then-crash restart loop', () async {
      final harness = await _RawRecoveryHarness.start(
        replayBehavior: 'acknowledge-then-crash-loop',
      );
      try {
        expect(
          await harness._nextMessage(),
          isA<JsonRpcResourceListChangedNotification>(),
        );
        final restartLimit = harness.errors.firstWhere(
          (error) => error.toString().contains('automatic restart limit'),
        );
        await harness.transport.send(
          const JsonRpcNotification(method: 'fixture/crash'),
        );

        expect(
          await restartLimit.timeout(const Duration(seconds: 10)),
          isA<StateError>(),
        );
        await harness.closed.timeout(const Duration(seconds: 10));
        expect(harness.launchCount, 6);
        expect(harness.closeCount, 1);
      } finally {
        await harness.dispose();
      }
    });
  });
}

Future<void> _expectBrokenStdinRecovery(String replayBehavior) async {
  final harness = await _RawRecoveryHarness.start(
    replayBehavior: replayBehavior,
    bootstrapSubscription: false,
  );
  const clientInfo = Implementation(
    name: 'broken-stdin-recovery-client',
    version: '1.0.0',
  );
  final meta = buildProtocolRequestMeta(
    protocolVersion: previewProtocolVersion,
    clientInfo: clientInfo,
    clientCapabilities: const ClientCapabilities(),
  );
  try {
    final discovery = harness._nextMessage();
    await harness.transport.send(
      JsonRpcServerDiscoverRequest(id: 1, meta: meta),
    );
    expect(await discovery, isA<JsonRpcResponse>());

    await harness.transport.send(
      const JsonRpcNotification(method: 'fixture/crash'),
    );
    await harness.waitForLaunchCount(2);
    await harness.waitForMarker('.stdin-closed');

    await expectLater(
      harness.transport.send(
        JsonRpcSubscriptionsListenRequest(
          id: 2,
          listenParams: const SubscriptionsListenRequest(
            notifications: SubscriptionFilter(
              resourcesListChanged: true,
            ),
          ),
          meta: meta,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    await harness.waitForLaunchCount(3);
    final response = harness._nextMessage();
    await harness.transport.send(
      JsonRpcRequest(
        id: 3,
        method: Method.resourcesList,
        meta: meta,
      ),
    );
    expect(
      await response.timeout(_stdioRecoveryTimeout),
      isA<JsonRpcResponse>().having((message) => message.id, 'id', 3),
    );
    expect(harness.closeCount, 0);
  } finally {
    await harness.dispose();
  }
}

class _RawRecoveryHarness {
  final io.Directory temporaryDirectory;
  final io.File launchCountFile;
  final StdioClientTransport transport;
  final StreamController<JsonRpcMessage> _messages;
  final StreamController<Error> _errors;
  final StreamIterator<JsonRpcMessage> _messageIterator;
  final Completer<void> _closed;
  int closeCount = 0;

  _RawRecoveryHarness._({
    required this.temporaryDirectory,
    required this.launchCountFile,
    required this.transport,
    required StreamController<JsonRpcMessage> messages,
    required StreamController<Error> errors,
    required StreamIterator<JsonRpcMessage> messageIterator,
    required Completer<void> closed,
  })  : _messages = messages,
        _errors = errors,
        _messageIterator = messageIterator,
        _closed = closed;

  static Future<_RawRecoveryHarness> start({
    bool restartOnUnexpectedExit = true,
    String replayBehavior = 'acknowledge-first',
    bool bootstrapSubscription = true,
    SubscriptionFilter subscriptionFilter = const SubscriptionFilter(
      resourcesListChanged: true,
    ),
  }) async {
    final temporaryDirectory =
        await io.Directory.systemTemp.createTemp('mcp_stdio_raw_recovery_');
    final launchCountFile = io.File(
      '${temporaryDirectory.path}${io.Platform.pathSeparator}launch-count',
    );
    final parameters = StdioServerParameters(
      command: io.Platform.resolvedExecutable,
      args: [
        'test/client/fixtures/stdio_restart_server.dart',
        launchCountFile.path,
        replayBehavior,
      ],
      stderrMode: io.ProcessStartMode.normal,
      restartOnUnexpectedExit: restartOnUnexpectedExit,
    );
    final transport = StdioClientTransport(parameters);
    final messages = StreamController<JsonRpcMessage>();
    final errors = StreamController<Error>.broadcast();
    final messageIterator = StreamIterator(messages.stream);
    final closed = Completer<void>();
    final harness = _RawRecoveryHarness._(
      temporaryDirectory: temporaryDirectory,
      launchCountFile: launchCountFile,
      transport: transport,
      messages: messages,
      errors: errors,
      messageIterator: messageIterator,
      closed: closed,
    );
    transport.onmessage = messages.add;
    transport.onerror = errors.add;
    transport.onclose = () {
      harness.closeCount++;
      if (!closed.isCompleted) {
        closed.complete();
      }
    };

    await transport.start();
    if (!bootstrapSubscription) {
      return harness;
    }

    const clientInfo = Implementation(
      name: 'raw-recovery-client',
      version: '1.0.0',
    );
    final meta = buildProtocolRequestMeta(
      protocolVersion: '2026-07-28',
      clientInfo: clientInfo,
      clientCapabilities: const ClientCapabilities(),
    );
    final discovery = harness._nextMessage();
    await transport.send(JsonRpcServerDiscoverRequest(id: 1, meta: meta));
    expect(await discovery, isA<JsonRpcResponse>());

    final acknowledgment = harness._nextMessage();
    await transport.send(
      JsonRpcSubscriptionsListenRequest(
        id: 2,
        listenParams: SubscriptionsListenRequest(
          notifications: subscriptionFilter,
        ),
        meta: meta,
      ),
    );
    expect(
      await acknowledgment,
      isA<JsonRpcSubscriptionsAcknowledgedNotification>(),
    );
    expect(harness.launchCount, 1);
    return harness;
  }

  Future<JsonRpcMessage> _nextMessage() async {
    final hasMessage =
        await _messageIterator.moveNext().timeout(const Duration(seconds: 10));
    if (!hasMessage) {
      throw StateError('stdio recovery fixture closed before the next message');
    }
    return _messageIterator.current;
  }

  Future<void> get closed => _closed.future;

  Stream<Error> get errors => _errors.stream;

  int get launchCount => _stdioFixtureLaunchCount(launchCountFile);

  Future<void> waitForLaunchCount(int expected) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < _stdioRecoveryTimeout) {
      if (launchCount >= expected) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError(
      'Expected at least $expected stdio fixture launches, got $launchCount.',
    );
  }

  Future<void> waitForMarker(String suffix) async {
    final marker = io.File('${launchCountFile.path}$suffix');
    for (var attempt = 0; attempt < 1000; attempt++) {
      if (marker.existsSync()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Expected stdio fixture marker ${marker.path}.');
  }

  Future<void> dispose() async {
    await transport.close();
    await _messageIterator.cancel();
    await _messages.close();
    await _errors.close();
    await temporaryDirectory.delete(recursive: true);
  }
}

int _stdioFixtureLaunchCount(io.File markerPrefix) {
  final pathPrefix = '${markerPrefix.path}.launch-';
  return markerPrefix.parent
      .listSync(followLinks: false)
      .whereType<io.File>()
      .where((file) {
    if (!file.path.startsWith(pathPrefix)) {
      return false;
    }
    return int.tryParse(file.path.substring(pathPrefix.length)) != null;
  }).length;
}
