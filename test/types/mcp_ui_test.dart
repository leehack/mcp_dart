import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('McpUiExtensionCapability', () {
    test('serializes and deserializes mime types', () {
      const capability = McpUiExtensionCapability(
        mimeTypes: [
          mcpUiResourceMimeType,
        ],
      );

      final json = capability.toJson();
      expect(json['mimeTypes'], equals([mcpUiResourceMimeType]));

      final restored = McpUiExtensionCapability.fromJson(json);
      expect(restored.supportsMimeType(mcpUiResourceMimeType), isTrue);
      expect(restored.supportsMimeType('application/json'), isFalse);
    });

    test('withMcpUiExtension adds extension while preserving existing keys',
        () {
      final merged = withMcpUiExtension(
        extensions: {
          'io.modelcontextprotocol/other': {
            'enabled': true,
          },
        },
      );

      expect(merged['io.modelcontextprotocol/other']?['enabled'], isTrue);
      expect(
        merged[mcpUiExtensionId]?['mimeTypes'],
        equals([mcpUiResourceMimeType]),
      );
    });

    test('ClientCapabilities helper reads ui extension', () {
      final caps = ClientCapabilities(
        extensions: withMcpUiExtension(),
      );

      expect(caps.mcpUiExtension, isNotNull);
      expect(caps.supportsMcpUiMimeType(), isTrue);
    });

    test('ServerCapabilities helper reads ui extension', () {
      final caps = ServerCapabilities(
        extensions: withMcpUiExtension(),
      );

      expect(caps.mcpUiExtension, isNotNull);
      expect(caps.supportsMcpUiMimeType(), isTrue);
    });
  });

  group('McpUiToolMeta', () {
    test('parses nested ui metadata from tool _meta', () {
      const tool = Tool(
        name: 'get_weather',
        inputSchema: JsonObject(),
        meta: {
          'ui': {
            'resourceUri': 'ui://weather/dashboard',
            'visibility': ['model', 'app'],
          },
        },
      );

      final uiMeta = tool.mcpUiMeta;
      expect(uiMeta, isNotNull);
      expect(uiMeta!.resourceUri, equals('ui://weather/dashboard'));
      expect(uiMeta.visibility, equals(['model', 'app']));
      expect(uiMeta.isVisibleToModel, isTrue);
      expect(uiMeta.isVisibleToApp, isTrue);
    });

    test('parses deprecated ui/resourceUri fallback', () {
      const tool = Tool(
        name: 'legacy_tool',
        inputSchema: JsonObject(),
        meta: {
          mcpUiLegacyResourceUriMetaKey: 'ui://legacy/dashboard',
        },
      );

      final uiMeta = tool.mcpUiMeta;
      expect(uiMeta, isNotNull);
      expect(uiMeta!.resourceUri, equals('ui://legacy/dashboard'));
    });

    test('toToolMeta merges with existing metadata', () {
      const uiMeta = McpUiToolMeta(
        resourceUri: 'ui://weather/dashboard',
        visibility: ['app'],
      );

      final merged = uiMeta.toToolMeta({
        'custom': true,
      });

      expect(merged['custom'], isTrue);
      expect(merged['ui']['resourceUri'], equals('ui://weather/dashboard'));
      expect(merged['ui']['visibility'], equals(['app']));
    });
  });

  group('McpUiResourceMeta', () {
    test('parses ui metadata from resource _meta', () {
      const resource = Resource(
        uri: 'ui://weather/dashboard',
        name: 'Weather Dashboard',
        mimeType: mcpUiResourceMimeType,
        meta: {
          'ui': {
            'csp': {
              'connectDomains': ['https://api.example.com'],
            },
            'permissions': {
              'geolocation': {},
            },
            'prefersBorder': true,
          },
        },
      );

      final uiMeta = resource.mcpUiMeta;
      expect(uiMeta, isNotNull);
      expect(uiMeta!.csp?.connectDomains, equals(['https://api.example.com']));
      expect(uiMeta.permissions?.geolocation, isTrue);
      expect(uiMeta.prefersBorder, isTrue);
    });

    test('typed metadata is available on resource templates', () {
      const template = ResourceTemplate(
        uriTemplate: 'ui://weather/{location}',
        name: 'Weather UI',
        meta: {
          'ui': {
            'domain': 'apps.example.com',
          },
        },
      );

      expect(template.mcpUiMeta, isNotNull);
      expect(template.mcpUiMeta!.domain, equals('apps.example.com'));
    });

    test('typed metadata is available on resource contents', () {
      const content = TextResourceContents(
        uri: 'ui://weather/dashboard',
        mimeType: mcpUiResourceMimeType,
        text: '<!doctype html>',
        meta: {
          'ui': {
            'domain': 'apps.example.com',
            'prefersBorder': false,
          },
        },
      );

      final uiMeta = content.mcpUiMeta;
      expect(uiMeta, isNotNull);
      expect(uiMeta!.domain, equals('apps.example.com'));
      expect(uiMeta.prefersBorder, isFalse);
    });

    test('toMeta nests metadata under ui key', () {
      const uiMeta = McpUiResourceMeta(
        domain: 'apps.example.com',
        prefersBorder: true,
      );

      final meta = uiMeta.toMeta({
        'custom': true,
      });

      expect(meta['custom'], isTrue);
      expect(meta['ui']['domain'], equals('apps.example.com'));
      expect(meta['ui']['prefersBorder'], isTrue);
    });
  });
}
