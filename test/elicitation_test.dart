import 'dart:async';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Mock transport for testing elicitation
class MockTransport extends Transport {
  final List<JsonRpcMessage> sentMessages = [];
  InitializeResult? mockInitializeResponse;
  ElicitResult? mockElicitResult;

  void clearSentMessages() {
    sentMessages.clear();
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    sentMessages.add(message);

    // Handle discovery probe from default 2026 clients against this legacy
    // mock transport.
    if (message is JsonRpcRequest && message.method == Method.serverDiscover) {
      onmessage?.call(
        JsonRpcError(
          id: message.id,
          error: JsonRpcErrorData(
            code: ErrorCode.methodNotFound.value,
            message: 'Method not found',
          ),
        ),
      );
      return;
    }

    // Handle initialize request
    if (message is JsonRpcRequest &&
        message.method == 'initialize' &&
        mockInitializeResponse != null) {
      if (onmessage != null) {
        onmessage!(
          JsonRpcResponse(
            id: message.id,
            result: mockInitializeResponse!.toJson(),
          ),
        );
      }
      // Send initialized notification
      Future.delayed(const Duration(milliseconds: 10), () {
        if (onmessage != null) {
          onmessage!(const JsonRpcInitializedNotification());
        }
      });
    }
    // Handle elicit request from server
    else if (message is JsonRpcElicitRequest && mockElicitResult != null) {
      if (onmessage != null) {
        onmessage!(
          JsonRpcResponse(
            id: message.id,
            result: mockElicitResult!.toJson(),
          ),
        );
      }
    }
    // Handle generic requests
    else if (message is JsonRpcRequest) {
      if (onmessage != null) {
        onmessage!(
          JsonRpcResponse(
            id: message.id,
            result: const EmptyResult().toJson(),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {}

  @override
  String? get sessionId => null;

  // Transport callbacks
  void Function()? _onclose;
  void Function(Error error)? _onerror;
  void Function(JsonRpcMessage message)? _onmessage;

  @override
  void Function()? get onclose => _onclose;

  @override
  set onclose(void Function()? value) {
    _onclose = value;
  }

  @override
  void Function(Error error)? get onerror => _onerror;

  @override
  set onerror(void Function(Error error)? value) {
    _onerror = value;
  }

  @override
  void Function(JsonRpcMessage message)? get onmessage => _onmessage;

  @override
  set onmessage(void Function(JsonRpcMessage message)? value) {
    _onmessage = value;
  }
}

void main() {
  group('Client Elicitation Handler Tests', () {
    test('Client registers elicit handler when capability is present', () {
      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );

      // Verify capability is registered by checking we can set handler
      client.onElicitRequest = (params) async {
        return const ElicitResult(
          action: 'accept',
          content: {'value': 'test'},
        );
      };

      // If no error, handler registration works
      expect(client.onElicitRequest, isNotNull);
    });

    test('Client handler validation works correctly', () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );

      await client.connect(transport);

      // Without setting onElicitRequest, handler is null
      expect(client.onElicitRequest, isNull);

      // After setting it, handler is available
      client.onElicitRequest = (params) async {
        return const ElicitResult(
          action: 'accept',
          content: {'value': 'test'},
        );
      };
      expect(client.onElicitRequest, isNotNull);

      await client.close();
    });

    test('Client successfully handles elicit request with string input',
        () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );

      // Set up elicit handler
      ElicitRequestParams? receivedParams;
      client.onElicitRequest = (params) async {
        receivedParams = params;
        expect(params.message, equals("Enter your name"));

        final schema = params.requestedSchema!;
        expect(schema, isA<JsonObject>());
        final objectSchema = schema as JsonObject;
        final stringSchema = objectSchema.properties!['name'] as JsonString;

        expect(stringSchema.minLength, equals(1));

        return const ElicitResult(
          action: 'accept',
          content: {'name': 'John Doe'},
        );
      };

      await client.connect(transport);

      // Simulate server sending elicit request
      final elicitRequest = JsonRpcElicitRequest(
        id: 1,
        elicitParams: ElicitRequestParams(
          message: "Enter your name",
          requestedSchema: JsonObject(
            properties: {'name': JsonSchema.string(minLength: 1)},
            required: const ['name'],
          ),
        ),
      );

      transport.onmessage?.call(elicitRequest);

      // Give async processing time
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify handler was called
      expect(receivedParams, isNotNull);
      expect(receivedParams?.message, equals("Enter your name"));

      await client.close();
    });

    test('Client handles elicit request with boolean input', () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );

      bool handlerCalled = false;
      client.onElicitRequest = (params) async {
        handlerCalled = true;
        expect(params.message, equals("Confirm action"));

        final schema = params.requestedSchema!;
        expect(schema, isA<JsonObject>());
        final objectSchema = schema as JsonObject;
        expect(objectSchema.properties!['confirmed'], isA<JsonBoolean>());

        return const ElicitResult(
          action: 'accept',
          content: {'confirmed': true},
        );
      };

      await client.connect(transport);

      final elicitRequest = JsonRpcElicitRequest(
        id: 2,
        elicitParams: ElicitRequestParams(
          message: "Confirm action",
          requestedSchema: JsonObject(
            properties: {
              'confirmed': JsonSchema.boolean(defaultValue: false),
            },
            required: const ['confirmed'],
          ),
        ),
      );

      transport.onmessage?.call(elicitRequest);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(handlerCalled, isTrue);
      await client.close();
    });

