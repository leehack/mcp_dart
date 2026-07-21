import 'dart:async';

import 'package:mcp_dart/src/server/server.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/stateless_meta_validation.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/types/json_rpc.dart' show validateMetaObject;
import 'package:test/test.dart';

const _invalidMeta = <String, dynamic>{'com.example//trace': true};
const _validExtensionMeta = <String, dynamic>{
  'com.example/trace_id': 'trace-1',
};
const _validTraceContextMeta = <String, dynamic>{
  'traceparent': '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
  'tracestate': 'rojo=00f067aa0ba902b7,congo=t61rcWkgMzE',
  'baggage': 'userId=Am%C3%A9lie;tenant=acme;sampled, serverNode = DF%2028',
};
const _invalidTraceContextMeta = <String, dynamic>{
  'traceparent': '00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01',
};
const _modernRequestMeta = <String, dynamic>{
  McpMetaKey.protocolVersion: defaultProtocolVersion,
  McpMetaKey.clientCapabilities: <String, dynamic>{},
};

class _RecordingTransport extends Transport {
  final List<JsonRpcMessage> sent = [];

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
  }) async {
    sent.add(message);
  }

  @override
  Future<void> start() async {}

  void receive(JsonRpcMessage message) {
    onmessage?.call(message);
  }
}

class _TestProtocol extends Protocol {
  _TestProtocol() : super(const ProtocolOptions());

  @override
  void assertCapabilityForMethod(String method) {}

  @override
  void assertNotificationCapability(String method) {}

  @override
  void assertRequestHandlerCapability(String method) {}

  @override
  void assertTaskCapability(String method) {}

  @override
  void assertTaskHandlerCapability(String method) {}
}

class _RawResult implements BaseResultData {
  final Map<String, dynamic> json;

  const _RawResult(this.json);

  @override
  Map<String, dynamic>? get meta => json['_meta'] as Map<String, dynamic>?;

  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(json);
}

