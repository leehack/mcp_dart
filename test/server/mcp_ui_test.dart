import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class _TestTransport implements Transport {
  final List<JsonRpcMessage> sentMessages = <JsonRpcMessage>[];

  bool _closed = false;

  @override
  String? get sessionId => 'test-session';

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  void receiveMessage(JsonRpcMessage message) {
    onmessage?.call(message);
  }

  @override
  Future<void> close() async {
    _closed = true;
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (_closed) {
      throw StateError('Transport is closed');
    }
    sentMessages.add(message);
  }

  @override
  Future<void> start() async {
    if (_closed) {
      throw StateError('Cannot start closed transport');
    }
  }
}

void main() {
  group('MCP Apps server helpers', () {
    late McpServer server;
    late _TestTransport transport;

    setUp(() {
      server = McpServer(
        const Implementation(name: 'test-server', version: '1.0.0'),
      );
      transport = _TestTransport();
    });

    tearDown(() async {
      await server.close();
    });

    test('registerAppTool fills legacy ui/resourceUri metadata', () async {
      registerAppTool(
        server,
        'weather',
        const McpUiAppToolConfig(
          description: 'Weather tool',
          meta: {
            'ui': {
              'resourceUri': 'ui://weather/view.html',
            },
          },
        ),
        (args, extra) async => const CallToolResult(content: []),
      );

      await server.connect(transport);

      transport.receiveMessage(const JsonRpcListToolsRequest(id: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final tools = response.result['tools'] as List<dynamic>;
      final tool = tools.first as Map<String, dynamic>;
      final meta = tool['_meta'] as Map<String, dynamic>;

      expect(meta[mcpUiLegacyResourceUriMetaKey], 'ui://weather/view.html');
      expect(meta['ui']['resourceUri'], 'ui://weather/view.html');
    });

    test('registerAppTool fills nested ui.resourceUri from legacy key',
        () async {
      registerAppTool(
        server,
        'weather-legacy',
        const McpUiAppToolConfig(
          description: 'Weather tool with legacy metadata',
          meta: {
            mcpUiLegacyResourceUriMetaKey: 'ui://weather/view.html',
          },
        ),
        (args, extra) async => const CallToolResult(content: []),
      );

      await server.connect(transport);

      transport.receiveMessage(const JsonRpcListToolsRequest(id: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final tools = response.result['tools'] as List<dynamic>;
      final tool = tools.first as Map<String, dynamic>;
      final meta = tool['_meta'] as Map<String, dynamic>;

      expect(meta[mcpUiLegacyResourceUriMetaKey], 'ui://weather/view.html');
      expect(meta['ui']['resourceUri'], 'ui://weather/view.html');
    });

    test('registerAppResource defaults mime type and keeps list metadata',
        () async {
      registerAppResource(
        server,
        'Weather UI',
        'ui://weather/view.html',
        const McpUiAppResourceConfig(
          description: 'Weather app UI',
          meta: {
            'ui': {
              'prefersBorder': true,
            },
          },
        ),
        (uri, extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(
                uri: uri.toString(),
                mimeType: mcpUiResourceMimeType,
                text: '<!doctype html>',
              ),
            ],
          );
        },
      );

      await server.connect(transport);

      transport.receiveMessage(JsonRpcListResourcesRequest(id: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final response = transport.sentMessages.last as JsonRpcResponse;
      final resources = response.result['resources'] as List<dynamic>;
      final resource = resources.first as Map<String, dynamic>;

      expect(resource['mimeType'], mcpUiResourceMimeType);
      expect(resource['_meta']['ui']['prefersBorder'], isTrue);
    });
  });

  group('MCP Apps capability helper', () {
    test('getUiCapability returns extension settings', () {
      final caps = ClientCapabilities(
        extensions: withMcpUiExtension(),
      );

      final uiCapability = getUiCapability(caps);

      expect(uiCapability, isNotNull);
      expect(uiCapability!.supportsMimeType(mcpUiResourceMimeType), isTrue);
    });

    test('getUiCapability supports server capabilities values', () {
      final caps = ServerCapabilities(
        extensions: withMcpUiExtension(),
      );

      final uiCapability = getUiCapability(caps);

      expect(uiCapability, isNotNull);
      expect(uiCapability!.supportsMimeType(mcpUiResourceMimeType), isTrue);
    });
  });
}