    test('Client handles elicit request with number input', () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );

      bool handlerCalled = false;
      client.onElicitRequest = (params) async {
        handlerCalled = true;
        expect(params.message, equals("Enter age"));

        final schema = params.requestedSchema!;
        expect(schema, isA<JsonObject>());
        final objectSchema = schema as JsonObject;
        final numberSchema = objectSchema.properties!['age'] as JsonNumber;

        expect(numberSchema.minimum, equals(0));
        expect(numberSchema.maximum, equals(120));

        return const ElicitResult(
          action: 'accept',
          content: {'age': 25},
        );
      };

      await client.connect(transport);

      final elicitRequest = JsonRpcElicitRequest(
        id: 3,
        elicitParams: ElicitRequestParams(
          message: "Enter age",
          requestedSchema: JsonObject(
            properties: {
              'age': JsonSchema.number(minimum: 0, maximum: 120),
            },
            required: const ['age'],
          ),
        ),
      );

      transport.onmessage?.call(elicitRequest);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(handlerCalled, isTrue);
      await client.close();
    });

    test('Client handles elicit request with enum input', () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );

      bool handlerCalled = false;
      client.onElicitRequest = (params) async {
        handlerCalled = true;
        expect(params.message, equals("Choose size"));

        final schema = params.requestedSchema!;
        expect(schema, isA<JsonObject>());
        final objectSchema = schema as JsonObject;
        final stringSchema = objectSchema.properties!['size'] as JsonString;
        expect(stringSchema.enumValues, equals(['small', 'medium', 'large']));

        return const ElicitResult(
          action: 'accept',
          content: {'size': 'medium'},
        );
      };

      await client.connect(transport);

      final elicitRequest = JsonRpcElicitRequest(
        id: 4,
        elicitParams: ElicitRequestParams(
          message: "Choose size",
          requestedSchema: JsonObject(
            properties: {
              'size': JsonSchema.string(
                enumValues: ['small', 'medium', 'large'],
                defaultValue: 'medium',
              ),
            },
            required: const ['size'],
          ),
        ),
      );

      transport.onmessage?.call(elicitRequest);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(handlerCalled, isTrue);
      await client.close();
    });

    test('Client handles rejected elicit request', () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );

      ElicitResult? receivedResult;
      client.onElicitRequest = (params) async {
        // Simulate user cancelling/rejecting
        receivedResult = const ElicitResult(action: 'decline');
        return receivedResult!;
      };

      await client.connect(transport);

      final elicitRequest = JsonRpcElicitRequest(
        id: 5,
        elicitParams: ElicitRequestParams(
          message: "Enter name",
          requestedSchema: JsonObject(
            properties: {'name': JsonSchema.string(minLength: 1)},
            required: const ['name'],
          ),
        ),
      );

      transport.onmessage?.call(elicitRequest);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedResult, isNotNull);
      expect(receivedResult?.accepted, isFalse);
      expect(receivedResult?.declined, isTrue);
      expect(receivedResult?.content, isNull);

      await client.close();
    });

    test('Client without elicitation capability does not register handler', () {
      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(),
        ),
      );

      // Attempting to set handler on client without capability
      // The handler can be set, but won't be registered internally
      client.onElicitRequest = (params) async {
        return const ElicitResult(
          action: 'accept',
          content: {'value': 'test'},
        );
      };

      // This should succeed - the handler field can be set
      // but the internal request handler won't be registered
      expect(client.onElicitRequest, isNotNull);
    });

    test('Client with URL-only capability handles URL elicitation', () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.urlOnly(),
          ),
        ),
      );

      ElicitRequest? receivedParams;
      client.onElicitRequest = (params) async {
        receivedParams = params;
        return const ElicitResult(action: 'accept');
      };

      await client.connect(transport);
      transport.clearSentMessages();

      transport.onmessage?.call(
        JsonRpcElicitRequest(
          id: 7,
          elicitParams: const ElicitRequest.url(
            message: 'Please authenticate',
            url: 'https://oauth.example.com/authorize',
            elicitationId: 'oauth-123',
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedParams, isNotNull);
      expect(receivedParams!.isUrlMode, isTrue);
      expect(transport.sentMessages.single, isA<JsonRpcResponse>());
      final response = transport.sentMessages.single as JsonRpcResponse;
      expect(response.id, 7);
      expect(response.result, equals({'action': 'accept'}));

      await client.close();
    });

    test('Client rejects unsupported elicitation mode', () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.formOnly(),
          ),
        ),
      );
      client.onElicitRequest = (params) async {
        return const ElicitResult(action: 'accept');
      };

      await client.connect(transport);
      transport.clearSentMessages();

      transport.onmessage?.call(
        JsonRpcElicitRequest(
          id: 8,
          elicitParams: const ElicitRequest.url(
            message: 'Please authenticate',
            url: 'https://oauth.example.com/authorize',
            elicitationId: 'oauth-123',
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(transport.sentMessages.single, isA<JsonRpcError>());
      final error = transport.sentMessages.single as JsonRpcError;
      expect(error.id, 8);
      expect(error.error.code, ErrorCode.invalidParams.value);
      expect(error.error.message, contains('URL elicitation'));

      await client.close();
    });

    test('Client rejects form elicitation when only URL is advertised',
        () async {
      final transport = MockTransport();
      transport.mockInitializeResponse = const InitializeResult(
        protocolVersion: stableProtocolVersion2025_11_25,
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
      );

      final client = Client(
        const Implementation(name: 'test-client', version: '1.0.0'),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            elicitation: ClientElicitation.urlOnly(),
          ),
        ),
      );
      client.onElicitRequest = (params) async {
        return const ElicitResult(action: 'accept');
      };

      await client.connect(transport);
      transport.clearSentMessages();

      transport.onmessage?.call(
        JsonRpcElicitRequest(
          id: 9,
          elicitParams: ElicitRequest.form(
            message: 'Enter your name',
            requestedSchema: JsonObject(
              properties: {'name': JsonSchema.string()},
              required: const ['name'],
            ),
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(transport.sentMessages.single, isA<JsonRpcError>());
      final error = transport.sentMessages.single as JsonRpcError;
      expect(error.id, 9);
      expect(error.error.code, ErrorCode.invalidParams.value);
      expect(error.error.message, contains('form elicitation'));

      await client.close();
    });
  });

  group('Elicitation Spec 2025-11-25 Features', () {
    test('JsonSchema integer serialization', () {
      final schema = JsonSchema.integer(
        minimum: 0,
        maximum: 100,
        defaultValue: 50,
        title: 'Age',
        description: 'Your age in years',
      );

      final json = schema.toJson();
      expect(json['type'], equals('integer'));
      expect(json['minimum'], equals(0));
      expect(json['maximum'], equals(100));
      expect(json['default'], equals(50));
      expect(json['title'], equals('Age'));
      expect(json['description'], equals('Your age in years'));

      final parsed = JsonSchema.fromJson(json);
      expect(parsed, isA<JsonInteger>());
      final integerSchema = parsed as JsonInteger;
      expect(integerSchema.minimum, equals(0));
      expect(integerSchema.maximum, equals(100));
    });

    test('JsonSchema string with format field', () {
      final schema = JsonSchema.string(
        format: 'email',
        title: 'Email Address',
        description: 'Your email',
      );

      final json = schema.toJson();
      expect(json['type'], equals('string'));
      expect(json['format'], equals('email'));
      expect(json['title'], equals('Email Address'));

      final parsed = JsonSchema.fromJson(json);
      expect(parsed, isA<JsonString>());
      final stringSchema = parsed as JsonString;
      expect(stringSchema.format, equals('email'));
    });

    test('ClientElicitation form/url sub-objects', () {
      // Default: form only
      const defaultCaps = ClientElicitation.formOnly();
      expect(defaultCaps.form != null, isTrue);
      expect(defaultCaps.url != null, isFalse);

      final defaultJson = defaultCaps.toJson();
      expect(defaultJson.containsKey('form'), isTrue);
      expect(defaultJson.containsKey('url'), isFalse);

      // Both form and URL
      const allCaps = ClientElicitation.all();
      expect(allCaps.form != null, isTrue);
      expect(allCaps.url != null, isTrue);

      final allJson = allCaps.toJson();
      expect(allJson.containsKey('form'), isTrue);
      expect(allJson.containsKey('url'), isTrue);

      // URL only
      const urlOnlyCaps = ClientElicitation.urlOnly();
      expect(urlOnlyCaps.form != null, isFalse);
      expect(urlOnlyCaps.url != null, isTrue);

      // Parse from JSON with sub-objects
      final parsedCaps = ClientElicitation.fromJson({
        'form': {},
        'url': {},
      });
      expect(parsedCaps.form != null, isTrue);
      expect(parsedCaps.url != null, isTrue);
    });

    test('ElicitRequestParams URL mode', () {
      const params = ElicitRequestParams.url(
        message: 'Please authenticate',
        url: 'https://oauth.example.com/authorize',
        elicitationId: 'oauth-123',
      );

      expect(params.isUrlMode, isTrue);
      expect(params.isFormMode, isFalse);
      expect(params.mode, equals(ElicitationMode.url));
      expect(params.url, equals('https://oauth.example.com/authorize'));
      expect(params.elicitationId, equals('oauth-123'));
      expect(params.requestedSchema, isNull);

      final json = params.toJson();
      expect(json['mode'], equals('url'));
      expect(json['url'], equals('https://oauth.example.com/authorize'));
      expect(json['elicitationId'], equals('oauth-123'));
    });

    test('ElicitRequestParams form mode', () {
      final params = ElicitRequestParams.form(
        message: 'Enter your name',
        requestedSchema: JsonObject(
          properties: {'name': JsonSchema.string(minLength: 1)},
          required: const ['name'],
        ),
      );

      expect(params.isFormMode, isTrue);
      expect(params.isUrlMode, isFalse);
      expect(params.mode, equals(ElicitationMode.form));
      expect(params.requestedSchema, isNotNull);
      expect(params.url, isNull);
      expect(params.elicitationId, isNull);
    });

    test('ElicitRequestParams rejects invalid form and URL variants', () {
      expect(
        () => ElicitRequestParams.fromJson({
          'mode': 'oauth',
          'message': 'Please authenticate',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson({
          'message': 'Enter your name',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson({
          'mode': 'url',
          'message': 'Please authenticate',
          'url': 'https://oauth.example.com/authorize',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson({
          'mode': 'url',
          'message': 'Please authenticate',
          'url': 'relative/callback',
          'elicitationId': 'oauth-123',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ElicitRequestParams.url(
          message: 'Please authenticate',
          url: 'relative/callback',
          elicitationId: 'oauth-123',
        ).toJson(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ElicitRequestParams.fromJson({
          'mode': 'url',
          'message': 'Please authenticate',
          'url': 'https://oauth.example.com/authorize',
          'elicitationId': 'oauth-123',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams(
          message: 'Please authenticate',
          requestedSchema: const JsonObject(properties: {}),
          url: 'https://oauth.example.com/authorize',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('JsonRpcElicitationCompleteNotification serialization', () {
      final notification = JsonRpcElicitationCompleteNotification(
        completeParams: const ElicitationCompleteParams(
          elicitationId: 'oauth-123',
        ),
      );

      final json = notification.toJson();
      expect(json['method'], equals('notifications/elicitation/complete'));
      expect(json['params']['elicitationId'], equals('oauth-123'));

      final parsed = JsonRpcElicitationCompleteNotification.fromJson(json);
      expect(parsed.completeParams.elicitationId, equals('oauth-123'));
    });

    test('URLElicitationRequiredError code', () {
      expect(ErrorCode.urlElicitationRequired.value, equals(-32042));
    });

    test('Form elicitation accepts spec primitive schema variants', () {
      final request = ElicitRequestParams.fromJson({
        'mode': 'form',
        'message': 'Configure deployment',
        'requestedSchema': {
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'type': 'object',
          'properties': {
            'email': {
              'type': 'string',
              'format': 'email',
              'title': 'Email',
              'description': 'Contact address',
              'default': 'ops@example.com',
              'minLength': 3,
              'maxLength': 320,
            },
            'size': {
              'type': 'string',
              'oneOf': [
                {'const': 'small', 'title': 'Small'},
                {'const': 'large', 'title': 'Large'},
              ],
            },
            'region': {
              'type': 'string',
              'enum': ['iad', 'sfo'],
              'enumNames': ['Virginia', 'California'],
            },
            'replicas': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 10,
              'default': 2,
            },
            'ratio': {
              'type': 'number',
              'minimum': 0,
              'maximum': 1,
            },
            'confirmed': {
              'type': 'boolean',
              'default': false,
            },
            'features': {
              'type': 'array',
              'minItems': 1,
              'maxItems': 2,
              'default': ['logs'],
              'items': {
                'type': 'string',
                'enum': ['logs', 'metrics'],
              },
            },
            'permissions': {
              'type': 'array',
              'items': {
                'anyOf': [
                  {'const': 'read', 'title': 'Read'},
                  {'const': 'write', 'title': 'Write'},
                ],
              },
            },
          },
          'required': ['email', 'region'],
        },
      });

      expect(request.isFormMode, isTrue);
      expect(request.toJson()['requestedSchema'], isA<Map<String, dynamic>>());
    });

    test('Form elicitation accepts numeric number schema keywords', () {
      Map<String, dynamic> requestWithProperty(
        String name,
        Map<String, dynamic> property,
      ) =>
          {
            'message': 'Configure deployment',
            'requestedSchema': {
              'type': 'object',
              'properties': {name: property},
            },
          };

      for (final property in <String, Map<String, dynamic>>{
        'fractionalNumberDefault': {
          'type': 'number',
          'default': 0.5,
        },
        'fractionalNumberMinimum': {
          'type': 'number',
          'minimum': 0.1,
        },
        'fractionalNumberMaximum': {
          'type': 'number',
          'maximum': 0.9,
        },
        'fractionalIntegerDefault': {
          'type': 'integer',
          'default': 1.5,
        },
        'fractionalIntegerMinimum': {
          'type': 'integer',
          'minimum': 1.5,
        },
        'fractionalIntegerMaximum': {
          'type': 'integer',
          'maximum': 10.5,
        },
      }.entries) {
        final params = ElicitRequestParams.fromJson(
          requestWithProperty(property.key, property.value),
        );
        expect(
          params.requestedSchema!.toJson()['properties'][property.key],
          containsPair(property.value.keys.last, property.value.values.last),
        );
      }

      final serialized = ElicitRequestParams.form(
        message: 'Configure deployment',
        requestedSchema: JsonSchema.object(
          properties: {
            'ratio': JsonSchema.number(
              minimum: 0.1,
              maximum: 0.9,
              defaultValue: 0.5,
            ),
          },
        ),
      ).toJson();
      final ratioSchema = serialized['requestedSchema']['properties']['ratio'];
      expect(ratioSchema['minimum'], 0.1);
      expect(ratioSchema['maximum'], 0.9);
      expect(ratioSchema['default'], 0.5);

      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('notFinite', {
            'type': 'number',
            'default': double.nan,
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('Draft form elicitation accepts numeric number schema keywords', () {
      final params = {
        'mode': 'form',
        'message': 'Configure deployment',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'ratio': {
              'type': 'number',
              'minimum': 0.1,
              'maximum': 0.9,
              'default': 0.5,
            },
            'count': {
              'type': 'integer',
              'minimum': 0.5,
              'maximum': 10.5,
              'default': 1.5,
            },
          },
        },
      };

      final parsed = ElicitRequestParams.fromJson(
        params,
        protocolVersion: draftProtocolVersion2026_07_28,
      );
      final parsedJson = parsed.toJson(
        protocolVersion: draftProtocolVersion2026_07_28,
      );
      expect(
        parsedJson['requestedSchema']['properties']['ratio']['minimum'],
        0.1,
      );
      expect(
        parsedJson['requestedSchema']['properties']['count']['maximum'],
        10.5,
      );

      final serialized = ElicitRequestParams.form(
        message: 'Configure deployment',
        requestedSchema: JsonSchema.object(
          properties: {
            'ratio': JsonSchema.number(
              minimum: 0.1,
              maximum: 0.9,
              defaultValue: 0.5,
            ),
          },
        ),
      ).toJson(protocolVersion: draftProtocolVersion2026_07_28);
      expect(
        serialized['requestedSchema']['properties']['ratio']['default'],
        0.5,
      );

      final request = JsonRpcElicitRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': 1,
        'method': Method.elicitationCreate,
        'params': {
          ...params,
          '_meta': {McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28},
        },
      });
      expect(
        request.toJson()['params']['requestedSchema']['properties']['count']
            ['minimum'],
        0.5,
      );

      expect(
        () => JsonRpcElicitRequest.fromJson({
          'jsonrpc': jsonRpcVersion,
          'id': 1,
          'method': Method.elicitationCreate,
          'params': {
            'mode': 'form',
            'message': 'Configure deployment',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'ratio': {
                  'type': 'number',
                  'maximum': double.infinity,
                },
              },
            },
            '_meta': {
              McpMetaKey.protocolVersion: draftProtocolVersion2026_07_28,
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('Form elicitation rejects non-spec schema shapes', () {
      Map<String, dynamic> requestWithProperty(
        String name,
        Object? property, {
        Object? required = const <String>['value'],
      }) =>
          {
            'message': 'Invalid schema',
            'requestedSchema': {
              'type': 'object',
              'properties': {name: property},
              if (required != null) 'required': required,
            },
          };

      expect(
        () => ElicitRequestParams.form(
          message: 'Bad root',
          requestedSchema: JsonSchema.string(),
        ).toJson(),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson({
          'message': 'Missing properties',
          'requestedSchema': {'type': 'object'},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', 'not-a-schema'),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson({
          'message': 'Bad required',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'value': {'type': 'string'},
            },
            'required': ['value', 1],
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson({
          'message': 'Bad schema URI',
          'requestedSchema': {
            r'$schema': 2020,
            'type': 'object',
            'properties': {
              'value': {'type': 'string'},
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
      for (final property in <String, Map<String, dynamic>>{
        'badStringTitle': {
          'type': 'string',
          'title': 1,
        },
        'badStringDefault': {
          'type': 'string',
          'default': false,
        },
        'badStringMinLength': {
          'type': 'string',
          'minLength': 1.5,
        },
        'badNumberDefault': {
          'type': 'number',
          'default': '0',
        },
        'badIntegerDefault': {
          'type': 'integer',
          'default': double.nan,
        },
        'badBooleanDefault': {
          'type': 'boolean',
          'default': 'false',
        },
        'badArrayDefault': {
          'type': 'array',
          'default': ['ok', 1],
          'items': {
            'type': 'string',
            'enum': ['ok'],
          },
        },
        'badArrayMinItems': {
          'type': 'array',
          'minItems': '1',
          'items': {
            'type': 'string',
            'enum': ['ok'],
          },
        },
      }.entries) {
        expect(
          () => ElicitRequestParams.fromJson(
            requestWithProperty(property.key, property.value),
          ),
          throwsA(isA<FormatException>()),
        );
      }
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'object',
            'properties': {},
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'string',
            'pattern': '^x',
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'string',
            'format': 'uuid',
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'string',
            'enum': ['ok', 1],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'string',
            'enumNames': ['Ok', 1],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'string',
            'enumNames': ['Ok'],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ElicitRequestParams.form(
          message: 'Bad enum names',
          requestedSchema: JsonObject(
            properties: {
              'value': JsonString(enumNames: ['Ok']),
            },
          ),
        ).toJson(),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'string',
            'oneOf': [
              {'const': 'ok'},
            ],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'array',
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'array',
            'items': {
              'type': 'string',
              'enum': ['ok', 1],
            },
          }),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitRequestParams.fromJson(
          requestWithProperty('value', {
            'type': 'array',
            'items': {
              'anyOf': [
                {'const': 'ok'},
              ],
            },
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('ElicitResult validates accepted content wire values', () {
      final parsed = ElicitResult.fromJson({
        'action': 'accept',
        'content': {
          'text': 'value',
          'count': 3.0,
          'ratio': 0.5,
          'confirmed': true,
          'selections': ['a', 'b'],
        },
        '_meta': {'trace': 'abc'},
      });

      expect(parsed.toJson()['content'], containsPair('count', 3));
      expect(parsed.toJson()['content'], containsPair('ratio', 0.5));
      expect(parsed.toJson()['_meta'], containsPair('trace', 'abc'));

      expect(
        () => ElicitResult.fromJson({
          'action': 'accept',
          'content': ['not', 'an', 'object'],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitResult.fromJson({
          'action': 'accept',
          'content': {
            'nested': {'value': true},
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ElicitResult.fromJson({
          'action': 'decline',
          'content': {
            'name': 'Alice',
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ElicitResult(
          action: 'accept',
          content: {
            'values': [1, 2],
          },
        ).toJson(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        const ElicitResult(
          action: 'accept',
          content: {
            'ratio': 0.5,
          },
        ).toJson()['content'],
        containsPair('ratio', 0.5),
      );
      expect(
        const ElicitResult(
          action: 'accept',
          content: {
            'count': 3.0,
          },
        ).toJson()['content'],
        containsPair('count', 3),
      );
      expect(
        () => const ElicitResult(
          action: 'cancel',
          content: {
            'name': 'Alice',
          },
        ).toJson(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('URLElicitationRequiredErrorData validates URL-only entries', () {
      final data = URLElicitationRequiredErrorData.fromJson({
        'elicitations': [
          {
            'mode': 'url',
            'message': 'Authenticate',
            'url': 'https://oauth.example.com/authorize',
            'elicitationId': 'oauth-123',
          },
        ],
      });

      expect(data.elicitations.single.isUrlMode, isTrue);
      expect(data.toJson()['elicitations'], hasLength(1));

      expect(
        () => URLElicitationRequiredErrorData.fromJson({}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => URLElicitationRequiredErrorData.fromJson({
          'elicitations': [
            {
              'message': 'Enter value',
              'requestedSchema': {
                'type': 'object',
                'properties': {
                  'value': {'type': 'string'},
                },
              },
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => URLElicitationRequiredErrorData(
          elicitations: [
            ElicitRequestParams.form(
              message: 'Enter value',
              requestedSchema: JsonObject(
                properties: {'value': JsonSchema.string()},
              ),
            ),
          ],
        ).toJson(),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Note: enumNames is not standard JSON Schema 2020-12, usually handled via oneOf with const/title
    // or custom extensions. Assuming simple enum for now.
  });
}
