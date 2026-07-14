import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];

  @override
  String? get sessionId => null;

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);
    if (message is JsonRpcRequest && message.method == Method.serverDiscover) {
      _respond(
        JsonRpcError(
          id: message.id,
          error: const JsonRpcErrorData(
            code: -32601,
            message: 'Method not found',
          ),
        ),
      );
    } else if (message is JsonRpcRequest &&
        message.method == Method.initialize) {
      _respond(
        JsonRpcResponse(
          id: message.id,
          result: const InitializeResult(
            protocolVersion: stableProtocolVersion,
            capabilities: ServerCapabilities(
              elicitation: ServerCapabilitiesElicitation(
                form: ServerElicitationForm(),
              ),
            ),
            serverInfo: Implementation(name: 'MockServer', version: '1.0.0'),
          ).toJson(),
        ),
      );
    }
  }

  void _respond(JsonRpcMessage message) {
    scheduleMicrotask(() {
      onmessage?.call(message);
    });
  }

  @override
  Future<void> start() async {}
}

Map<String, dynamic> _lastElicitContent(MockTransport transport) {
  final response = transport.sentMessages.whereType<JsonRpcResponse>().last;
  return response.result['content'] as Map<String, dynamic>;
}

void main() {
  group('Client - Elicitation Defaults', () {
    late Client client;
    late MockTransport transport;

    setUp(() {
      transport = MockTransport();
      client = Client(
        const Implementation(name: 'TestClient', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation(
              form: ClientElicitationForm(applyDefaults: true),
            ),
          ),
        ),
      );
    });

    test('applies default values to elicitation content', () async {
      await client.connect(transport);

      Map<String, dynamic>? receivedContent;
      client.onElicitRequest = (params) async {
        expect(params.mode, equals(ElicitationMode.form));
        expect(params.requestedSchema, isNotNull);

        // Simulate user accepting with empty content, expecting defaults to be applied
        receivedContent = {};
        return ElicitResult(
          action: 'accept',
          content: receivedContent!,
        );
      };

      // Simulate server sending an elicitation request with a schema and defaults
      final elicitRequest = JsonRpcElicitRequest(
        id: 1,
        elicitParams: ElicitRequestParams.form(
          message: 'Please provide details',
          requestedSchema: JsonSchema.object(
            properties: {
              'name': JsonSchema.string(defaultValue: 'John Doe'),
              'age': JsonSchema.integer(defaultValue: 30),
              'addressStreet': JsonSchema.string(defaultValue: 'Main St'),
            },
          ),
        ),
      );

      transport.onmessage?.call(elicitRequest);
      await Future.delayed(
        const Duration(milliseconds: 10),
      ); // Allow microtasks to run

      // Verify that defaults were applied to the submitted response without
      // mutating the callback-owned map.
      expect(receivedContent, isNotNull);
      expect(receivedContent, isEmpty);

      final submittedContent = _lastElicitContent(transport);
      expect(submittedContent['name'], equals('John Doe'));
      expect(submittedContent['age'], equals(30));
      expect(submittedContent['addressStreet'], equals('Main St'));
    });

    test('does not override existing values with defaults', () async {
      await client.connect(transport);

      Map<String, dynamic>? receivedContent;
      client.onElicitRequest = (params) async {
        receivedContent = {'name': 'Jane Smith'};
        return ElicitResult(
          action: 'accept',
          content: receivedContent!,
        );
      };

      final elicitRequest = JsonRpcElicitRequest(
        id: 1,
        elicitParams: ElicitRequestParams.form(
          message: 'Please provide details',
          requestedSchema: JsonSchema.object(
            properties: {
              'name': JsonSchema.string(defaultValue: 'John Doe'),
              'age': JsonSchema.integer(defaultValue: 30),
            },
          ),
        ),
      );

      transport.onmessage?.call(elicitRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(receivedContent, isNotNull);
      expect(
        receivedContent!['name'],
        equals('Jane Smith'),
      ); // Should retain existing

      final submittedContent = _lastElicitContent(transport);
      expect(submittedContent['name'], equals('Jane Smith'));
      expect(submittedContent['age'], equals(30));
    });

    test('does not apply defaults if applyDefaults is false', () async {
      // Configure client with applyDefaults: false
      client = Client(
        const Implementation(name: 'TestClient', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation(
              form: ClientElicitationForm(applyDefaults: false),
            ),
          ),
        ),
      );
      await client.connect(transport);

      Map<String, dynamic>? receivedContent;
      client.onElicitRequest = (params) async {
        receivedContent = {};
        return ElicitResult(
          action: 'accept',
          content: receivedContent!,
        );
      };

      final elicitRequest = JsonRpcElicitRequest(
        id: 1,
        elicitParams: ElicitRequestParams.form(
          message: 'Please provide details',
          requestedSchema: JsonSchema.object(
            properties: {
              'name': JsonSchema.string(defaultValue: 'John Doe'),
            },
          ),
        ),
      );

      transport.onmessage?.call(elicitRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(receivedContent, isNotNull);
      expect(
        receivedContent!.containsKey('name'),
        isFalse,
      ); // Default should NOT be applied
    });

    test('does not apply defaults for url elicitation', () async {
      client = Client(
        const Implementation(name: 'TestClient', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.urlOnly(),
          ),
        ),
      );
      await client.connect(transport);

      Map<String, dynamic>? receivedContent;
      client.onElicitRequest = (params) async {
        receivedContent = {}; // No content for URL elicitation typically
        return const ElicitResult(action: 'accept');
      };

      final elicitRequest = JsonRpcElicitRequest(
        id: 1,
        elicitParams: const ElicitRequestParams.url(
          message: 'Please provide details',
          url: 'http://example.com/form',
          elicitationId: '123',
        ),
      );

      transport.onmessage?.call(elicitRequest);
      await Future.delayed(const Duration(milliseconds: 10));

      // No content is expected for URL elicitation, so no defaults applied to it.
      // The key here is that _applyElicitationDefaults is NOT called for URL mode.
      expect(receivedContent, isNotNull);
      expect(receivedContent!.containsKey('name'), isFalse);
    });
  });
}
