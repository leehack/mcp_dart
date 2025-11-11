import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:mcp_dart/src/server/stdio.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

/// Mock stdin stream for testing
class MockStdin extends Stream<List<int>> implements io.Stdin {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Add data to the mock stdin stream
  void addData(List<int> data) {
    _controller.add(data);
  }

  /// Add string data as UTF-8 bytes
  void addString(String data) {
    _controller.add(utf8.encode(data));
  }

  /// Add error to the stream
  void addError(Object error) {
    _controller.addError(error);
  }

  /// Close the stream
  void closeStream() {
    _controller.close();
  }

  @override
  bool get echoMode => true;

  @override
  set echoMode(bool enabled) {}

  @override
  bool get lineMode => true;

  @override
  set lineMode(bool enabled) {}

  @override
  int readByteSync() => throw UnimplementedError();

  @override
  String? readLineSync(
          {Encoding encoding = utf8,
          bool retainNewlines = false}) =>
      throw UnimplementedError();

  @override
  bool get echoNewlineMode => true;

  @override
  set echoNewlineMode(bool enabled) {}

  @override
  bool get supportsAnsiEscapes => false;

  @override
  bool get hasTerminal => false;
}

/// Mock stdout sink for testing
class MockStdout implements io.IOSink {
  final List<String> writtenData = [];
  bool _closed = false;

  @override
  void write(Object? object) {
    if (_closed) {
      throw StateError('IOSink is closed');
    }
    writtenData.add(object.toString());
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  @override
  Future<void> flush() async {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    write('$object\n');
  }

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding encoding) {}

  @override
  void add(List<int> data) {
    write(utf8.decode(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future get done => Future.value();
}

void main() {
  group('StdioServerTransport - Lifecycle', () {
    late MockStdin stdin;
    late MockStdout stdout;
    late StdioServerTransport transport;

    setUp(() {
      stdin = MockStdin();
      stdout = MockStdout();
      transport = StdioServerTransport(stdin: stdin, stdout: stdout);
    });

    tearDown(() async {
      await transport.close();
    });

    test('starts successfully and sets started flag', () async {
      expect(transport.sessionId, isNull);

      await transport.start();

      // Should not throw - transport is now listening
      expect(() => transport.start(),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('already started'))));
    });

    test('throws StateError when starting twice', () async {
      await transport.start();

      expect(
        () => transport.start(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('already started'))),
      );
    });

    test('closes successfully and calls onclose', () async {
      var oncloseCalled = false;
      transport.onclose = () {
        oncloseCalled = true;
      };

      await transport.start();
      await transport.close();

      expect(oncloseCalled, isTrue);
    });

    test('can close multiple times without error', () async {
      await transport.start();
      await transport.close();
      await transport.close(); // Should not throw

      expect(() => transport.close(), returnsNormally);
    });
  });

  group('StdioServerTransport - Message Receiving', () {
    late MockStdin stdin;
    late MockStdout stdout;
    late StdioServerTransport transport;

    setUp(() {
      stdin = MockStdin();
      stdout = MockStdout();
      transport = StdioServerTransport(stdin: stdin, stdout: stdout);
    });

    tearDown(() async {
      await transport.close();
    });

    test('receives and parses valid JSON-RPC message', () async {
      JsonRpcMessage? receivedMessage;
      transport.onmessage = (message) {
        receivedMessage = message;
      };

      await transport.start();

      final initRequest = JsonRpcInitializeRequest(
        id: 1,
        initParams: InitializeRequestParams(
          protocolVersion: latestProtocolVersion,
          capabilities: const ClientCapabilities(),
          clientInfo: Implementation(name: 'TestClient', version: '1.0.0'),
        ),
      );

      final jsonString = jsonEncode(initRequest.toJson());
      stdin.addString('$jsonString\n');

      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedMessage, isNotNull);
      expect(receivedMessage, isA<JsonRpcInitializeRequest>());
      expect((receivedMessage as JsonRpcInitializeRequest).id, equals(1));
    });

    test('handles multiple messages in sequence', () async {
      final receivedMessages = <JsonRpcMessage>[];
      transport.onmessage = (message) {
        receivedMessages.add(message);
      };

      await transport.start();

      final message1 = JsonRpcPingRequest(id: 1);
      final message2 = JsonRpcPingRequest(id: 2);

      stdin.addString('${jsonEncode(message1.toJson())}\n');
      stdin.addString('${jsonEncode(message2.toJson())}\n');

      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedMessages.length, equals(2));
      expect((receivedMessages[0] as JsonRpcPingRequest).id, equals(1));
      expect((receivedMessages[1] as JsonRpcPingRequest).id, equals(2));
    });