void main() {
  group('2026-07-28 MetaObject grammar', () {
    test('server rejects malformed result metadata only for modern requests',
        () {
      final modernServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      final legacyServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );

      expect(
        () => modernServer.serializeIncomingResult(
          const JsonRpcPingRequest(id: 1, meta: _modernRequestMeta),
          const EmptyResult(meta: _invalidMeta),
        ),
        throwsFormatException,
      );

      final legacyResult = legacyServer.serializeIncomingResult(
        const JsonRpcPingRequest(id: 1),
        const EmptyResult(meta: _invalidMeta),
      );
      expect(legacyResult['_meta'], _invalidMeta);
    });

    test('server preserves valid extension result metadata', () {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );

      final result = server.serializeIncomingResult(
        const JsonRpcPingRequest(id: 1, meta: _modernRequestMeta),
        const EmptyResult(meta: _validExtensionMeta),
      );

      expect(result['_meta'], containsPair('com.example/trace_id', 'trace-1'));
    });

    test('accepts W3C trace context and baggage values', () {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );

      final result = server.serializeIncomingResult(
        const JsonRpcPingRequest(id: 1, meta: _modernRequestMeta),
        const EmptyResult(meta: _validTraceContextMeta),
      );

      final resultMeta = result['_meta'] as Map<String, dynamic>;
      for (final entry in _validTraceContextMeta.entries) {
        expect(resultMeta, containsPair(entry.key, entry.value));
      }
      expect(
        () => validateMetaObject(const {
          'traceparent':
              '01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-03-vendor-data',
          'tracestate': '',
          'baggage': 'dup=first,dup=second,empty=',
        }),
        returnsNormally,
      );
      expect(
        () => validateMetaObject({
          'tracestate': List.generate(32, (index) => 'v$index=value').join(','),
          'baggage': List.generate(180, (index) => 'k$index=value').join(','),
        }),
        returnsNormally,
      );
    });

    test('rejects malformed reserved trace context values', () {
      final invalidMetaObjects = <Map<String, dynamic>>[
        {'com.example/trace\n': 'value'},
        {'traceparent': 1},
        {
          'traceparent':
              '00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01',
        },
        {
          'traceparent':
              '00-00000000000000000000000000000000-00f067aa0ba902b7-01',
        },
        {
          'traceparent':
              '00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01',
        },
        {
          'traceparent':
              '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra',
        },
        {
          'traceparent':
              '01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01extra',
        },
        {
          'traceparent':
              '01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-0\n',
        },
        {
          'traceparent':
              'ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        },
        {'tracestate': 1},
        {'tracestate': '1vendor=value'},
        {'tracestate': 'vendor='},
        {'tracestate': 'vendor=value,vendor=again'},
        {'tracestate': 'vendor=value=again'},
        {'tracestate': 'vendor\n=value'},
        {
          'tracestate': List.generate(33, (index) => 'v$index=value').join(','),
        },
        {'baggage': 1},
        {'baggage': ''},
        {'baggage': 'user id=alice'},
        {'baggage': 'user\n=alice'},
        {'baggage': 'userId=alice smith'},
        {'baggage': 'userId=alice%2'},
        {'baggage': 'userId=Amélie'},
        {'baggage': 'userId=alice;'},
        {
          'baggage': List.generate(181, (index) => 'k$index=value').join(','),
        },
      ];

      for (final meta in invalidMetaObjects) {
        expect(
          () => validateMetaObject(meta),
          throwsFormatException,
          reason: '$meta',
        );
      }
    });

    test('reserved value validation remains modern-only', () {
      final modernServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      final legacyServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );

      expect(
        () => modernServer.serializeIncomingResult(
          const JsonRpcPingRequest(id: 1, meta: _modernRequestMeta),
          const EmptyResult(meta: _invalidTraceContextMeta),
        ),
        throwsFormatException,
      );

      final legacyResult = legacyServer.serializeIncomingResult(
        const JsonRpcPingRequest(id: 1),
        const EmptyResult(meta: _invalidTraceContextMeta),
      );
      expect(legacyResult['_meta'], _invalidTraceContextMeta);
    });

    test('server rejects malformed incoming modern notification metadata', () {
      final modernServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      final legacyServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );
      final notification = JsonRpcCancelledNotification(
        cancelParams: const CancelledNotification(requestId: 1),
        meta: _invalidMeta,
      );

      expect(
        modernServer.validateIncomingNotification(notification),
        isA<McpError>().having(
          (error) => error.code,
          'code',
          ErrorCode.invalidParams.value,
        ),
      );
      expect(legacyServer.validateIncomingNotification(notification), isNull);
    });

    test('server validates outgoing modern notification metadata', () async {
      final modernTransport = _RecordingTransport();
      final modernServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      await modernServer.connect(modernTransport);
      addTearDown(modernServer.close);

      await expectLater(
        modernServer.notification(
          const JsonRpcNotification(
            method: 'notifications/example',
            meta: _invalidMeta,
          ),
        ),
        throwsFormatException,
      );
      await modernServer.notification(
        const JsonRpcNotification(
          method: 'notifications/example',
          meta: _validExtensionMeta,
        ),
      );
      expect(modernTransport.sent, hasLength(1));
    });

    test('server preserves malformed legacy notification metadata', () async {
      final transport = _RecordingTransport();
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );
      await server.connect(transport);
      addTearDown(server.close);

      await server.notification(
        const JsonRpcNotification(
          method: 'notifications/example',
          meta: _invalidMeta,
        ),
      );

      expect(transport.sent.single.toJson()['params']['_meta'], _invalidMeta);
    });

    test('client-side result validation is modern-only', () async {
      final modernTransport = _RecordingTransport();
      final modernProtocol = _TestProtocol();
      await modernProtocol.connect(modernTransport);
      addTearDown(modernProtocol.close);

      final modernResult = modernProtocol.request<EmptyResult>(
        const JsonRpcRequest(
          id: 99,
          method: 'example/request',
          meta: _modernRequestMeta,
        ),
        EmptyResult.fromJson,
      );
      await Future<void>.delayed(Duration.zero);
      final modernRequest = modernTransport.sent.single as JsonRpcRequest;
      modernTransport.receive(
        JsonRpcResponse(
          id: modernRequest.id,
          result: const {
            'resultType': resultTypeComplete,
            '_meta': _invalidMeta,
          },
        ),
      );
      await expectLater(
        modernResult,
        throwsA(
          isA<McpError>().having(
            (error) => error.code,
            'code',
            ErrorCode.internalError.value,
          ),
        ),
      );

      final legacyTransport = _RecordingTransport();
      final legacyProtocol = _TestProtocol();
      await legacyProtocol.connect(legacyTransport);
      addTearDown(legacyProtocol.close);
      final legacyResult = legacyProtocol.request<EmptyResult>(
        const JsonRpcRequest(id: 99, method: 'example/request'),
        EmptyResult.fromJson,
      );
      await Future<void>.delayed(Duration.zero);
      final legacyRequest = legacyTransport.sent.single as JsonRpcRequest;
      legacyTransport.receive(
        JsonRpcResponse(
          id: legacyRequest.id,
          result: const {'_meta': _invalidMeta},
        ),
      );

      expect((await legacyResult).meta, _invalidMeta);
    });

    test('nested result metadata validation is modern-only', () {
      final modernServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      final legacyServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );
      const result = _RawResult({
        'tools': [
          {
            'name': 'example',
            'inputSchema': {'type': 'object'},
            '_meta': _invalidMeta,
          },
        ],
      });

      expect(
        () => modernServer.serializeIncomingResult(
          const JsonRpcRequest(
            id: 1,
            method: Method.toolsList,
            meta: _modernRequestMeta,
          ),
          result,
        ),
        throwsFormatException,
      );
      expect(
        legacyServer.serializeIncomingResult(
          const JsonRpcRequest(id: 1, method: Method.toolsList),
          result,
        )['tools'],
        isNotEmpty,
      );
    });

    test('nested result metadata preserves valid extensions', () {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      const result = _RawResult({
        'resources': [
          {
            'uri': 'file:///resource',
            'name': 'resource',
            '_meta': _validExtensionMeta,
          },
        ],
      });

      final serialized = server.serializeIncomingResult(
        const JsonRpcRequest(
          id: 1,
          method: Method.resourcesList,
          meta: _modernRequestMeta,
        ),
        result,
      );

      expect(
        serialized['resources'][0]['_meta'],
        _validExtensionMeta,
      );
    });

    test('nested reserved value validation is modern-only', () {
      final modernServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      final legacyServer = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.legacy),
      );
      const result = _RawResult({
        'resources': [
          {
            'uri': 'file:///resource',
            'name': 'resource',
            '_meta': {'baggage': 'userId=unescaped value'},
          },
        ],
      });

      expect(
        () => modernServer.serializeIncomingResult(
          const JsonRpcRequest(
            id: 1,
            method: Method.resourcesList,
            meta: _modernRequestMeta,
          ),
          result,
        ),
        throwsFormatException,
      );
      expect(
        legacyServer.serializeIncomingResult(
          const JsonRpcRequest(id: 1, method: Method.resourcesList),
          result,
        )['resources'],
        isNotEmpty,
      );
    });

    test('arbitrary structured tool output remains opaque', () {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      const result = _RawResult({
        'content': <Map<String, dynamic>>[],
        'structuredContent': {
          '_meta': _invalidMeta,
        },
      });

      final serialized = server.serializeIncomingResult(
        const JsonRpcRequest(
          id: 1,
          method: Method.toolsCall,
          params: {
            'name': 'example',
            'arguments': <String, dynamic>{},
          },
          meta: _modernRequestMeta,
        ),
        result,
      );

      expect(serialized['structuredContent']['_meta'], _invalidMeta);
    });

    test('validates metadata inside modern MRTR input requests', () {
      final server = Server(
        const Implementation(name: 'server', version: '1.0.0'),
        options: const McpServerOptions(protocol: McpProtocol.require2026),
      );
      const result = _RawResult({
        'resultType': resultTypeInputRequired,
        'inputRequests': {
          'sample': {
            'method': Method.samplingCreateMessage,
            'params': {
              'messages': [
                {
                  'role': 'user',
                  'content': {
                    'type': 'text',
                    'text': 'hello',
                    '_meta': _invalidMeta,
                  },
                },
              ],
              'maxTokens': 10,
            },
          },
        },
      });

      expect(
        () => server.serializeIncomingResult(
          const JsonRpcRequest(
            id: 1,
            method: Method.toolsCall,
            params: {
              'name': 'example',
              'arguments': <String, dynamic>{},
            },
            meta: _modernRequestMeta,
          ),
          result,
        ),
        throwsFormatException,
      );
    });

    test('validates metadata inside task notifications', () {
      const notification = JsonRpcNotification(
        method: Method.notificationsTasks,
        params: {
          'taskId': 'task-1',
          'status': 'completed',
          'createdAt': '2026-07-28T00:00:00Z',
          'lastUpdatedAt': '2026-07-28T00:00:00Z',
          'ttlMs': null,
          'result': {
            'content': [
              {
                'type': 'text',
                'text': 'done',
                '_meta': _invalidMeta,
              },
            ],
          },
        },
      );

      expect(
        () => validateStatelessNotificationMetaObjects(notification),
        throwsFormatException,
      );
    });

    test('outgoing nested request metadata validation is modern-only',
        () async {
      const inputResponses = {
        'sample': {
          'model': 'model',
          'role': 'assistant',
          'content': {
            'type': 'text',
            'text': 'hello',
            '_meta': _invalidMeta,
          },
        },
      };
      final modernTransport = _RecordingTransport();
      final modernProtocol = _TestProtocol();
      await modernProtocol.connect(modernTransport);
      addTearDown(modernProtocol.close);

      await expectLater(
        modernProtocol.request<EmptyResult>(
          const JsonRpcRequest(
            id: 1,
            method: Method.toolsCall,
            params: {'inputResponses': inputResponses},
            meta: _modernRequestMeta,
          ),
          EmptyResult.fromJson,
        ),
        throwsFormatException,
      );
      expect(modernTransport.sent, isEmpty);

      final legacyTransport = _RecordingTransport();
      final legacyProtocol = _TestProtocol();
      await legacyProtocol.connect(legacyTransport);
      addTearDown(legacyProtocol.close);
      final legacyResult = legacyProtocol.request<EmptyResult>(
        const JsonRpcRequest(
          id: 1,
          method: Method.toolsCall,
          params: {'inputResponses': inputResponses},
        ),
        EmptyResult.fromJson,
      );
      await Future<void>.delayed(Duration.zero);
      final legacyRequest = legacyTransport.sent.single as JsonRpcRequest;
      legacyTransport.receive(
        JsonRpcResponse(id: legacyRequest.id, result: const {}),
      );

      expect(await legacyResult, isA<EmptyResult>());
    });

    test('embedded sampling result metadata validation is modern-only',
        () async {
      const inputResponses = {
        'sample': {
          'model': 'model',
          'role': 'assistant',
          'content': {'type': 'text', 'text': 'hello'},
          '_meta': _invalidMeta,
        },
      };
      final modernTransport = _RecordingTransport();
      final modernProtocol = _TestProtocol();
      await modernProtocol.connect(modernTransport);
      addTearDown(modernProtocol.close);

      await expectLater(
        modernProtocol.request<EmptyResult>(
          const JsonRpcRequest(
            id: 1,
            method: Method.toolsCall,
            params: {'inputResponses': inputResponses},
            meta: _modernRequestMeta,
          ),
          EmptyResult.fromJson,
        ),
        throwsFormatException,
      );
      expect(modernTransport.sent, isEmpty);

      final legacyTransport = _RecordingTransport();
      final legacyProtocol = _TestProtocol();
      await legacyProtocol.connect(legacyTransport);
      addTearDown(legacyProtocol.close);
      final legacyResult = legacyProtocol.request<EmptyResult>(
        const JsonRpcRequest(
          id: 1,
          method: Method.toolsCall,
          params: {'inputResponses': inputResponses},
        ),
        EmptyResult.fromJson,
      );
      await Future<void>.delayed(Duration.zero);
      final legacyRequest = legacyTransport.sent.single as JsonRpcRequest;
      legacyTransport.receive(
        JsonRpcResponse(id: legacyRequest.id, result: const {}),
      );

      expect(await legacyResult, isA<EmptyResult>());
      expect(
        legacyRequest.params!['inputResponses'],
        containsPair('sample', containsPair('_meta', _invalidMeta)),
      );
    });
  });
}
