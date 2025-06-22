import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/src/shared/iostream.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('IOStream Transport Tests', () {
    // Stream controllers for direct communication
    late StreamController<List<int>> clientToServerController;
    late StreamController<List<int>> serverToClientController;

    // Client and server transports
    late IOStreamTransport clientTransport;
    late IOStreamTransport serverTransport;

    // Test state management
    late Completer<void> serverCloseCompleter;
    late Completer<void> clientCloseCompleter;
    late Completer<Error> serverErrorCompleter;
    late Completer<Error> clientErrorCompleter;
    final List<JsonRpcMessage> serverReceivedMessages = [];
    final List<JsonRpcMessage> clientReceivedMessages = [];

    setUp(() {
      // Create fresh stream controllers for each test
      clientToServerController = StreamController<List<int>>.broadcast();
      serverToClientController = StreamController<List<int>>.broadcast();

      // Set up transports
      clientTransport = IOStreamTransport(
        stream: serverToClientController.stream,
        sink: clientToServerController.sink,
      );

      serverTransport = IOStreamTransport(
        stream: clientToServerController.stream,
        sink: serverToClientController.sink,
      );

      // Reset state tracking
      serverCloseCompleter = Completer<void>();
      clientCloseCompleter = Completer<void>();
      serverErrorCompleter = Completer<Error>();
      clientErrorCompleter = Completer<Error>();
      serverReceivedMessages.clear();
      clientReceivedMessages.clear();

      // Configure callbacks
      serverTransport.onclose = () {
        if (!serverCloseCompleter.isCompleted) {
          serverCloseCompleter.complete();
        }
      };

      serverTransport.onerror = (error) {
        if (!serverErrorCompleter.isCompleted) {
          serverErrorCompleter.complete(error);
        }
      };

      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
      };

      clientTransport.onclose = () {
        if (!clientCloseCompleter.isCompleted) {
          clientCloseCompleter.complete();
        }
      };

      clientTransport.onerror = (error) {
        if (!clientErrorCompleter.isCompleted) {
          clientErrorCompleter.complete(error);
        }
      };

      clientTransport.onmessage = (message) {
        clientReceivedMessages.add(message);
      };
    });

    tearDown(() async {
      // Clean up resources
      await clientTransport.close();
      await serverTransport.close();
      await clientToServerController.close();
      await serverToClientController.close();
    });

    // Helper to send a properly formatted message directly to a stream controller
    void sendRawJsonMessage(
        StreamController<List<int>> controller, JsonRpcMessage message) {
      final jsonString = "${jsonEncode(message.toJson())}\n";
      controller.add(utf8.encode(jsonString));
    }

    test('Transports start without errors', () async {
      await serverTransport.start();
      await clientTransport.start();

      expect(serverCloseCompleter.isCompleted, isFalse);
      expect(clientCloseCompleter.isCompleted, isFalse);
      expect(serverErrorCompleter.isCompleted, isFalse);
      expect(clientErrorCompleter.isCompleted, isFalse);
    });

    test('Basic message passing - client to server', () async {
      // Start both sides
      await serverTransport.start();
      await clientTransport.start();

      // Setup a completer for server message receipt
      final messageReceived = Completer<JsonRpcMessage>();
      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!messageReceived.isCompleted) {
          messageReceived.complete(message);
        }
      };

      // Send a message via the raw controller (bypassing transport.send())
      final pingMessage = JsonRpcPingRequest(id: 1);
      sendRawJsonMessage(clientToServerController, pingMessage);

      // Wait for the message to be received
      final receivedMessage = await messageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Message not received'),
      );

      // Verify correct message received
      expect(receivedMessage, isA<JsonRpcPingRequest>());
      expect((receivedMessage as JsonRpcPingRequest).id, 1);
    });

    test('Basic message passing - server to client', () async {
      // Start both sides
      await serverTransport.start();
      await clientTransport.start();

      // Setup a completer for client message receipt
      final messageReceived = Completer<JsonRpcMessage>();
      clientTransport.onmessage = (message) {
        clientReceivedMessages.add(message);
        if (!messageReceived.isCompleted) {
          messageReceived.complete(message);
        }
      };

      // Send a message from server to client
      final pingMessage = JsonRpcPingRequest(id: 2);
      sendRawJsonMessage(serverToClientController, pingMessage);

      // Wait for the message to be received
      final receivedMessage = await messageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Message not received'),
      );

      // Verify correct message received
      expect(receivedMessage, isA<JsonRpcPingRequest>());
      expect((receivedMessage as JsonRpcPingRequest).id, 2);
    });

    test('Bidirectional communication', () async {
      // Start both sides
      await serverTransport.start();
      await clientTransport.start();

      // Setup completers for message receipt
      final serverReceived = Completer<JsonRpcMessage>();
      final clientReceived = Completer<JsonRpcMessage>();

      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!serverReceived.isCompleted) {
          serverReceived.complete(message);
        }
      };

      clientTransport.onmessage = (message) {
        clientReceivedMessages.add(message);
        if (!clientReceived.isCompleted) {
          clientReceived.complete(message);
        }
      };

      // Send client -> server
      sendRawJsonMessage(clientToServerController, JsonRpcPingRequest(id: 3));

      // Send server -> client
      sendRawJsonMessage(serverToClientController, JsonRpcPingRequest(id: 4));

      // Wait for both messages to be received
      final serverMsg =
          await serverReceived.future.timeout(const Duration(seconds: 2));
      final clientMsg =
          await clientReceived.future.timeout(const Duration(seconds: 2));

      // Verify both messages
      expect(serverMsg, isA<JsonRpcPingRequest>());
      expect((serverMsg as JsonRpcPingRequest).id, 3);

      expect(clientMsg, isA<JsonRpcPingRequest>());
      expect((clientMsg as JsonRpcPingRequest).id, 4);
    });

    test('Multiple messages can be sent and received', () async {
      await serverTransport.start();
      await clientTransport.start();

      const expectedMessageCount = 5;
      final receivedMessages = <JsonRpcMessage>[];
      final allMessagesReceived = Completer<void>();

      serverTransport.onmessage = (message) {
        receivedMessages.add(message);
        if (receivedMessages.length >= expectedMessageCount) {
          if (!allMessagesReceived.isCompleted) {
            allMessagesReceived.complete();
          }
        }
      };

      // Send multiple messages
      for (int i = 0; i < expectedMessageCount; i++) {
        sendRawJsonMessage(clientToServerController, JsonRpcPingRequest(id: i));
        // Add a small delay to avoid overwhelming the stream
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Wait for all messages to be received
      await allMessagesReceived.future.timeout(const Duration(seconds: 5));

      // Verify messages received
      expect(receivedMessages.length, expectedMessageCount);

      // Check all expected IDs are present
      final receivedIds =
          receivedMessages.map((msg) => (msg as JsonRpcPingRequest).id).toSet();

      for (int i = 0; i < expectedMessageCount; i++) {
        expect(receivedIds, contains(i));
      }
    });

    test('Transport closes when input stream closes', () async {
      await serverTransport.start();

      // Close the client-to-server controller
      await clientToServerController.close();

      // Wait for server transport to close
      await serverCloseCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Transport not closed'),
      );
    });

    test('Transport handles invalid JSON gracefully', () async {
      await serverTransport.start();

      // Send invalid JSON data
      clientToServerController.add(utf8.encode('not valid json\n'));

      // Wait for error to be reported
      final error = await serverErrorCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Error not reported'),
      );

      // Verify error was reported but transport still works
      expect(error.toString(), contains('Invalid JSON'));

      // Set up a completer for subsequent valid message
      final validMessageReceived = Completer<JsonRpcMessage>();
      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!validMessageReceived.isCompleted) {
          validMessageReceived.complete(message);
        }
      };

      // Send a valid message
      sendRawJsonMessage(clientToServerController, JsonRpcPingRequest(id: 7));

      // Wait for valid message to be received
      final validMessage = await validMessageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw TimeoutException('Valid message not received after error'),
      );

      // Verify message received correctly
      expect(validMessage, isA<JsonRpcPingRequest>());
      expect((validMessage as JsonRpcPingRequest).id, 7);
    });

    test('Cannot start transport twice', () async {
      await serverTransport.start();

      // Attempt to start again should throw
      expect(() => serverTransport.start(), throwsA(isA<StateError>()));
    });

    test('Cannot send messages after transport is closed', () async {
      await serverTransport.start();
      await serverTransport.close();

      // Attempt to send message from closed transport should throw
      expect(
        () => serverTransport.send(JsonRpcPingRequest(id: 8)),
        throwsA(isA<StateError>()),
      );
    });

    test('Partial JSON messages are buffered until complete', () async {
      await serverTransport.start();

      // Setup a completer for message receipt
      final messageReceived = Completer<JsonRpcMessage>();
      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!messageReceived.isCompleted) {
          messageReceived.complete(message);
        }
      };

      // Create a message and encode it
      final message = JsonRpcPingRequest(id: 9);
      final jsonString = "${jsonEncode(message.toJson())}\n";
      final bytes = utf8.encode(jsonString);

      // Split the message into multiple parts
      final partOne = bytes.sublist(0, bytes.length ~/ 2);
      final partTwo = bytes.sublist(bytes.length ~/ 2);

      // Send first part and check no message is received yet
      clientToServerController.add(partOne);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(serverReceivedMessages.isEmpty, isTrue);

      // Send second part and wait for complete message
      clientToServerController.add(partTwo);
      final receivedMessage = await messageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw TimeoutException('Complete message not received'),
      );

      // Verify message was received correctly
      expect(receivedMessage, isA<JsonRpcPingRequest>());
      expect((receivedMessage as JsonRpcPingRequest).id, 9);
    });

    test('Error in onmessage handler is caught and reported', () async {
      await serverTransport.start();

      // Set up a completer to capture the reported error
      final errorReported = Completer<Error>();

      // Set up an onmessage handler that throws an error
      serverTransport.onmessage = (message) {
        throw StateError('Intentional error in onmessage handler');
      };

      // Set up an onerror handler to capture the error
      serverTransport.onerror = (error) {
        if (!errorReported.isCompleted) {
          errorReported.complete(error);
        }
      };

      // Send a message to trigger the error
      sendRawJsonMessage(clientToServerController, JsonRpcPingRequest(id: 10));

      // Wait for the error to be reported
      final reportedError = await errorReported.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Error not reported'),
      );

      // Verify the error was reported with the correct message
      expect(reportedError, isA<StateError>());
      expect(reportedError.toString(), contains('onmessage handler'));
    });

    test('Error in onerror handler is handled gracefully', () async {
      await serverTransport.start();

      // Set up an onerror handler that throws another error
      serverTransport.onerror = (error) {
        throw StateError('Intentional error in onerror handler');
      };

      // Send invalid JSON data to trigger an error
      clientToServerController.add(utf8.encode('invalid json\n'));

      // Wait a moment to allow error processing
      await Future.delayed(const Duration(milliseconds: 100));

      // We can't easily assert what happens here, but the transport should remain functional
      // and not crash. Let's send another valid message and make sure it works.

      // Reset the onerror handler so it doesn't throw again
      serverTransport.onerror = null;

      // Set up a completer for subsequent valid message
      final validMessageReceived = Completer<JsonRpcMessage>();
      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!validMessageReceived.isCompleted) {
          validMessageReceived.complete(message);
        }
      };

      // Send a valid message
      sendRawJsonMessage(clientToServerController, JsonRpcPingRequest(id: 11));

      // Wait for valid message to be received, showing transport still works
      final validMessage = await validMessageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw TimeoutException('Valid message not received after error'),
      );

      // Verify message received correctly
      expect(validMessage, isA<JsonRpcPingRequest>());
      expect((validMessage as JsonRpcPingRequest).id, 11);
    });

    test('Transport handles incomplete message at end of stream', () async {
      await serverTransport.start();

      // Create a message but don't add the newline terminator
      final message = JsonRpcPingRequest(id: 12);
      final jsonString = jsonEncode(message.toJson()); // No newline at the end

      // Send the incomplete message
      clientToServerController.add(utf8.encode(jsonString));

      // Wait a moment to allow processing
      await Future.delayed(const Duration(milliseconds: 100));

      // No message should be received since it's incomplete
      expect(serverReceivedMessages.isEmpty, isTrue);

      // Now close the stream
      await clientToServerController.close();

      // Wait for the transport to close
      await serverCloseCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Transport not closed'),
      );

      // Verify no message was extracted from the incomplete data
      expect(serverReceivedMessages.isEmpty, isTrue);
    });
  });
}