    test('handles chunked message data', () async {
      JsonRpcMessage? receivedMessage;
      transport.onmessage = (message) {
        receivedMessage = message;
      };

      await transport.start();

      final message = JsonRpcPingRequest(id: 1);
      final jsonString = jsonEncode(message.toJson());
      final fullMessage = '$jsonString\n';

      // Send message in chunks
      final chunk1 = fullMessage.substring(0, fullMessage.length ~/ 2);
      final chunk2 = fullMessage.substring(fullMessage.length ~/ 2);

      stdin.addString(chunk1);
      await Future.delayed(Duration(milliseconds: 10));
      stdin.addString(chunk2);

      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedMessage, isNotNull);
      expect(receivedMessage, isA<JsonRpcPingRequest>());
    });

    test('calls onerror on malformed JSON', () async {
      Error? receivedError;
      transport.onerror = (error) {
        receivedError = error;
      };

      await transport.start();

      stdin.addString('invalid json\n');

      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedError, isNotNull);
    });

    test('calls onclose when stdin closes', () async {
      var oncloseCalled = false;
      transport.onclose = () {
        oncloseCalled = true;
      };

      await transport.start();

      stdin.closeStream();

      await Future.delayed(Duration(milliseconds: 50));

      expect(oncloseCalled, isTrue);
    });

    test('calls onerror when stdin stream has error', () async {
      Error? receivedError;
      transport.onerror = (error) {
        receivedError = error;
      };

      await transport.start();

      stdin.addError(Exception('Stream error'));

      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedError, isNotNull);
    });
  });

  group('StdioServerTransport - Message Sending', () {
    late MockStdin stdin;
    late MockStdout stdout;
    late StdioServerTransport transport;

    setUp(() {
      stdin = MockStdin();
      stdout = MockStdout();
      transport = StdioServerTransport(stdin: stdin, stdout: stdout);
    });

    tearDown(() async {
      await transport.close();
    });

    test('sends message successfully', () async {
      await transport.start();

      final response = JsonRpcResponse(
        id: 1,
        result: InitializeResult(
          protocolVersion: latestProtocolVersion,
          capabilities: const ServerCapabilities(),
          serverInfo: Implementation(name: 'TestServer', version: '1.0.0'),
        ).toJson(),
      );

      await transport.send(response);

      expect(stdout.writtenData.length, equals(1));
      expect(stdout.writtenData[0], contains('"jsonrpc":"2.0"'));
      expect(stdout.writtenData[0], contains('"result"'));
    });

    test('sends multiple messages in sequence', () async {
      await transport.start();

      final message1 = JsonRpcPingRequest(id: 1);
      final message2 = JsonRpcPingRequest(id: 2);

      await transport.send(message1);
      await transport.send(message2);

      expect(stdout.writtenData.length, equals(2));
    });

    test('warns when sending before start', () async {
      final response = JsonRpcPingRequest(id: 1);

      // Should not throw, but will log warning
      await transport.send(response);

      // No data written because not started
      expect(stdout.writtenData.length, equals(0));
    });
  });

  group('StdioServerTransport - Error Handling', () {
    late MockStdin stdin;
    late MockStdout stdout;
    late StdioServerTransport transport;

    setUp(() {
      stdin = MockStdin();
      stdout = MockStdout();
      transport = StdioServerTransport(stdin: stdin, stdout: stdout);
    });

    tearDown(() async {
      await transport.close();
    });

    test('handles error in onmessage callback gracefully', () async {
      transport.onmessage = (message) {
        throw Exception('Handler error');
      };

      Error? receivedError;
      transport.onerror = (error) {
        receivedError = error;
      };

      await transport.start();

      final message = JsonRpcPingRequest(id: 1);
      stdin.addString('${jsonEncode(message.toJson())}\n');

      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedError, isNotNull);
    });

    test('handles error in onerror callback gracefully', () async {
      transport.onerror = (error) {
        throw Exception('onerror handler error');
      };

      await transport.start();

      stdin.addString('invalid json\n');

      await Future.delayed(Duration(milliseconds: 50));

      // Should not crash, just log warning
      expect(() => Future.value(), returnsNormally);
    });

    test('handles error in onclose callback gracefully', () async {
      transport.onclose = () {
        throw Exception('onclose handler error');
      };

      await transport.start();

      // Should not throw, just log warning
      await transport.close();

      expect(() => transport.close(), returnsNormally);
    });
  });
}
