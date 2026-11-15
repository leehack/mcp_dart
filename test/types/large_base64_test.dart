import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

// Exercise validation through public parsing and serialization entry points.
Map<String, dynamic> toolJson(String kind, String data) => {
      'content': [
        if (kind == 'blob')
          {
            'type': 'resource',
            'resource': {'uri': 'test://blob', 'blob': data},
          }
        else
          {'type': kind, 'data': data, 'mimeType': '$kind/test'},
      ],
    };

CallToolResult toolResult(String kind, String data) => CallToolResult(
      content: [
        if (kind == 'blob')
          EmbeddedResource(
            resource: BlobResourceContents(uri: 'test://blob', blob: data),
          )
        else if (kind == 'image')
          ImageContent(data: data, mimeType: 'image/test')
        else
          AudioContent(data: data, mimeType: 'audio/test'),
      ],
    );

void checkValid(String data) {
  for (final kind in ['image', 'audio', 'blob']) {
    final json = toolJson(kind, data);
    expect(CallToolResult.fromJson(json).toJson(), json);
    expect(toolResult(kind, data).toJson(), json);
  }
  for (final image in [true, false]) {
    final json = {
      'type': image ? 'image' : 'audio',
      'data': data,
      'mimeType': image ? 'image/test' : 'audio/test',
    };
    expect(SamplingContent.fromJson(json).toJson(), json);
    expect(
      image
          ? SamplingImageContent(data: data, mimeType: 'image/test').toJson()
          : SamplingAudioContent(data: data, mimeType: 'audio/test').toJson(),
      json,
    );
  }
}

void checkInvalid(String data) {
  for (final kind in ['image', 'audio', 'blob']) {
    expect(
      () => CallToolResult.fromJson(toolJson(kind, data)),
      throwsFormatException,
    );
    expect(() => toolResult(kind, data).toJson(), throwsArgumentError);
  }
  for (final image in [true, false]) {
    expect(
      () => SamplingContent.fromJson({
        'type': image ? 'image' : 'audio',
        'data': data,
        'mimeType': image ? 'image/test' : 'audio/test',
      }),
      throwsFormatException,
    );
    expect(
      () => image
          ? SamplingImageContent(data: data, mimeType: 'image/test').toJson()
          : SamplingAudioContent(data: data, mimeType: 'audio/test').toJson(),
      throwsArgumentError,
    );
  }
}

void main() {
  test('canonical base64 acceptance matrix across public content APIs', () {
    for (final data in ['', 'TWFu', 'TWE=', 'TQ==', '+/8=', 'AZaz09+/']) {
      checkValid(data);
    }
    for (final data in [
      'A',
      'AAA',
      'AAAAA',
      '====',
      'A===',
      'AA=A',
      '=AAA',
      'AA==AAAA',
      'AAA==',
      'TQ',
      'TQ%3D%3D',
      '-_8=',
      'AAAA\n',
      'AA A',
      'AA\tA',
      'AAéA',
      'AA😀',
      'TR==',
      'TWF=',
    ]) {
      checkInvalid(data);
    }
  });

  test('every terminal sextet agrees with the standard base64 decoder', () {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    for (final symbol in alphabet.split('')) {
      for (final data in ['AAA$symbol', 'AA$symbol=', 'A$symbol==']) {
        var valid = true;
        try {
          base64Decode(data);
        } on FormatException {
          valid = false;
        }
        if (valid) {
          checkValid(data);
        } else {
          checkInvalid(data);
        }
      }
    }
  });

  test('invalid characters are rejected in each lookup block and tail', () {
    for (final valid in ['AAAAAAAA', 'AAAAAAA=', 'AAAAAA==']) {
      final dataEnd = valid.indexOf('=');
      final end = dataEnd == -1 ? valid.length : dataEnd;
      for (var i = 0; i < end; i++) {
        for (final invalid in [
          '!',
          '-',
          '_',
          '\u0080',
          '\uffff',
          '\ud800',
        ]) {
          checkInvalid(valid.replaceRange(i, i + 1, invalid));
        }
      }
    }
  });

  // Decoded payload sizes straddle 4/8 MiB and collectively cover all padding
  // endings without retaining multiple large payloads at once.
  for (final size in [4 * 1024 * 1024, 8 * 1024 * 1024, 8 * 1024 * 1024 + 1]) {
    test('large base64 public parsing and serialization: $size bytes', () {
      final bytes = Uint8List(size);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i & 0xff;
      }
      checkValid(base64Encode(bytes));
    });
  }

  test('large base64 serialization alone: 4 MiB', () {
    final data = base64Encode(Uint8List(4 * 1024 * 1024));
    expect(toolResult('image', data).toJson(), toolJson('image', data));
  });

  test('large invalid character near the end preserves exception types', () {
    final valid = base64Encode(Uint8List(4 * 1024 * 1024));
    checkInvalid('${valid.substring(0, valid.length - 4)}!A==');
  });

  test('4 MiB tool result crosses public client/server IO streams', () async {
    final payload = base64Encode(Uint8List(4 * 1024 * 1024));
    final requests = StreamController<List<int>>();
    final responses = StreamController<List<int>>();
    final server =
        McpServer(const Implementation(name: 'server', version: '1'));
    final client =
        McpClient(const Implementation(name: 'client', version: '1'));
    addTearDown(() async {
      await client.close();
      await server.close();
      await requests.close();
      await responses.close();
    });
    server.registerTool(
      'image',
      callback: (args, extra) => toolResult('image', payload),
    );
    await server.connect(
      IOStreamTransport(stream: requests.stream, sink: responses.sink),
    );
    await client.connect(
      IOStreamTransport(stream: responses.stream, sink: requests.sink),
    );
    final result = await client.callTool(const CallToolRequest(name: 'image'));
    expect((result.content.single as ImageContent).data, payload);
  });
}
