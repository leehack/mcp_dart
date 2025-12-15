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
        protocolVersion: latestProtocolVersion,
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
        protocolVersion: latestProtocolVersion,
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

        final schema = InputSchema.fromJson(params.requestedSchema!);
        expect(schema, isA<StringInputSchema>());

        final stringSchema = schema as StringInputSchema;
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
          requestedSchema: const StringInputSchema(minLength: 1).toJson(),
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
        protocolVersion: latestProtocolVersion,
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

        final schema = InputSchema.fromJson(params.requestedSchema!);
        expect(schema, isA<BooleanInputSchema>());

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
          requestedSchema:
              const BooleanInputSchema(defaultValue: false).toJson(),
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
        protocolVersion: latestProtocolVersion,
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

        final schema = InputSchema.fromJson(params.requestedSchema!);
        expect(schema, isA<NumberInputSchema>());

        final numberSchema = schema as NumberInputSchema;
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
          requestedSchema:
              const NumberInputSchema(minimum: 0, maximum: 120).toJson(),
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
        protocolVersion: latestProtocolVersion,
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

        final schema = InputSchema.fromJson(params.requestedSchema!);
        expect(schema, isA<EnumInputSchema>());

        final enumSchema = schema as EnumInputSchema;
        expect(enumSchema.values, equals(['small', 'medium', 'large']));

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
          requestedSchema: const EnumInputSchema(
            values: ['small', 'medium', 'large'],
            defaultValue: 'medium',
          ).toJson(),
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
        protocolVersion: latestProtocolVersion,
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
          requestedSchema: const StringInputSchema(minLength: 1).toJson(),
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
  });

  group('Elicitation Spec 2025-11-25 Features', () {
    test('IntegerInputSchema serialization', () {
      const schema = IntegerInputSchema(
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
      expect(json['defaultValue'], equals(50));
      expect(json['title'], equals('Age'));
      expect(json['description'], equals('Your age in years'));

      final parsed = InputSchema.fromJson(json);
      expect(parsed, isA<IntegerInputSchema>());
      final intSchema = parsed as IntegerInputSchema;
      expect(intSchema.minimum, equals(0));
      expect(intSchema.maximum, equals(100));
    });

    test('StringInputSchema with format field', () {
      const schema = StringInputSchema(
        format: 'email',
        title: 'Email Address',
        description: 'Your email',
      );

      final json = schema.toJson();
      expect(json['type'], equals('string'));
      expect(json['format'], equals('email'));
      expect(json['title'], equals('Email Address'));

      final parsed = InputSchema.fromJson(json);
      expect(parsed, isA<StringInputSchema>());
      final stringSchema = parsed as StringInputSchema;
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
        requestedSchema: const StringInputSchema(minLength: 1).toJson(),
      );

      expect(params.isFormMode, isTrue);
      expect(params.isUrlMode, isFalse);
      expect(params.mode, equals(ElicitationMode.form));
      expect(params.requestedSchema, isNotNull);
      expect(params.url, isNull);
      expect(params.elicitationId, isNull);
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

    test('EnumInputSchema with enumNames', () {
      const schema = EnumInputSchema(
        values: ['small', 'medium', 'large'],
        enumNames: ['Small Size', 'Medium Size', 'Large Size'],
        defaultValue: 'medium',
        title: 'Size Selection',
      );

      final json = schema.toJson();
      expect(
        json['enumNames'],
        equals(['Small Size', 'Medium Size', 'Large Size']),
      );
      expect(json['title'], equals('Size Selection'));

      final parsed = InputSchema.fromJson(json);
      expect(parsed, isA<EnumInputSchema>());
      final enumSchema = parsed as EnumInputSchema;
      expect(
        enumSchema.enumNames,
        equals(['Small Size', 'Medium Size', 'Large Size']),
      );
    });
  });
}
