import 'dart:io' as io;

import 'package:mcp_dart/src/client/stdio.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('StdioClientTransport', () {
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
  });
}
