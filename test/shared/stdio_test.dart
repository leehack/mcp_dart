import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/stdio.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('ReadBuffer message limit', () {
    test('accepts a message at the configured byte limit', () {
      const message = JsonRpcPingRequest(id: 1);
      final messageBytes = utf8.encode(jsonEncode(message.toJson()));
      final buffer = ReadBuffer(
        maxIncomingMessageBytes: messageBytes.length,
      );

      buffer.append(Uint8List.fromList(messageBytes));
      expect(buffer.readMessage(), isNull);

      buffer.append(Uint8List.fromList(const [10]));
      expect(
        buffer.readMessage(),
        isA<JsonRpcPingRequest>().having(
          (received) => received.id,
          'id',
          1,
        ),
      );
    });

    test('rejects one message byte above the configured limit', () {
      final buffer = ReadBuffer(maxIncomingMessageBytes: 4);

      buffer.append(Uint8List.fromList(const [1, 2, 3, 4]));

      expect(
        () => buffer.append(Uint8List.fromList(const [5])),
        throwsA(
          isA<StdioMessageTooLargeException>().having(
            (error) => error.maxIncomingMessageBytes,
            'maxIncomingMessageBytes',
            4,
          ),
        ),
      );
    });

    test('rejects an oversized complete message in one chunk', () {
      final buffer = ReadBuffer(maxIncomingMessageBytes: 4);

      expect(
        () => buffer.append(Uint8List.fromList(const [1, 2, 3, 4, 5, 10])),
        throwsA(isA<StdioMessageTooLargeException>()),
      );
      expect(buffer.readMessage(), isNull);
    });

    test('counts UTF-8 bytes instead of text characters', () {
      final buffer = ReadBuffer(maxIncomingMessageBytes: 2);

      buffer.append(Uint8List.fromList(utf8.encode('é')));
      buffer.append(Uint8List.fromList(const [10]));

      expect(
        () => buffer.append(Uint8List.fromList(utf8.encode('éé'))),
        throwsA(isA<StdioMessageTooLargeException>()),
      );
    });

    test('accepts multiple bounded messages in one large chunk', () {
      const message = JsonRpcPingRequest(id: 2);
      final encodedMessage = jsonEncode(message.toJson());
      final messageBytes = utf8.encode(encodedMessage);
      final buffer = ReadBuffer(
        maxIncomingMessageBytes: messageBytes.length,
      );

      buffer.append(
        Uint8List.fromList(utf8.encode('$encodedMessage\n$encodedMessage\n')),
      );

      expect(buffer.readMessage(), isA<JsonRpcPingRequest>());
      expect(buffer.readMessage(), isA<JsonRpcPingRequest>());
      expect(buffer.readMessage(), isNull);
    });

    test('clears buffered input after a limit violation', () {
      const message = JsonRpcPingRequest(id: 3);
      final encodedMessage = jsonEncode(message.toJson());
      final messageBytes = utf8.encode(encodedMessage);
      final buffer = ReadBuffer(
        maxIncomingMessageBytes: messageBytes.length,
      );

      expect(
        () => buffer.append(
          Uint8List.fromList(List.filled(messageBytes.length + 1, 120)),
        ),
        throwsA(isA<StdioMessageTooLargeException>()),
      );

      buffer.append(Uint8List.fromList(utf8.encode('$encodedMessage\n')));
      expect(
        buffer.readMessage(),
        isA<JsonRpcPingRequest>().having(
          (received) => received.id,
          'id',
          3,
        ),
      );
    });

    test('requires a positive configured limit', () {
      expect(
        () => ReadBuffer(maxIncomingMessageBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => ReadBuffer(maxIncomingMessageBytes: -1),
        throwsArgumentError,
      );
    });
  });
}
